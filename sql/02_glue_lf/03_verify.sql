-- Pattern 2, step 3: verify the Glue tables and prove writes work through Lake Formation
-- Expected counts: item 1032, location 13, retailer_metadata 12.

USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

SELECT 'item' AS tbl, COUNT(*) AS row_count FROM RIV2026DATALAKEDEMO."rivdemo_2026"."item"
UNION ALL SELECT 'location', COUNT(*) FROM RIV2026DATALAKEDEMO."rivdemo_2026"."location"
UNION ALL SELECT 'retailer_metadata', COUNT(*) FROM RIV2026DATALAKEDEMO."rivdemo_2026"."retailer_metadata";

-- Write round trip in a scratch table named after your prefix (letters, digits, underscore only).
-- BASE_LOCATION must be a full s3:// path for Glue catalog-linked tables.
CREATE ICEBERG TABLE RIV2026DATALAKEDEMO."rivdemo_2026"."__user_prefix___scratch" (id INT, note STRING)
  BASE_LOCATION = 's3://riv-demo-2026-w2/rivdemo_2026/__user_prefix___scratch/';
INSERT INTO RIV2026DATALAKEDEMO."rivdemo_2026"."__user_prefix___scratch" VALUES (1, 'written from Snowflake');
SELECT * FROM RIV2026DATALAKEDEMO."rivdemo_2026"."__user_prefix___scratch";
DROP ICEBERG TABLE RIV2026DATALAKEDEMO."rivdemo_2026"."__user_prefix___scratch";
