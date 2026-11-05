#!/usr/bin/env bash
# Starts the shared micro-batch Lambda, but only if no run is active.
# Usage: bash lambda_start.sh [batch_size] [wait_seconds] [start_rowid]
#   defaults: 50 rows every 10 s, replay from rowid 1 (a full run is ~8 min)
#   Runs as profile riv-demo-deployer (set up by deployer_access.sh).
set -euo pipefail
HERE="$(dirname "$0")"
export PROFILE="${PROFILE:-riv-demo-deployer}"
source "$HERE/common.sh"

BATCH_SIZE="${1:-50}" WAIT_SECONDS="${2:-10}" START_ROWID="${3:-1}"
for v in "$BATCH_SIZE" "$WAIT_SECONDS" "$START_ROWID"; do
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "Arguments must be integers" >&2; exit 1; }
done

set +e
STATUS=$(bash "$HERE/lambda_status.sh")
CODE=$?
set -e
echo "$STATUS"
if [ "$CODE" -eq 2 ]; then
  echo "Not starting: a run is already active. Wait for it, or stop it with lambda_stop.sh and wait for IDLE." >&2
  exit 2
elif [ "$CODE" -ne 0 ]; then
  echo "Could not determine Lambda status; not starting." >&2
  exit 1
fi

PAYLOAD="{\"batch_size\":$BATCH_SIZE,\"wait_seconds\":$WAIT_SECONDS,\"start_rowid\":$START_ROWID}"
# Async invoke. Reserved concurrency 1 also throttles a second concurrent start.
run awsp lambda invoke --function-name "$LAMBDA" --invocation-type Event \
  --cli-binary-format raw-in-base64-out --payload "$PAYLOAD" /dev/null
echo "Started $LAMBDA with $PAYLOAD. Watch: bash $HERE/lambda_status.sh  or  aws logs tail $LOG_GROUP --follow --profile $PROFILE"
