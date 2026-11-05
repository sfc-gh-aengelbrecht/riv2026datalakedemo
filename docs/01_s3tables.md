# 1. Streaming into Amazon S3 Tables

A Lambda (`riv-demo-s3t-microbatch`) replays 2,000 activity rows from `rawdata.new_activity`
into `rivdemo_ingest.activity` in the S3 table bucket `riv-demo-2026-s3t`: 50 rows per
Iceberg commit, one commit about every 10 s. Snowflake reads the bucket through a read-only
catalog-linked database that syncs every 30 s.

## Steps in Snowsight (role RIV_DEMO_RL)
1. Run `sql/01_s3tables/01_catalog_integration.sql`, copy `API_AWS_IAM_USER_ARN` /
   `API_AWS_EXTERNAL_ID`, request trust (see `docs/00_onboarding.md`).
2. After trust is added, run `sql/01_s3tables/02_catalog_linked_db.sql`.
   Within about 60 s Database Explorer shows `RIV_DEMO_S3T_DB` with schemas `rawdata` and
   `rivdemo_ingest`.
3. Run `sql/01_s3tables/03_verify.sql`.
   - `source_rows` is 2000.
   - The batch query lists the latest batches per `run_id` / `batch_seq`.

## Show the stream live
1. Ask the Lambda operator to start a run (or start it yourself if you have the operator
   policy):
   ```bash
   aws lambda invoke --profile <profile> --function-name riv-demo-s3t-microbatch \
     --invocation-type Event --cli-binary-format raw-in-base64-out \
     --payload '{"batch_size":50,"wait_seconds":10}' /dev/null
   ```
2. Rerun the batch query in `03_verify.sql` every 30 s. New batches arrive in groups of
   about 3 (one CLD sync). A full run is 40 batches, about 8 minutes.
3. Stop early by setting SSM parameter `/riv-demo/s3t-microbatch/stop` to `true`.

Console steps, resume and single-batch options: `aws/lambda/s3t_microbatch/README.md`.

## Notes
- Only one run can be active at a time. Someone else may already be streaming; check the
  batch query before starting.
- The CLD is `ALLOWED_WRITE_OPERATIONS = NONE`, so you cannot `DELETE` or `INSERT` from
  your account. Resetting the table is an admin task.
- Namespaces and columns are lowercase: `RIV_DEMO_S3T_DB."rivdemo_ingest"."activity"`.
- Pattern 3 and the semantic view read `rivdemo_ingest.activity`, so keep this CLD in place.
