#!/usr/bin/env bash
# Asks the running micro-batch Lambda to stop after its current batch.
# The next run resets the flag itself. Usage: bash lambda_stop.sh (profile riv-demo-deployer)
set -euo pipefail
PROFILE="${PROFILE:-riv-demo-deployer}"
source "$(dirname "$0")/common.sh"

run awsp ssm put-parameter --name "$STOP_PARAM" --value true --overwrite >/dev/null
echo "Stop flag set. The run exits within ~10-14 s and logs run_end; check with lambda_status.sh."
