# End-to-end test

Runs the repo SQL with renamed objects (`RIVTEST_*`, user prefix `rivtest`) so it can sit next to the working demo install without touching it. The role `RIV_DEMO_RL` is shared with the real install.

All Snowflake steps run in a Snowsight worksheet (or `snow sql -f`). AWS steps use the `sesandbox` profile.

## 1. Render the SQL

```bash
python3 tests/render.py RIVTEST rivtest /tmp/rivtest_sql
grep -rE "RIV_DEMO_S3T|RIV_DEMO_2026_|RIV2026DATALAKEDEMO|RIV2026DL_SNOW|RIV_DEMO_WH|__user_prefix__" /tmp/rivtest_sql
```

The `grep` must return nothing.

## 2. Setup

Run `/tmp/rivtest_sql/00_setup_role_wh.sql` as ACCOUNTADMIN.

Check: `SHOW WAREHOUSES LIKE 'RIVTEST_WH';` returns one row.

## 3. Pattern 1: S3 Tables

1. Run `01_s3tables/01_catalog_integration.sql`. From the `DESC` output, note `API_AWS_IAM_USER_ARN` and `API_AWS_EXTERNAL_ID`.
2. Add trust:
   ```bash
   bash aws/shared_role/add_snowflake_trust.sh <API_AWS_IAM_USER_ARN> <API_AWS_EXTERNAL_ID>
   ```
   Wait about 10 seconds.
3. Run `01_s3tables/02_catalog_linked_db.sql`.
   - `SYSTEM$VERIFY_CATALOG_INTEGRATION` returns success.
   - Link status is RUNNING.
   - The tables `new_activity` and `activity` appear within about 60 seconds.
4. Start the Lambda (see `aws/lambda/s3t_microbatch/README.md`) and run `01_s3tables/03_verify.sql`.
   - `source_rows` = 2000.
   - Rerunning shows a new `batch_seq` about every 30 seconds.
5. Confirm the read-only setting: an `INSERT` into `RIVTEST_S3T_DB."rivdemo_ingest"."activity"` must fail.

## 4. Pattern 2: Glue and Lake Formation

1. Run `02_glue_lf/01_catalog_integration.sql`, then run `add_snowflake_trust.sh` with its ARN and external ID.
2. Run `02_glue_lf/02_catalog_linked_db.sql`. The tables `item`, `location` and `retailer_metadata` appear.
3. Run `02_glue_lf/03_verify.sql`.
   - Row counts: item 1032, location 13, retailer_metadata 12.
   - The scratch table `rivtest_scratch` is created, its insert reads back, and it is dropped.
   - In AWS, check that `rivtest_scratch` is gone and the shared tables are still listed:
     ```bash
     aws glue get-tables --profile sesandbox --region us-west-2 --database-name rivdemo_2026 --query 'TableList[].Name'
     ```

## 5. Pattern 3: Snowflake-managed Iceberg

1. Run `03_snow_managed/01_external_volume.sql`.
2. From `STORAGE_LOCATION_1`, take `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`, then run `add_snowflake_trust.sh` with them.
3. Run `03_snow_managed/02_database_dynamic_iceberg.sql`.
   - `SYSTEM$VERIFY_EXTERNAL_VOLUME` returns success.
   - The dynamic Iceberg table initializes. This needs patterns 1 and 2 in place.
4. Run `03_snow_managed/03_verify.sql`.
   - Refresh history shows SUCCEEDED.
   - Files exist under `s3://riv-demo-2026-snow-w2/rivtest/`:
     ```bash
     aws s3 ls --profile sesandbox --recursive s3://riv-demo-2026-snow-w2/rivtest/ | head
     ```

## 6. Analytics

1. Run `04_analytics/01_semantic_view.sql`. Check that `SHOW SEMANTIC VIEWS IN SCHEMA RIVTEST_SNOW_DB.DL_ANALYTICS;` returns a row.
2. Run `04_analytics/02_agent.sql`.
3. In Snowsight, open the agent **Retail Distribution Analyst** in `RIVTEST_SNOW_DB.DL_ANALYTICS`. Ask the sample questions:
   - "What are net sales and margin % by department?"
   - "Which retailers have the most units in transit right now?"

   Each should answer with data, and trends should return a chart.

## 7. DROP DATABASE on a catalog-linked database

Follow `tests/cld_drop_test.sql`. It uses a scratch Glue database `rivtest_droptest` and never touches the shared `rivdemo_2026` data. Record the outcome in `docs/troubleshooting.md` and adjust `sql/99_teardown.sql` if needed.

## 8. Teardown

1. Run `/tmp/rivtest_sql/99_teardown.sql`. Then confirm:
   - Nothing remains in Snowflake: `SHOW DATABASES LIKE 'RIVTEST%'`, `SHOW INTEGRATIONS LIKE 'RIVTEST%'`, `SHOW EXTERNAL VOLUMES LIKE 'RIVTEST%'`.
   - The shared data is intact. These still list the tables:
     ```bash
     aws glue get-tables --profile sesandbox --region us-west-2 --database-name rivdemo_2026 --query 'TableList[].Name'
     aws s3tables list-tables --profile sesandbox --region us-west-2 --table-bucket-arn arn:aws:s3tables:us-west-2:484577546576:bucket/riv-demo-2026-s3t
     ```
2. Remove the test files:
   ```bash
   aws s3 rm --profile sesandbox --recursive s3://riv-demo-2026-snow-w2/rivtest/
   ```
3. Optionally, remove the RIVTEST trust entries from `riv-demo-2026-shared-role`.

## Sign-off

- [ ] Steps 2 to 8 pass.
- [ ] Issues are fixed in `sql/`, `docs/`, `aws/`, and the SQL has been re-rendered.
- [ ] Reviewed and approved, then commit and push.
