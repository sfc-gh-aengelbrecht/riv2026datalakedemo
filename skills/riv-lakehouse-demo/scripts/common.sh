# Shared settings for the riv-lakehouse-demo scripts. Sourced, not run.
PROFILE="${PROFILE:-sesandbox}"
REGION=us-west-2
ACCOUNT=484577546576

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
SHARED_POLICIES="$REPO_DIR/aws/shared_role"

LAMBDA=riv-demo-s3t-microbatch
LOG_GROUP=/aws/lambda/$LAMBDA
STOP_PARAM=/riv-demo/s3t-microbatch/stop

# Lambda scripts run as the shared deployer role (logs, stop flag, invoke).
# deployer_access.sh adds the user to its trust and creates this profile.
DEPLOYER_ROLE=riv-demo-s3t-deployer-role
DEPLOYER_ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${DEPLOYER_ROLE}"
DEPLOYER_PROFILE=riv-demo-deployer

S3T_POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/riv-demo-s3t-snowflake-access"
OPERATOR_POLICY_ARN="arn:aws:iam::${ACCOUNT}:policy/riv-demo-s3t-microbatch-operator"
GLUE_DB=rivdemo_2026
GLUE_DATA_BUCKET=riv-demo-2026-w2

awsp() { ${AWS_BIN:-aws} --profile "$PROFILE" --region "$REGION" "$@"; }  # AWS_BIN: test override (word-split on purpose)

# DRYRUN=1 prints mutating commands (to stderr, so output redirects don't hide them).
run() {
  if [ "${DRYRUN:-0}" = 1 ]; then
    { printf 'DRYRUN:'; printf ' %q' "$@"; echo; } >&2
  else
    "$@"
  fi
}

check_account() {
  local acct
  acct=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
  if [ "$acct" != "$ACCOUNT" ]; then
    echo "Profile $PROFILE is account $acct, expected SE Sandbox $ACCOUNT" >&2
    exit 1
  fi
}

role_name() { echo "riv-demo-2026-${1//_/-}-role"; }

validate_user() {
  [[ "$1" =~ ^[a-z][a-z0-9_]{1,19}$ ]] || { echo "user must be lower_snake, 2-20 chars: $1" >&2; exit 1; }
}
