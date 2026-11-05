#!/usr/bin/env bash
# Adds one Snowflake integration / external volume to the trust policy of the user's
# demo role. Each Snowflake object has its own ExternalId, so run once per object.
# Usage: bash aws_trust.sh --user <lower_snake> <snowflake_iam_user_arn> <external_id>
#   Both values come from DESC CATALOG INTEGRATION / DESC EXTERNAL VOLUME in Snowflake.
set -euo pipefail
source "$(dirname "$0")/common.sh"

[ $# -eq 4 ] && [ "$1" = --user ] || { echo "Usage: $0 --user <lower_snake> <iam_user_arn> <external_id>" >&2; exit 1; }
validate_user "$2"
ROLE=$(role_name "$2")

check_account
CURRENT=$(awsp iam get-role --role-name "$ROLE" --query Role.AssumeRolePolicyDocument --output json)

# Values are passed as argv, never interpolated into code.
NEW=$(python3 - "$3" "$4" "$CURRENT" <<'PY'
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
  echo "Already trusted: $3 / $4"
  exit 0
fi

run awsp iam update-assume-role-policy --role-name "$ROLE" --policy-document "$NEW"
echo "Added trust for $3 (ExternalId $4) on $ROLE. Allow ~10s for IAM to propagate before verifying in Snowflake."
