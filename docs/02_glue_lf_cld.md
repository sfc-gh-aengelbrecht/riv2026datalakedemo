# 2. AWS Glue Data Catalog + Lake Formation

Master data (1,032 items, 13 locations, 12 retailers) lives as Iceberg v2 tables in Glue database
`rivdemo_2026`. Lake Formation governs access and vends short-lived S3 credentials to Snowflake. The
catalog-linked database is writable, so Snowflake can also create tables in Glue.

## Steps in Snowsight (role RIV_DEMO_RL)
1. Run `sql/02_glue_lf/01_catalog_integration.sql`, copy `API_AWS_IAM_USER_ARN` / `API_AWS_EXTERNAL_ID`, request trust.
2. After trust is added, run `sql/02_glue_lf/02_catalog_linked_db.sql`.
   Database Explorer shows `RIV2026DATALAKEDEMO` -> schema `rivdemo_2026` -> 3 Iceberg tables.
3. Open `sql/02_glue_lf/03_verify.sql`, replace `__user_prefix__` with your prefix, and run it.
   - Counts: item 1032, location 13, retailer_metadata 12.
   - The scratch table is created in Glue, written, read back and dropped. That proves writes through Lake Formation.
   - Optional: open the AWS Glue console during the scratch step to show the table appear in `rivdemo_2026`.

## Notes
- Glue identifiers are lowercase: always double-quote schema, table and column names.
- New tables need `BASE_LOCATION` with a full `s3://riv-demo-2026-w2/rivdemo_2026/...` path.
- Tables stay Iceberg v2 so Athena can read them.
