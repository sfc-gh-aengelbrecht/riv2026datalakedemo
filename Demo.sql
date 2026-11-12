-- =====================================================================
-- 1. Setup: role and warehouse
-- =====================================================================
USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

-- =====================================================================
-- 2. Iceberg tables in S3, managed by AWS Glue
--    Catalog integration: RIV_DEMO_2026_GLUE_CAT_INT
-- =====================================================================
SHOW ICEBERG TABLES IN SCHEMA RIV2026DATALAKEDEMO."rivdemo_2026";

SELECT * FROM RIV2026DATALAKEDEMO."rivdemo_2026"."item" LIMIT 10;

SELECT * FROM RIV2026DATALAKEDEMO."rivdemo_2026"."location" LIMIT 10;

SELECT * FROM RIV2026DATALAKEDEMO."rivdemo_2026"."retailer_metadata" LIMIT 10;

-- =====================================================================
-- 3. Amazon S3 Tables Iceberg table
--    Catalog integration: RIV_DEMO_S3T_CAT_INT
-- =====================================================================
SELECT * FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity" LIMIT 100;

-- Re-run during the demo to show the row count growing
SELECT COUNT(*) AS row_count, CURRENT_TIMESTAMP() AS checked_at
FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity";

-- Optional: pull the latest snapshot from the catalog on demand
-- ALTER ICEBERG TABLE RIV_DEMO_S3T_DB."rivdemo_ingest"."activity" REFRESH;

-- =====================================================================
-- 4. Snowflake-managed dynamic Iceberg table
--    External volume: RIV_DEMO_2026_SNOW_EXT_VOL
-- =====================================================================
-- Target lag, refresh mode, scheduling state and row count
SHOW DYNAMIC TABLES IN SCHEMA RIV2026DL_SNOW.DYNAMIC_ICEBERG;

SELECT COUNT(*) AS row_count, CURRENT_TIMESTAMP() AS checked_at
FROM RIV2026DL_SNOW.DYNAMIC_ICEBERG.ACTIVITY_AGG_DIT;

SELECT * FROM RIV2026DL_SNOW.DYNAMIC_ICEBERG.ACTIVITY_AGG_DIT LIMIT 100;

-- Latest refreshes
SELECT name, state, refresh_action, refresh_start_time, refresh_end_time
FROM TABLE(RIV2026DL_SNOW.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
       NAME => 'RIV2026DL_SNOW.DYNAMIC_ICEBERG.ACTIVITY_AGG_DIT'))
ORDER BY refresh_start_time DESC
LIMIT 10;
