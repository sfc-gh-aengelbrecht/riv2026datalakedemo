#!/usr/bin/env bash
# Adds a Snowflake integration / external volume to the trust policy of riv-demo-2026-shared-role.
# Usage: bash add_snowflake_trust.sh <snowflake_iam_user_arn> <external_id>
#   Both values come from DESC INTEGRATION / DESC EXTERNAL VOLUME in Snowflake.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: bash $0 <snowflake_iam_user_arn> <external_id>" >&2
  exit 1
fi

PROFILE="${PROFILE:-sesandbox}"
ROLE=riv-demo-2026-shared-role

CURRENT=$(aws iam get-role --profile "$PROFILE" --role-name "$ROLE" \
  --query Role.AssumeRolePolicyDocument --output json)

# Values are passed as argv, never interpolated into code.
NEW=$(python3 - "$1" "$2" "$CURRENT" <<'PY'
import json, sys
arn, ext_id, doc = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
if not arn.startswith("arn:aws:iam::"):
    sys.exit(f"Not an IAM ARN: {arn}")
for s in doc["Statement"]:
    if (s.get("Principal", {}).get("AWS") == arn and
            s.get("Condition", {}).get("StringEquals", {}).get("sts:ExternalId") == ext_id):
        sys.exit(0)  # already trusted; print nothing
doc["Statement"].append({
    "Effect": "Allow",
    "Principal": {"AWS": arn},
    "Action": "sts:AssumeRole",
    "Condition": {"StringEquals": {"sts:ExternalId": ext_id}},
})
print(json.dumps(doc))
PY
)

if [ -z "$NEW" ]; then
  echo "Already trusted: $1 / $2"
  exit 0
fi

aws iam update-assume-role-policy --profile "$PROFILE" --role-name "$ROLE" --policy-document "$NEW"
echo "Added trust for $1 (ExternalId $2). Allow ~10s for IAM to propagate before verifying in Snowflake."
