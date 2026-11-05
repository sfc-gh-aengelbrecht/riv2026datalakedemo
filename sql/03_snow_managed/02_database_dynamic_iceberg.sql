-- Pattern 3, step 2: Snowflake-managed Iceberg database and a dynamic Iceberg table
-- Requires patterns 1 and 2: the table joins the S3 Tables stream with the Glue dimensions.
-- Run only after the sandbox admin has added the external volume trust entry.

USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('RIV_DEMO_2026_SNOW_EXT_VOL');

CREATE DATABASE IF NOT EXISTS RIV2026DL_SNOW
  EXTERNAL_VOLUME = 'RIV_DEMO_2026_SNOW_EXT_VOL'
  CATALOG = 'SNOWFLAKE';
CREATE SCHEMA IF NOT EXISTS RIV2026DL_SNOW.DYNAMIC_ICEBERG;
CREATE SCHEMA IF NOT EXISTS RIV2026DL_SNOW.DL_ANALYTICS;

-- Iceberg v2 keeps the table readable by Athena.
CREATE DYNAMIC ICEBERG TABLE IF NOT EXISTS RIV2026DL_SNOW.DYNAMIC_ICEBERG.ACTIVITY_AGG_DIT
  TARGET_LAG = '1 minute'
  REFRESH_MODE = INCREMENTAL
  INITIALIZE = ON_CREATE
  WAREHOUSE = RIV_DEMO_WH
  EXTERNAL_VOLUME = 'RIV_DEMO_2026_SNOW_EXT_VOL'
  CATALOG = 'SNOWFLAKE'
  ICEBERG_VERSION = 2
  BASE_LOCATION = 'dynamic_iceberg/activity_agg_dit/'
AS
SELECT
    DATE_TRUNC('minute', a."insert_timestamp")::TIMESTAMP_NTZ(6) AS LOAD_MINUTE,
    a."period_ending_date"            AS PERIOD_ENDING_DATE,
    a."sps_retailer_name_key"         AS RETAILER_KEY,
    r."activitygrain"                 AS ACTIVITY_GRAIN,
    l."region"                        AS REGION,
    l."state"                         AS STATE,
    i."brand_name"                    AS BRAND_NAME,
    i."department_name"               AS DEPARTMENT_NAME,
    i."category_name"                 AS CATEGORY_NAME,
    COUNT(*)                          AS ROW_COUNT,
    SUM(a."gross_sales_units")        AS GROSS_SALES_UNITS,
    SUM(a."net_sales_units")          AS NET_SALES_UNITS,
    SUM(a."net_sales_retail")         AS NET_SALES_RETAIL,
    SUM(a."net_sales_cost")           AS NET_SALES_COST,
    SUM(a."net_sales_margin_value")   AS NET_MARGIN,
    SUM(a."customer_return_units")    AS RETURN_UNITS,
    SUM(a."total_markdown_values")    AS MARKDOWN_VALUE,
    SUM(a."inventory_units")          AS ON_HAND_UNITS,
    SUM(a."on_order_units")           AS ON_ORDER_UNITS,
    MAX(a."insert_timestamp")::TIMESTAMP_NTZ(6) AS LAST_LOADED_AT
FROM RIV_DEMO_S3T_DB."rivdemo_ingest"."activity" a
LEFT JOIN RIV2026DATALAKEDEMO."rivdemo_2026"."item" i
  ON a."sps_retailer_name_key" = i."sps_retailer_name_key"
 AND a."sps_customer_item_key" = i."sps_customer_item_key"
LEFT JOIN RIV2026DATALAKEDEMO."rivdemo_2026"."location" l
  ON a."sps_retailer_name_key" = l."sps_retailer_name_key"
 AND a."sps_customer_location_key" = l."sps_customer_location_key"
LEFT JOIN RIV2026DATALAKEDEMO."rivdemo_2026"."retailer_metadata" r
  ON a."sps_retailer_name_key" = r."sps_retailer_name_key"
GROUP BY ALL;
