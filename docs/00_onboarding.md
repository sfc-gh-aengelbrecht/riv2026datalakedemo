# 0. Onboarding

> **Using CoCo Desktop?** The `riv-lakehouse-demo` skill does all of this with your own AWS role and bucket instead of the shared role, so no sandbox admin is needed. See the README. The diagram of that setup is in [skills/riv-lakehouse-demo/references/demo-guide.md](../skills/riv-lakehouse-demo/references/demo-guide.md).

This guide is the manual path using the shared role `riv-demo-2026-shared-role`.

## Prerequisites
- A Snowflake account with ACCOUNTADMIN (once, for `sql/00_setup_role_wh.sql`). AWS us-west-2 avoids cross-region egress.
- A short lowercase prefix for your files, e.g. `jdoe`. It is used in place of `__user_prefix__`.
- A contact who administers the AWS sandbox (has the `sesandbox` profile).

## Step 1: role and warehouse
1. In Snowsight open **Projects -> Workspaces** (or **Worksheets**) and create a SQL file.
2. Paste `sql/00_setup_role_wh.sql`, select role **ACCOUNTADMIN**, then **Run All**.
3. Switch the worksheet role to **RIV_DEMO_RL**. Use this role for every later script.

## How AWS trust works
Each Snowflake catalog integration and external volume gets its own AWS identity: an IAM user ARN plus an
ExternalId. The shared role only lets in identities listed in its trust policy, so each new object needs
one trust entry. The demo creates three objects:

| Object | Script | Where to read the identity |
|---|---|---|
| `RIV_DEMO_S3T_CAT_INT` | `sql/01_s3tables/01_catalog_integration.sql` | DESC rows `API_AWS_IAM_USER_ARN`, `API_AWS_EXTERNAL_ID` |
| `RIV_DEMO_2026_GLUE_CAT_INT` | `sql/02_glue_lf/01_catalog_integration.sql` | DESC rows `API_AWS_IAM_USER_ARN`, `API_AWS_EXTERNAL_ID` |
| `RIV_DEMO_2026_SNOW_EXT_VOL` | `sql/03_snow_managed/01_external_volume.sql` | DESC row `STORAGE_LOCATION_1`, JSON keys `STORAGE_AWS_IAM_USER_ARN`, `STORAGE_AWS_EXTERNAL_ID` |

The IAM user ARN is usually the same for all three; the ExternalIds differ.

## Step 2: request trust
Run the three `01_*` scripts and send the admin something like:

```
RIV demo trust request, Snowflake account <ORG-ACCOUNT>
S3T  : <iam_user_arn>  <external_id>
Glue : <iam_user_arn>  <external_id>
Snow : <iam_user_arn>  <external_id>   prefix: <user_prefix>
```

Do not re-create an object after the admin has added it: `CREATE OR REPLACE` generates a new ExternalId and breaks trust.

## For the sandbox admin
```bash
cd aws/shared_role
bash add_snowflake_trust.sh <iam_user_arn> <external_id>   # once per pair
```
The script is idempotent. Allow about 10 seconds for IAM propagation. The trust policy fits roughly
8 to 10 entries at the default 2,048-character limit; request an IAM quota increase for more users.
Lambda operators need the operator policy; see `aws/lambda/s3t_microbatch/README.md`.
