-- Pattern 1, step 3: verify and watch the micro-batch stream
-- Namespaces and columns are lowercase in S3 Tables, so quote them.

USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

-- Source rows the Lambda replays (2000 rows)
SELECT COUNT(*) AS source_rows FROM RIV_DEMO_S3T_DB."rawdata"."new_activity";

-- Batch progress: rerun while the Lambda is running; new batches land every ~30 s
SELECT "run_id", "batch_seq", COUNT(*) AS row_count,
       MIN("rowid") AS rowid_from, MAX("rowid") AS rowid_to,
       MIN("insert_timestamp") AS inserted_at
FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity"
GROUP BY 1, 2
ORDER BY 2 DESC
LIMIT 20;
