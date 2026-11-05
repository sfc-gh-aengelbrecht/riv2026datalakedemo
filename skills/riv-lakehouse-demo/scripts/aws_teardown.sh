#!/usr/bin/env bash
# Removes the per-user AWS objects created by aws_setup.sh: Lake Formation grants,
# the IAM role and the bucket (all object versions). Shared demo data is not touched.
# Usage: bash aws_teardown.sh --user <lower_snake> --bucket <bucket-name> --confirm
#   DRYRUN=1 prints the mutating commands instead of running them.
set -euo pipefail
source "$(dirname "$0")/common.sh"

USER_PREFIX="" BUCKET="" CONFIRM=0
while [ $# -gt 0 ]; do
  case "$1" in
    --user) USER_PREFIX="$2"; shift 2 ;;
    --bucket) BUCKET="$2"; shift 2 ;;
    --confirm) CONFIRM=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$USER_PREFIX" ] && [ -n "$BUCKET" ] || { echo "Usage: $0 --user <lower_snake> --bucket <bucket-name> --confirm" >&2; exit 1; }
validate_user "$USER_PREFIX"
[ "$CONFIRM" = 1 ] || [ "${DRYRUN:-0}" = 1 ] || { echo "Add --confirm to delete role $(role_name "$USER_PREFIX") and bucket $BUCKET" >&2; exit 1; }

ROLE=$(role_name "$USER_PREFIX")
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"
check_account

# Refuse to delete the shared demo buckets by mistake.
case "$BUCKET" in riv-demo-2026-w2|riv-demo-2026-snow-w2|riv-demo-2026-s3t)
  echo "Refusing to delete shared bucket $BUCKET" >&2; exit 1 ;;
esac

echo "== 1. Lake Formation grants"
PRINCIPAL="DataLakePrincipalIdentifier=$ROLE_ARN"
run awsp lakeformation revoke-permissions --principal "$PRINCIPAL" \
  --resource "{\"Table\":{\"DatabaseName\":\"${GLUE_DB}\",\"TableWildcard\":{}}}" \
  --permissions SELECT INSERT DELETE ALTER DESCRIBE || true
run awsp lakeformation revoke-permissions --principal "$PRINCIPAL" \
  --resource "{\"Database\":{\"Name\":\"${GLUE_DB}\"}}" \
  --permissions CREATE_TABLE ALTER DESCRIBE || true
run awsp lakeformation revoke-permissions --principal "$PRINCIPAL" \
  --resource "{\"DataLocation\":{\"ResourceArn\":\"arn:aws:s3:::${GLUE_DATA_BUCKET}\"}}" \
  --permissions DATA_LOCATION_ACCESS || true

echo "== 2. Role $ROLE"
if awsp iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  for p in $(awsp iam list-role-policies --role-name "$ROLE" --query 'PolicyNames[]' --output text); do
    run awsp iam delete-role-policy --role-name "$ROLE" --policy-name "$p"
  done
  for p in $(awsp iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyArn' --output text); do
    run awsp iam detach-role-policy --role-name "$ROLE" --policy-arn "$p"
  done
  run awsp iam delete-role --role-name "$ROLE"
else
  echo "not found"
fi

echo "== 3. Bucket s3://$BUCKET"
if awsp s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  # Versioned bucket: delete every version and delete marker, 1000 at a time.
  while :; do
    BATCH=$(awsp s3api list-object-versions --bucket "$BUCKET" --max-items 1000 --output json \
      --query '{Objects: [Versions[].{Key:Key,VersionId:VersionId}, DeleteMarkers[].{Key:Key,VersionId:VersionId}][] }')
    COUNT=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1]).get("Objects") or []))' "$BATCH")
    [ "$COUNT" -gt 0 ] || break
    if [ "${DRYRUN:-0}" = 1 ]; then echo "DRYRUN: delete $COUNT object versions"; break; fi
    awsp s3api delete-objects --bucket "$BUCKET" --delete "$BATCH" >/dev/null
  done
  run awsp s3api delete-bucket --bucket "$BUCKET"
else
  echo "not found"
fi

echo "Done."
