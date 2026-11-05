#!/usr/bin/env bash
# Deploys the RIV S3 Tables micro-batch demo. Safe to re-run.
#   Step 1 (IAM) runs as the sandbox user (profile sesandbox).
#   Remaining steps run as riv-demo-s3t-deployer-role (profile riv-demo-deployer).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REGION=us-west-2
ACCOUNT=484577546576
USER_PROFILE="${USER_PROFILE:-sesandbox}"
DEPLOY_PROFILE="${DEPLOY_PROFILE:-riv-demo-deployer}"

FUNCTION=riv-demo-s3t-microbatch
LAMBDA_ROLE=riv-demo-s3t-lambda-role
DEPLOYER_ROLE=riv-demo-s3t-deployer-role
OPERATOR_POLICY=riv-demo-s3t-microbatch-operator
STOP_PARAM=/riv-demo/s3t-microbatch/stop
TABLE_BUCKET_ARN="arn:aws:s3tables:${REGION}:${ACCOUNT}:bucket/riv-demo-2026-s3t"
PROFILE_FOR_IDENTITY="$USER_PROFILE"; source "$HERE/../../admin_identity.sh"
TAGS="Key=owner,Value=${OWNER} Key=demo,Value=riv-2026"

iam() { aws iam --profile "$USER_PROFILE" "$@"; }
dep() { aws --profile "$DEPLOY_PROFILE" --region "$REGION" "$@"; }

echo "== 1. IAM roles and policies"
iam get-role --role-name "$DEPLOYER_ROLE" >/dev/null 2>&1 || \
  iam create-role --role-name "$DEPLOYER_ROLE" --max-session-duration 7200 \
    --assume-role-policy-document "$(trust_doc "$HERE/deployer-trust.json")" --tags $TAGS >/dev/null
iam put-role-policy --role-name "$DEPLOYER_ROLE" --policy-name riv-demo-s3t-deployer \
  --policy-document "file://$HERE/deployer-policy.json"

iam get-role --role-name "$LAMBDA_ROLE" >/dev/null 2>&1 || \
  iam create-role --role-name "$LAMBDA_ROLE" \
    --assume-role-policy-document "file://$HERE/lambda-trust.json" --tags $TAGS >/dev/null
iam put-role-policy --role-name "$LAMBDA_ROLE" --policy-name riv-demo-s3t-lambda \
  --policy-document "file://$HERE/lambda-role-policy.json"
iam attach-role-policy --role-name "$LAMBDA_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

OPERATOR_ARN="arn:aws:iam::${ACCOUNT}:policy/${OPERATOR_POLICY}"
iam get-policy --policy-arn "$OPERATOR_ARN" >/dev/null 2>&1 || \
  iam create-policy --policy-name "$OPERATOR_POLICY" \
    --policy-document "file://$HERE/operator-policy.json" \
    --description "Start/stop/watch the RIV S3 Tables micro-batch demo" >/dev/null

OPERATOR_ROLE=riv-demo-s3t-microbatch-operator-role
iam get-role --role-name "$OPERATOR_ROLE" >/dev/null 2>&1 || \
  iam create-role --role-name "$OPERATOR_ROLE" --max-session-duration 7200 \
    --description "Start/stop/monitor the RIV S3 Tables micro-batch Lambda" \
    --assume-role-policy-document "$(trust_doc "$HERE/operator-trust.json")" --tags $TAGS >/dev/null
iam attach-role-policy --role-name "$OPERATOR_ROLE" --policy-arn "$OPERATOR_ARN"

echo "== 2. SSM stop flag"
dep ssm get-parameter --name "$STOP_PARAM" >/dev/null 2>&1 || \
  dep ssm put-parameter --name "$STOP_PARAM" --type String --value false \
    --description "Set true to stop the RIV S3 Tables micro-batch demo loop" --tags $TAGS >/dev/null

echo "== 3. PyIceberg layer"
[ -f "$HERE/build/pyiceberg-layer.zip" ] || bash "$HERE/build_layer.sh"
LAYER_ARN=$(dep lambda list-layer-versions --layer-name riv-demo-pyiceberg \
  --query 'LayerVersions[0].LayerVersionArn' --output text 2>/dev/null || true)
if [ -z "$LAYER_ARN" ] || [ "$LAYER_ARN" = "None" ] || [ "${REPUBLISH_LAYER:-0}" = "1" ]; then
  LAYER_ARN=$(dep lambda publish-layer-version --layer-name riv-demo-pyiceberg \
    --description "pyiceberg + pyarrow (S3-enabled) for python3.12 arm64" \
    --compatible-runtimes python3.12 --compatible-architectures arm64 \
    --zip-file "fileb://$HERE/build/pyiceberg-layer.zip" --query LayerVersionArn --output text)
fi
echo "   $LAYER_ARN"

echo "== 4. Lambda function"
python3 - "$HERE" <<'PY'
import sys, zipfile, pathlib
here = pathlib.Path(sys.argv[1])
with zipfile.ZipFile(here / "build" / "function.zip", "w", zipfile.ZIP_DEFLATED) as z:
    z.write(here / "handler.py", "handler.py")
PY
ENV="Variables={TABLE_BUCKET_ARN=${TABLE_BUCKET_ARN},REGION=${REGION},SRC=rawdata.new_activity,TGT=rivdemo_ingest.activity,BATCH_SIZE=50,WAIT_SECONDS=10,STOP_PARAM=${STOP_PARAM}}"
if dep lambda get-function --function-name "$FUNCTION" >/dev/null 2>&1; then
  dep lambda update-function-code --function-name "$FUNCTION" \
    --zip-file "fileb://$HERE/build/function.zip" >/dev/null
  dep lambda wait function-updated --function-name "$FUNCTION"
  dep lambda update-function-configuration --function-name "$FUNCTION" \
    --layers "$LAYER_ARN" --timeout 900 --memory-size 1024 \
    --environment "$ENV" >/dev/null
else
  dep lambda create-function --function-name "$FUNCTION" \
    --runtime python3.12 --architectures arm64 --handler handler.handler \
    --role "arn:aws:iam::${ACCOUNT}:role/${LAMBDA_ROLE}" \
    --zip-file "fileb://$HERE/build/function.zip" \
    --layers "$LAYER_ARN" --timeout 900 --memory-size 1024 \
    --environment "$ENV" --tags "owner=${OWNER},demo=riv-2026" >/dev/null
fi
dep lambda wait function-updated --function-name "$FUNCTION"

echo "== 5. One run at a time, no async retries"
dep lambda put-function-concurrency --function-name "$FUNCTION" \
  --reserved-concurrent-executions 1 >/dev/null
dep lambda put-function-event-invoke-config --function-name "$FUNCTION" \
  --maximum-retry-attempts 0 --maximum-event-age-in-seconds 60 >/dev/null

echo "Done: arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FUNCTION}"
