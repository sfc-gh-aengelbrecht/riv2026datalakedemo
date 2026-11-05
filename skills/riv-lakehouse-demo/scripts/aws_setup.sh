#!/usr/bin/env bash
# Creates the per-user AWS objects for the RIV lakehouse demo in the SE Sandbox:
#   - S3 bucket for Snowflake-managed Iceberg (external volume)
#   - IAM role riv-demo-2026-<user>-role with Glue/LF, S3 Tables, user bucket and
#     Lambda start/stop/monitor access
#   - Lake Formation grants on the shared Glue database rivdemo_2026
# Safe to re-run; never resets the role trust policy after creation.
# Usage: bash aws_setup.sh --user <lower_snake> --bucket <bucket-name>
#   DRYRUN=1 prints the mutating commands instead of running them.
set -euo pipefail
source "$(dirname "$0")/common.sh"

USER_PREFIX="" BUCKET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --user) USER_PREFIX="$2"; shift 2 ;;
    --bucket) BUCKET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$USER_PREFIX" ] && [ -n "$BUCKET" ] || { echo "Usage: $0 --user <lower_snake> --bucket <bucket-name>" >&2; exit 1; }
validate_user "$USER_PREFIX"
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] || { echo "Invalid bucket name: $BUCKET" >&2; exit 1; }

ROLE=$(role_name "$USER_PREFIX")
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"
OWNER=$(aws sts get-caller-identity --profile "$PROFILE" --query Arn --output text)
TAGS="Key=owner,Value=${USER_PREFIX} Key=demo,Value=riv-2026"

check_account

echo "== 1. Bucket s3://$BUCKET"
if awsp s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "exists"
else
  run awsp s3api create-bucket --bucket "$BUCKET" \
    --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
fi
# New buckets block public access by default, and the sandbox SCP denies changing it,
# so only check. Try to set it only if it is somehow not fully blocked.
PAB=$(awsp s3api get-public-access-block --bucket "$BUCKET" --output text \
  --query 'PublicAccessBlockConfiguration.[BlockPublicAcls,IgnorePublicAcls,BlockPublicPolicy,RestrictPublicBuckets]' 2>/dev/null || echo unknown)
if [[ "$PAB" == $'True\tTrue\tTrue\tTrue' ]]; then
  echo "public access blocked"
elif [ "${DRYRUN:-0}" != 1 ] || [ "$PAB" != unknown ]; then
  run awsp s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    || echo "WARNING: could not set public access block (current: $PAB)" >&2
fi
run awsp s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
run awsp s3api put-bucket-tagging --bucket "$BUCKET" \
  --tagging "TagSet=[{Key=owner,Value=${USER_PREFIX}},{Key=demo,Value=riv-2026}]"

echo "== 2. Role $ROLE"
if awsp iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  echo "exists (trust policy left unchanged)"
else
  # Initial trust: the SE's own sandbox principal, so they can assume the role to run
  # the Lambda. Snowflake principals are added later by aws_trust.sh.
  TRUST=$(python3 - "$OWNER" <<'PY'
import json, re, sys
arn = sys.argv[1]
m = re.fullmatch(r"arn:aws:sts::(\d{12}):assumed-role/([^/]+)/.+", arn)
if m:  # SSO / assumed-role session -> trust the role itself
    arn = f"arn:aws:iam::{m.group(1)}:role/{m.group(2)}"
print(json.dumps({"Version": "2012-10-17", "Statement": [{
    "Sid": "SandboxUser", "Effect": "Allow",
    "Principal": {"AWS": arn}, "Action": "sts:AssumeRole"}]}))
PY
)
  run awsp iam create-role --role-name "$ROLE" --max-session-duration 7200 \
    --description "RIV 2026 demo role for ${USER_PREFIX} (Snowflake data access + start/stop/monitor micro-batch)" \
    --assume-role-policy-document "$TRUST" --tags $TAGS >/dev/null
fi

echo "== 3. Inline policies"
run awsp iam put-role-policy --role-name "$ROLE" --policy-name riv-demo-2026-datalake-access \
  --policy-document "file://$SHARED_POLICIES/riv-demo-2026-datalake-access.json"
run awsp iam put-role-policy --role-name "$ROLE" --policy-name riv-demo-2026-datalake-s3 \
  --policy-document "file://$SHARED_POLICIES/riv-demo-2026-datalake-s3.json"
BUCKET_POLICY=$(sed "s/__BUCKET__/$BUCKET/g" "$SKILL_DIR/templates/user-bucket-policy.json.tmpl")
run awsp iam put-role-policy --role-name "$ROLE" --policy-name riv-demo-2026-user-extvol-s3 \
  --policy-document "$BUCKET_POLICY"

echo "== 4. Managed policies (S3 Tables access, Lambda operator)"
for p in "$S3T_POLICY_ARN" "$OPERATOR_POLICY_ARN"; do
  run awsp iam attach-role-policy --role-name "$ROLE" --policy-arn "$p"
done

echo "== 5. Lake Formation grants"
[ "${DRYRUN:-0}" = 1 ] || sleep 10  # let a new role propagate before LF validates the principal
PRINCIPAL="DataLakePrincipalIdentifier=$ROLE_ARN"
run awsp lakeformation grant-permissions --principal "$PRINCIPAL" \
  --resource "{\"DataLocation\":{\"ResourceArn\":\"arn:aws:s3:::${GLUE_DATA_BUCKET}\"}}" \
  --permissions DATA_LOCATION_ACCESS
run awsp lakeformation grant-permissions --principal "$PRINCIPAL" \
  --resource "{\"Database\":{\"Name\":\"${GLUE_DB}\"}}" \
  --permissions CREATE_TABLE ALTER DESCRIBE
run awsp lakeformation grant-permissions --principal "$PRINCIPAL" \
  --resource "{\"Table\":{\"DatabaseName\":\"${GLUE_DB}\",\"TableWildcard\":{}}}" \
  --permissions SELECT INSERT DELETE ALTER DESCRIBE

if [ "${DRYRUN:-0}" != 1 ]; then
  echo "== 6. Verify Lake Formation grants"
  MISSING=0
  for res in "{\"DataLocation\":{\"ResourceArn\":\"arn:aws:s3:::${GLUE_DATA_BUCKET}\"}}" \
             "{\"Database\":{\"Name\":\"${GLUE_DB}\"}}" \
             "{\"Table\":{\"DatabaseName\":\"${GLUE_DB}\",\"TableWildcard\":{}}}"; do
    PERMS=$(awsp lakeformation list-permissions --principal "$PRINCIPAL" --resource "$res" \
      --query 'PrincipalResourcePermissions[].Permissions[]' --output text)
    echo "$res -> ${PERMS:-NONE}"
    [ -n "$PERMS" ] || MISSING=1
  done
  [ "$MISSING" = 0 ] || { echo "Lake Formation grant missing; see above." >&2; exit 1; }
fi

echo "Done: role $ROLE_ARN, bucket s3://$BUCKET"
