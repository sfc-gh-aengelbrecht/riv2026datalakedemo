#!/usr/bin/env bash
# Creates riv-demo-2026-shared-role: Snowflake data access for the RIV 2026 demo
# plus start/stop/monitor of the micro-batch Lambda (no change/delete). Safe to re-run.
# Runs as the sandbox user (profile sesandbox, Lake Formation admin).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${PROFILE:-sesandbox}"
REGION=us-west-2
ACCOUNT=484577546576
ROLE=riv-demo-2026-shared-role
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"
PROFILE_FOR_IDENTITY="$PROFILE"; source "$HERE/../admin_identity.sh"
TAGS="Key=owner,Value=${OWNER} Key=demo,Value=riv-2026"

iam() { aws iam --profile "$PROFILE" "$@"; }
lf()  { aws lakeformation --profile "$PROFILE" --region "$REGION" "$@"; }

echo "== 1. Role"
# Never overwrite trust on re-run: Snowflake statements are added by add_snowflake_trust.sh.
iam get-role --role-name "$ROLE" >/dev/null 2>&1 || \
  iam create-role --role-name "$ROLE" --max-session-duration 7200 \
    --description "RIV 2026 shared Snowflake demo role (data access + start/stop/monitor micro-batch)" \
    --assume-role-policy-document "$(trust_doc "$HERE/trust.json")" --tags $TAGS >/dev/null

echo "== 2. Inline policies"
for p in riv-demo-2026-datalake-access riv-demo-2026-datalake-s3 riv-demo-2026-snow-extvol-s3; do
  iam put-role-policy --role-name "$ROLE" --policy-name "$p" --policy-document "file://$HERE/$p.json"
done

echo "== 3. Managed policies"
for p in riv-demo-s3t-snowflake-access riv-demo-s3t-microbatch-operator; do
  iam attach-role-policy --role-name "$ROLE" --policy-arn "arn:aws:iam::${ACCOUNT}:policy/$p"
done

echo "== 4. Lake Formation grants"
sleep 10  # let the new role propagate before LF validates the principal
lf grant-permissions --principal "DataLakePrincipalIdentifier=$ROLE_ARN" \
  --resource "{\"DataLocation\":{\"ResourceArn\":\"arn:aws:s3:::riv-demo-2026-w2\"}}" \
  --permissions DATA_LOCATION_ACCESS
lf grant-permissions --principal "DataLakePrincipalIdentifier=$ROLE_ARN" \
  --resource '{"Database":{"Name":"rivdemo_2026"}}' \
  --permissions CREATE_TABLE ALTER DESCRIBE
lf grant-permissions --principal "DataLakePrincipalIdentifier=$ROLE_ARN" \
  --resource '{"Table":{"DatabaseName":"rivdemo_2026","TableWildcard":{}}}' \
  --permissions SELECT INSERT DELETE ALTER DESCRIBE

echo "Done: $ROLE_ARN"
