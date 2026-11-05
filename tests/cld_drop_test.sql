-- Throwaway test: does DROP DATABASE on a catalog-linked database propagate to the remote catalog?
-- Uses a scratch Glue database (rivtest_droptest) so the shared rivdemo_2026 tables are never at risk.
-- Prerequisites (see tests/E2E_TEST.md, step 7):
--   aws glue create-database --profile sesandbox --region us-west-2 \
--     --database-input '{"Name":"rivtest_droptest","LocationUri":"s3://riv-demo-2026-w2/rivtest_droptest/"}'
--   Lake Formation: grant riv-demo-2026-shared-role ALL on database rivtest_droptest
--   (and data location s3://riv-demo-2026-w2/rivtest_droptest/ if not already covered).
-- Requires RIVTEST_GLUE_CAT_INT from the E2E test (pattern 2).

USE ROLE RIV_DEMO_RL;
USE WAREHOUSE RIVTEST_WH;

-- 1. Throwaway CLD with writes enabled, so a drop *could* propagate
CREATE DATABASE RIVTEST_DROPTEST_DB
  LINKED_CATALOG = (
    CATALOG = 'RIVTEST_GLUE_CAT_INT'
    ALLOWED_NAMESPACES = ('rivtest_droptest')
    NAMESPACE_MODE = IGNORE_NESTED_NAMESPACE
    SYNC_INTERVAL_SECONDS = 30
    ALLOWED_WRITE_OPERATIONS = ALL);

SELECT SYSTEM$CATALOG_LINK_STATUS('RIVTEST_DROPTEST_DB');

-- 2. Create a table through the CLD (lands in Glue)
CREATE ICEBERG TABLE RIVTEST_DROPTEST_DB."rivtest_droptest"."t1" (id INT)
  BASE_LOCATION = 's3://riv-demo-2026-w2/rivtest_droptest/t1/';
INSERT INTO RIVTEST_DROPTEST_DB."rivtest_droptest"."t1" VALUES (1);

-- Check in AWS before dropping (expect t1 listed):
--   aws glue get-tables --profile sesandbox --region us-west-2 --database-name rivtest_droptest --query 'TableList[].Name'

-- 3a. Drop with writes still ALL (worst case)
DROP DATABASE RIVTEST_DROPTEST_DB;

-- Check in AWS again. Record the result in docs/troubleshooting.md:
--   t1 still listed     -> DROP DATABASE does not propagate; teardown is safe as written
--   t1 / database gone  -> DROP DATABASE propagates; ALLOWED_WRITE_OPERATIONS = NONE before drop is mandatory (test 3b)

-- 3b. Only if 3a propagated: repeat steps 1-2, then make it read-only before dropping
-- ALTER DATABASE RIVTEST_DROPTEST_DB UPDATE LINKED_CATALOG SET ALLOWED_WRITE_OPERATIONS = NONE;
-- DROP DATABASE RIVTEST_DROPTEST_DB;
-- Check in AWS: t1 should still be listed.

-- 4. AWS cleanup when done:
--   aws glue delete-table    --profile sesandbox --region us-west-2 --database-name rivtest_droptest --name t1
--   aws glue delete-database --profile sesandbox --region us-west-2 --name rivtest_droptest
--   aws s3 rm --profile sesandbox --recursive s3://riv-demo-2026-w2/rivtest_droptest/
