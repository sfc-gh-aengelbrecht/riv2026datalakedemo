# riv-demo-2026-shared-role

Shared IAM role for the RIV 2026 demo in AWS sandbox `484577546576` (us-west-2).
Other users add their own Snowflake account to its trust policy and point their integrations at it.

**Role ARN:** `arn:aws:iam::484577546576:role/riv-demo-2026-shared-role`

## What it can do
| Area | Access |
|---|---|
| S3 Tables bucket `riv-demo-2026-s3t` | Read/write namespaces and tables (managed `riv-demo-s3t-snowflake-access`) |
| Glue database `rivdemo_2026` | Read/create/update/delete tables, `lakeformation:GetDataAccess` |
| Lake Formation | `DATA_LOCATION_ACCESS` on `riv-demo-2026-w2`; DB `CREATE_TABLE/ALTER/DESCRIBE`; all tables `SELECT/INSERT/DELETE/ALTER/DESCRIBE` |
| S3 `riv-demo-2026-w2` | Read/write (Glue Iceberg data) |
| S3 `riv-demo-2026-snow-w2` | Read/write incl. object versions (Snowflake-managed Iceberg external volume) |
| Lambda `riv-demo-s3t-microbatch` | Start, stop, monitor only (managed `riv-demo-s3t-microbatch-operator`) |

It **cannot** change or delete the Lambda, publish layers, pass roles, or change IAM.

## Files
- `trust.json` - initial trust template (`__ADMIN_PRINCIPAL_ARN__` is filled with the admin running the script; see `aws/admin_identity.sh`)
- `riv-demo-2026-*.json` - inline policies, copied from the original demo roles
- `create_shared_role.sh` - creates the role, its policies and Lake Formation grants (safe to re-run; never resets trust)
- `add_snowflake_trust.sh` - adds one Snowflake integration / external volume to the trust policy

## Onboard your Snowflake account
1. Create the Snowflake object with the shared role ARN.

   External volume (Snowflake-managed Iceberg). Use your own prefix:
   ```sql
   CREATE EXTERNAL VOLUME MY_RIV_EXT_VOL STORAGE_LOCATIONS = ((
     NAME = 'riv-snow-w2' STORAGE_PROVIDER = 'S3'
     STORAGE_BASE_URL = 's3://riv-demo-2026-snow-w2/<your-prefix>/'
     STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::484577546576:role/riv-demo-2026-shared-role'))
     ALLOW_WRITES = TRUE;
   ```
   S3 Tables catalog integration:
   ```sql
   CREATE CATALOG INTEGRATION MY_RIV_S3T_CAT_INT
     CATALOG_SOURCE = ICEBERG_REST TABLE_FORMAT = ICEBERG
     REST_CONFIG = (
       CATALOG_URI = 'https://s3tables.us-west-2.amazonaws.com/iceberg'
       CATALOG_API_TYPE = AWS_S3TABLES
       CATALOG_NAME = 'arn:aws:s3tables:us-west-2:484577546576:bucket/riv-demo-2026-s3t'
       ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS)
     REST_AUTHENTICATION = (TYPE = SIGV4
       SIGV4_IAM_ROLE = 'arn:aws:iam::484577546576:role/riv-demo-2026-shared-role'
       SIGV4_SIGNING_REGION = 'us-west-2')
     ENABLED = TRUE;
   ```
   Glue catalog integration:
   ```sql
   CREATE CATALOG INTEGRATION MY_RIV_GLUE_CAT_INT
     CATALOG_SOURCE = ICEBERG_REST TABLE_FORMAT = ICEBERG
     CATALOG_NAMESPACE = 'rivdemo_2026'
     REST_CONFIG = (
       CATALOG_URI = 'https://glue.us-west-2.amazonaws.com/iceberg'
       CATALOG_API_TYPE = AWS_GLUE
       CATALOG_NAME = '484577546576'
       ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS)
     REST_AUTHENTICATION = (TYPE = SIGV4
       SIGV4_IAM_ROLE = 'arn:aws:iam::484577546576:role/riv-demo-2026-shared-role'
       SIGV4_SIGNING_REGION = 'us-west-2')
     ENABLED = TRUE;
   ```
2. Get the Snowflake IAM user and ExternalId:
   - external volume: `DESC EXTERNAL VOLUME MY_RIV_EXT_VOL;` gives `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`;
   - catalog integration: `DESC CATALOG INTEGRATION ...;` gives the `...IAM_USER_ARN` and `...EXTERNAL_ID` rows (Glue returns `API_AWS_IAM_USER_ARN` / `API_AWS_EXTERNAL_ID`).
3. Ask a sandbox admin (profile `sesandbox`) to add the trust statement:
   ```bash
   bash iam/shared_role/add_snowflake_trust.sh <iam_user_arn> <external_id>
   ```
   Each Snowflake object has its own ExternalId, so repeat this step for every object.
4. Wait about 10 seconds, then verify:
   ```sql
   SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('MY_RIV_EXT_VOL');
   SELECT SYSTEM$VERIFY_CATALOG_INTEGRATION('MY_RIV_S3T_CAT_INT');
   ```

The trust policy holds 2,048 characters by default, enough for about 8 to 10 Snowflake statements. Request an IAM quota increase if more accounts need it.

## Run the micro-batch demo
Profile for people (assumes the role):
```ini
# ~/.aws/config
[profile riv-demo-shared]
role_arn = arn:aws:iam::484577546576:role/riv-demo-2026-shared-role
source_profile = sesandbox
region = us-west-2
```

```bash
# start: async, 50 rows every 10s; replays from rowid 1 and resets the stop flag itself
aws lambda invoke --profile riv-demo-shared --region us-west-2 \
  --function-name riv-demo-s3t-microbatch --invocation-type Event \
  --cli-binary-format raw-in-base64-out \
  --payload '{"batch_size":50,"wait_seconds":10}' /dev/null

# monitor
aws logs tail --profile riv-demo-shared --region us-west-2 \
  /aws/lambda/riv-demo-s3t-microbatch --follow

# stop: the loop exits after its current batch and logs a run_end event
aws ssm put-parameter --profile riv-demo-shared --region us-west-2 \
  --name /riv-demo/s3t-microbatch/stop --value true --overwrite
```
Only one run can be active at a time. Wait for the `run_end` log event before starting again.
