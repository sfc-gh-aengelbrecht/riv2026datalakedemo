#!/usr/bin/env bash
# Reports whether the shared micro-batch Lambda is running.
# Prints RUNNING or IDLE on the first line, then details.
# Exit code: 0 IDLE, 2 RUNNING, 1 UNKNOWN (logs not readable). Read-only.
# Usage: bash lambda_status.sh   (runs as profile riv-demo-deployer; see deployer_access.sh)
set -euo pipefail
PROFILE="${PROFILE:-riv-demo-deployer}"
source "$(dirname "$0")/common.sh"

# Lambda timeout is 900 s; look back 16 min so any live run's run_start is included.
START_MS=$(( ($(date +%s) - 960) * 1000 ))
if ! EVENTS=$(awsp logs filter-log-events --log-group-name "$LOG_GROUP" --start-time "$START_MS" \
  --filter-pattern '?run_start ?run_end ?batch_committed ?"END RequestId"' \
  --query 'events[].[timestamp,message]' --output json 2>&1); then
  echo "UNKNOWN"
  echo "Cannot read $LOG_GROUP with profile $PROFILE:"
  echo "$EVENTS" | tail -1
  echo "Run: bash $(dirname "$0")/deployer_access.sh   (adds you to the deployer role and creates profile riv-demo-deployer)"
  exit 1
fi
STOP_FLAG=$(awsp ssm get-parameter --name "$STOP_PARAM" --query Parameter.Value --output text 2>/dev/null || echo unknown)

python3 - "$EVENTS" "$STOP_FLAG" <<'PY'
import datetime, json, sys
events, stop_flag = json.loads(sys.argv[1] or "[]"), sys.argv[2]
events.sort(key=lambda e: e[0])

def ts(ms):
    return datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

def payload(msg):
    start = msg.find("{")
    try:
        return json.loads(msg[start:]) if start >= 0 else {}
    except ValueError:
        return {}

last_start = last_finish = last_batch = None
for t, msg in events:
    p = payload(msg)
    if p.get("event") == "run_start":
        last_start = (t, p)
    elif p.get("event") == "run_end" or msg.startswith("END RequestId"):
        last_finish = t
    elif p.get("event") == "batch_committed":
        last_batch = (t, p)

running = last_start is not None and (last_finish is None or last_finish < last_start[0])
print("RUNNING" if running else "IDLE")
if last_start:
    print(f"last run_start: {ts(last_start[0])} run_id={last_start[1].get('run_id', '?')}")
if last_batch:
    p = last_batch[1]
    print(f"last batch: {ts(last_batch[0])} batch_seq={p.get('batch_seq', '?')} "
          f"rowid {p.get('rowid_from', '?')}-{p.get('rowid_to', '?')}")
if not events:
    print("no run activity in the last 16 minutes")
print(f"stop flag: {stop_flag}")
sys.exit(2 if running else 0)
PY
