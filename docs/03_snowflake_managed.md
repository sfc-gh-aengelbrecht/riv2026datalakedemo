# 3. Snowflake-managed Iceberg (dynamic Iceberg table)

Snowflake writes its own Iceberg v2 tables to `s3://riv-demo-2026-snow-w2/<your_prefix>/`.
The dynamic Iceberg table `ACTIVITY_AGG_DIT` joins the S3 Tables stream (pattern 1) with the
Glue master data (pattern 2) and refreshes incrementally with a 1-minute target lag.

Requires patterns 1 and 2.

## Steps in Snowsight (role RIV_DEMO_RL)
1. Open `sql/03_snow_managed/01_external_volume.sql`, replace `__user_prefix__` with your
   prefix, and run it. Copy `STORAGE_AWS_IAM_USER_ARN` / `STORAGE_AWS_EXTERNAL_ID` from the
   `STORAGE_LOCATION_1` JSON and request trust.
2. After trust is added, run `sql/03_snow_managed/02_database_dynamic_iceberg.sql`.
   This creates database `RIV2026DL_SNOW`, schemas `DYNAMIC_ICEBERG` and `DL_ANALYTICS`, and
   the dynamic table. `INITIALIZE = ON_CREATE` runs the first refresh during create.
3. Run `sql/03_snow_managed/03_verify.sql`.
   - Refresh history shows `SUCCEEDED`, `refresh_action` `INCREMENTAL` (or `NO_DATA`).
   - While the Lambda streams, a new `LOAD_MINUTE` appears roughly every minute.

## What to point out
- End-to-end latency: Lambda commit -> CLD sync (30 s) -> DT refresh (1 min).
  Compare `LAST_LOADED_AT` with the current time.
- The table files are plain Iceberg in your S3 prefix; the S3 console shows `data/` and
  `metadata/` under `dynamic_iceberg/activity_agg_dit/`.
- `ICEBERG_VERSION = 2` keeps it readable by external engines such as Athena.

## Notes
- The dynamic table uses `RIV_DEMO_WH`. Suspend it when you are done
  (`ALTER DYNAMIC TABLE ... SUSPEND`) or run `sql/99_teardown.sql`.
- Do not change the external volume `STORAGE_BASE_URL` to another user's prefix.
