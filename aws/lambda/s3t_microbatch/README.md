# RIV S3 Tables micro-batch demo

Replays `rawdata.new_activity` into `rivdemo_ingest.activity` (S3 table bucket
`riv-demo-2026-s3t`, us-west-2) in 50-row batches, one Iceberg commit every ~10 s.
Snowflake sees the data through the catalog-linked database `RIV_DEMO_S3T_DB`
(syncs every 30 s, so new batches appear in groups of ~3).

Each batch is stamped with:

| Column | Value |
|---|---|
| `period_ending_date` | UTC date of the batch |
| `insert_timestamp` | UTC time of the batch (same for every row in it) |
| `rowid` | copied from `new_activity` (1-2000) |
| `batch_seq` | global counter, continues across runs |
| `run_id` | UTC start time of the Lambda run |

Every run replays from `rowid` 1 unless you pass `start_rowid`, so rows repeat
across runs by design. A full run is 40 batches, ~8 minutes.

## AWS resources

| Resource | Name |
|---|---|
| Lambda function | `riv-demo-s3t-microbatch` (python3.12, arm64, 900 s timeout, reserved concurrency 1, async retries 0) |
| Layer | `riv-demo-pyiceberg` (pyiceberg 0.11.1 + pyarrow 20.0.0) |
| Stop flag | SSM parameter `/riv-demo/s3t-microbatch/stop` |
| Lambda role | `riv-demo-s3t-lambda-role` (S3 Tables on this bucket + the stop flag) |
| Deployer role | `riv-demo-s3t-deployer-role` (assumed by the deploying admin and SEs added with `skills/riv-lakehouse-demo/scripts/deployer_access.sh`; CLI profile `riv-demo-deployer`) |
| Operator policy | `riv-demo-s3t-microbatch-operator` (start, stop, watch only) |

## Giving another sandbox user access

Attach the operator policy to their IAM user or role:

- Console: IAM -> Users (or Roles) -> the user -> Add permissions -> Attach policies -> `riv-demo-s3t-microbatch-operator`
- CLI: `aws iam attach-user-policy --user-name <user> --policy-arn arn:aws:iam::484577546576:policy/riv-demo-s3t-microbatch-operator`

It allows reading/flipping the stop flag, invoking the function and reading its
logs. It does not allow deleting the flag or changing the function. Who flipped
the flag is visible in Parameter Store -> History and in CloudTrail.

## Run from the AWS console

**Start a full run**
1. Lambda -> `riv-demo-s3t-microbatch` -> **Test** tab.
2. Event JSON: `{"batch_size": 50, "wait_seconds": 10}` -> **Test**.
   The console waits for the run to finish (~8 min). The Lambda keeps running even if the browser gives up.

**Resume a stopped run**: same, with `{"start_rowid": 201}` (use the `next_rowid` the stopped run returned).

**Write a single batch**: `{"single": true}`.

**Watch**: CloudWatch -> Log groups -> `/aws/lambda/riv-demo-s3t-microbatch` -> latest stream.
Each batch logs a `batch_committed` line with `batch_seq`, `rowid_from`, `rowid_to`.

**Stop**: Systems Manager -> Parameter Store -> `/riv-demo/s3t-microbatch/stop` -> Edit -> value `true` -> Save.
The loop exits between batches within ~10-14 s. The next run resets the flag to `false` itself.

## Run from CoCo

Ask CoCo "start the micro-batch demo", "stop it", "resume from where it stopped",
or "show batch progress", or run the commands yourself (prefix with `!` in CoCo):

```bash
# Start (async, returns immediately)
aws lambda invoke --profile riv-demo-deployer --function-name riv-demo-s3t-microbatch \
  --invocation-type Event --cli-binary-format raw-in-base64-out \
  --payload '{"batch_size":50,"wait_seconds":10}' /dev/null

# Resume from a given rowid
aws lambda invoke --profile riv-demo-deployer --function-name riv-demo-s3t-microbatch \
  --invocation-type Event --cli-binary-format raw-in-base64-out \
  --payload '{"start_rowid":201}' /dev/null

# Stop
aws ssm put-parameter --profile riv-demo-deployer \
  --name /riv-demo/s3t-microbatch/stop --value true --overwrite

# Follow logs live
aws logs tail /aws/lambda/riv-demo-s3t-microbatch --follow --profile riv-demo-deployer
```

Operators using their own credentials can use the same commands with their own profile.

## Track progress in Snowflake

```sql
SELECT "run_id", "batch_seq", COUNT(*) AS row_count,
       MIN("rowid") AS rowid_from, MAX("rowid") AS rowid_to,
       MIN("insert_timestamp") AS inserted_at, MIN("period_ending_date") AS period_date
FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity"
GROUP BY 1, 2
ORDER BY 2 DESC;
```

## Start over with an empty table (optional)

Stop the loop first, then:

```sql
DELETE FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity";
```

`batch_seq` starts again at 1 on the next run.

## Notes

- Only one run can execute at a time; a second start while one is running is throttled.
- A stop never leaves a half-written batch: each batch is one atomic Iceberg commit.
- The run exits with `timeout_guard` if fewer than 30 s of its 15-minute limit remain.
- The AWS SDK for pandas layer is not used: its pyarrow lacks S3 support (`pyarrow._s3fs`), which pyiceberg needs.

## Redeploy

```bash
bash build_layer.sh                 # only when changing pyiceberg/pyarrow versions
REPUBLISH_LAYER=1 bash deploy.sh    # republish layer + update function
bash deploy.sh                      # update function code/config only
```
