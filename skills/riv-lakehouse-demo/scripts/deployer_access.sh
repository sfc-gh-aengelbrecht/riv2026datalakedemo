#!/usr/bin/env bash
# Gives the current sandbox user access to the shared Lambda through the deployer role
# riv-demo-s3t-deployer-role, and configures the AWS CLI profile riv-demo-deployer.
#   1. Adds the caller's principal to the deployer role trust (one shared statement).
#   2. Writes [profile riv-demo-deployer] to ~/.aws/config with `aws configure set`.
#   3. Verifies the profile can assume the role and read the Lambda logs.
# Safe to re-run. Runs as profile sesandbox (needs IAM rights on the deployer role).
# Usage: bash deployer_access.sh      DRYRUN=1 prints the mutating commands.
set -euo pipefail
source "$(dirname "$0")/common.sh"   # PROFILE defaults to sesandbox here

check_account
CALLER=$(aws sts get-caller-identity --profile "$PROFILE" --query Arn --output text)
CURRENT=$(awsp iam get-role --role-name "$DEPLOYER_ROLE" --query Role.AssumeRolePolicyDocument --output json)

# Values are passed as argv, never interpolated into code.
RESULT=$(python3 - "$CALLER" "$CURRENT" <<'PY'
import json, re, sys
arn, doc = sys.argv[1], json.loads(sys.argv[2])
m = re.fullmatch(r"arn:aws:sts::(\d{12}):assumed-role/([^/]+)/.+", arn)
if m:  # SSO / assumed-role session -> trust the role itself
    arn = f"arn:aws:iam::{m.group(1)}:role/{m.group(2)}"
if not re.fullmatch(r"arn:aws:iam::\d{12}:(user|role)/.+", arn):
    sys.exit(f"Unsupported caller principal: {arn}")

def principals(s):
    p = s.get("Principal", {}).get("AWS", [])
    return [p] if isinstance(p, str) else list(p)

for s in doc["Statement"]:
    if s.get("Effect") == "Allow" and arn in principals(s) and not s.get("Condition"):
        print(f"TRUSTED {arn}")
        sys.exit(0)

stmt = next((s for s in doc["Statement"] if s.get("Sid") == "RivDemoSEs"), None)
if stmt is None:
    stmt = {"Sid": "RivDemoSEs", "Effect": "Allow", "Principal": {"AWS": []}, "Action": "sts:AssumeRole"}
    doc["Statement"].append(stmt)
stmt["Principal"]["AWS"] = sorted(set(principals(stmt) + [arn]))
print(f"ADD {arn}")
print(json.dumps(doc, separators=(",", ":")))
PY
)

FIRST=$(echo "$RESULT" | head -1)
echo "== 1. Deployer role trust: ${FIRST#* } "
if [[ "$FIRST" == ADD* ]]; then
  NEW=$(echo "$RESULT" | sed -n 2p)
  if [ ${#NEW} -gt 2048 ]; then
    echo "Trust policy would be ${#NEW} chars (limit 2048). Ask the sandbox admin to raise the IAM quota or switch to an account-level trust." >&2
    exit 1
  fi
  run awsp iam update-assume-role-policy --role-name "$DEPLOYER_ROLE" --policy-document "$NEW"
  echo "added (allow ~10 s for IAM to propagate)"
else
  echo "already trusted"
fi

echo "== 2. AWS CLI profile $DEPLOYER_PROFILE"
run aws configure set role_arn "$DEPLOYER_ROLE_ARN" --profile "$DEPLOYER_PROFILE"
run aws configure set source_profile "$PROFILE" --profile "$DEPLOYER_PROFILE"
run aws configure set region "$REGION" --profile "$DEPLOYER_PROFILE"
run aws configure set role_session_name "riv-demo-$(whoami | tr -cd 'a-zA-Z0-9_-')" --profile "$DEPLOYER_PROFILE"

[ "${DRYRUN:-0}" = 1 ] && exit 0

echo "== 3. Verify"
for i in 1 2 3 4 5 6; do
  if aws sts get-caller-identity --profile "$DEPLOYER_PROFILE" --query Arn --output text 2>/dev/null; then
    aws logs describe-log-streams --profile "$DEPLOYER_PROFILE" --region "$REGION" \
      --log-group-name "$LOG_GROUP" --max-items 1 --query 'logStreams[0].logStreamName' --output text >/dev/null
    echo "OK: profile $DEPLOYER_PROFILE can assume $DEPLOYER_ROLE and read $LOG_GROUP"
    exit 0
  fi
  sleep 5
done
echo "Profile $DEPLOYER_PROFILE could not assume $DEPLOYER_ROLE yet; wait a minute and re-run this script." >&2
exit 1
