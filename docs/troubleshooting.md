# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `SYSTEM$VERIFY_*` fails with AssumeRole / not authorized | Trust entry missing or the object was re-created (new ExternalId). Re-read DESC and re-request trust. Wait 10 s after the admin adds it. |
| Glue CLD shows no tables, or `loadTable` 403 "Access is not allowed" | Lake Formation: the bucket must be registered with the custom role `riv-demo-2026-datalake`, not the service-linked role. LF grants are on the shared role (admin: `aws/shared_role/create_shared_role.sh`). |
| New Glue database lets everyone in | Glue default DB permissions re-add `IAM_ALLOWED_PRINCIPALS`; revoke it in Lake Formation. |
| `CREATE ICEBERG TABLE` in the Glue CLD fails | Add `BASE_LOCATION = 's3://riv-demo-2026-w2/rivdemo_2026/<table>/'`. |
| Invalid identifier on Glue or S3 Tables objects | Lowercase plus double quotes: `"rivdemo_2026"."item"`. |
| S3 Tables namespace rejected | Namespaces cannot contain hyphens. |
| Lambda start is throttled | A run is already active (concurrency 1). Wait for `run_end` in the logs or set the stop flag. |
| `ROWS` alias error | `ROWS` is reserved in Snowflake; use `row_count`. |
| Athena cannot read a table | Athena reads Iceberg v2 only; keep `ICEBERG_VERSION = 2`. |
| Admin shell scripts: permission denied | `chmod` is blocked by org policy; run with `bash script.sh`. |
| zsh mangles ARNs containing `:root` | Quote ARNs: `"$ARN"`, or use bash. |
| Skill: `aws_setup.sh` Lake Formation grant fails (AccessDenied) | The `sesandbox` profile is not a Lake Formation admin. Check `aws lakeformation get-data-lake-settings --profile sesandbox --region us-west-2`; you need to be in `DataLakeAdmins`. Re-run the script after that (it is idempotent). |
| Skill: `lambda_status.sh` prints UNKNOWN | Profile `riv-demo-deployer` is missing, can't assume `riv-demo-s3t-deployer-role`, or the SSO session expired. Run `aws sso login --profile sesandbox` (SSO only), then `bash skills/riv-lakehouse-demo/scripts/deployer_access.sh`. |
| Skill: `deployer_access.sh` says the trust policy is too long | The deployer role trust is over 2,048 characters. Remove SEs who no longer need access from the `RivDemoSEs` statement, or request an IAM quota increase. |
| Skill: `lambda_start.sh` says a run is already active | Another presenter (or you) is running the Lambda. `lambda_status.sh` shows the run's start time and last batch. Wait about 8 minutes, or run `lambda_stop.sh` and wait for IDLE. |
| Skill: agent is missing from CoWork | Add it to the CoWork object: `ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT <db>.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_AGENT;`. This needs ACCOUNTADMIN or MODIFY on the object. Users also need USAGE on the object, and a default role and warehouse. |
| Skill: other agents disappeared from CoWork | The CoWork object was just created. Once it exists, only agents added to it are shown. Add the other agents with `ALTER SNOWFLAKE INTELLIGENCE ... ADD AGENT`. |
