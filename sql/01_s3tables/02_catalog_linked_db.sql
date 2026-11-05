-- Pattern 1, step 2: catalog-linked database over the S3 table bucket
-- Run only after the sandbox admin has added your trust entry.

USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIV_DEMO_WH;

SELECT SYSTEM$VERIFY_CATALOG_INTEGRATION('RIV_DEMO_S3T_CAT_INT');

CREATE DATABASE IF NOT EXISTS RIV_DEMO_S3T_DB
  LINKED_CATALOG = (
    CATALOG = 'RIV_DEMO_S3T_CAT_INT'
    ALLOWED_NAMESPACES = ('rawdata', 'rivdemo_ingest')
    NAMESPACE_MODE = IGNORE_NESTED_NAMESPACE
    SYNC_INTERVAL_SECONDS = 30
    -- Read-only: the Lambda writes, Snowflake only reads. These tables are shared by all users.
    ALLOWED_WRITE_OPERATIONS = NONE);

-- Tables appear after the first sync (up to ~60 s).
SELECT SYSTEM$CATALOG_LINK_STATUS('RIV_DEMO_S3T_DB');
SHOW ICEBERG TABLES IN DATABASE RIV_DEMO_S3T_DB;
