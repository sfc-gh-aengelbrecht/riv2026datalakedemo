---
name: riv-lakehouse-demo
description: "Set up the RIV 2026 lakehouse demo in your own Snowflake account against the shared SE Sandbox AWS data: your own S3 bucket and IAM role (with Lake Formation grants and Lambda start/stop), catalog-linked databases over the AWS Glue Iceberg tables and the S3 Tables bucket, a Snowflake-managed Iceberg database with a dynamic Iceberg table, semantic view and Cortex Agent, and the agent added to CoWork. Also runs the demo (start/stop/watch the micro-batch Lambda, guarded against concurrent runs) and tears it down. Use when: set up RIV demo, RIV lakehouse demo, RIV datalake demo, riv2026, configure the Iceberg demo, start the micro-batch Lambda, tear down RIV demo."
---

# RIV 2026 lakehouse demo

Builds the three Iceberg patterns of the RIV 2026 demo in the user's Snowflake account, using shared data in the SE Sandbox AWS account `484577546576` (us-west-2). Shared AWS data (S3 table bucket `riv-demo-2026-s3t`, Glue database `rivdemo_2026`, Lambda `riv-demo-s3t-microbatch`) is reused and never modified.

Paths below are relative to this skill directory (`SKILL_DIR`). The repo root is `SKILL_DIR/../..` (`REPO_DIR`). SQL comes from `REPO_DIR/sql`, rendered with the user's names by `REPO_DIR/tests/render.py --config`.

Architecture and demo script: [references/demo-guide.md](references/demo-guide.md).

## Rules

- Never modify or drop the shared AWS data, the shared Lambda, or `riv-demo-2026-shared-role`.
- Never start the Lambda without `scripts/lambda_start.sh` (it refuses while a run is active).
- Run rendered SQL with `sql_execute`, one statement per call, in file order. Do not edit statements except to substitute values the user confirmed.
- Setup and teardown AWS commands use profile `sesandbox`. The Lambda scripts use profile `riv-demo-deployer`, which assumes the shared deployer role `riv-demo-s3t-deployer-role` (created in step 3b).

## Workflow

### Step 0: ACCOUNTADMIN gate (blocking)

```sql
SELECT CURRENT_ROLE(), IS_ROLE_IN_SESSION('ACCOUNTADMIN'), CURRENT_ACCOUNT(), CURRENT_USER();
```

- If the current role is not ACCOUNTADMIN, run `USE ROLE ACCOUNTADMIN;`.
- If that fails, **stop**. Tell the user that configuring the demo needs ACCOUNTADMIN, and that they should rerun the skill with a user that has it. Do not continue to any later step.

### Step 1: AWS CLI with the SE Sandbox

Ask (ask_user_question): "Is the AWS CLI configured with the SE Sandbox profile `sesandbox`?"

- **Yes:** run `aws sts get-caller-identity --profile sesandbox`. The Account must be `484577546576`; if it isn't, show the account it returned and treat the answer as No.
- **No:** ask whether they want setup instructions.
  - If yes, show [references/aws-cli-setup.md](references/aws-cli-setup.md), wait for them to finish, then re-run the check.
  - If no, stop. The demo can't be configured without sandbox access.

Also confirm `python3 --version` works (the scripts need it).

**STOP** until the identity check passes.

### Step 2: Names

Follow [references/naming.md](references/naming.md). Ask for a short lowercase user prefix (for example `jdoe`). Then ask for the three database names, pre-filled with:

- Snowflake-managed Iceberg database: `RIVDEMO_<USER>_SNOW_DB`
- Glue catalog-linked database: `RIVDEMO_<USER>_GLUE_CLD`
- S3 Tables catalog-linked database: `RIVDEMO_<USER>_S3T_CLD`

Derive the rest, as listed in naming.md: integrations, external volume, warehouse, bucket `riv-demo-2026-<user>-snow`, role `riv-demo-2026-<user>-role`.

Check for collisions. Every query must return no rows and `head-bucket` must fail:

```sql
SHOW DATABASES LIKE '<name>';            -- each of the three
SHOW INTEGRATIONS LIKE 'RIVDEMO_<USER>%';
SHOW EXTERNAL VOLUMES LIKE 'RIVDEMO_<USER>%';
```
```bash
aws s3api head-bucket --profile sesandbox --bucket riv-demo-2026-<user>-snow
```

Show the full name table and get confirmation. **STOP** until confirmed.

Write the config to `REPO_DIR/.riv-demo/<user>/config.json` (gitignored):

```json
{"user_prefix": "<user>", "warehouse": "...", "s3t_cat_int": "...", "s3t_db": "...",
 "glue_cat_int": "...", "glue_db": "...", "ext_vol": "...", "snow_db": "...",
 "role_arn": "arn:aws:iam::484577546576:role/riv-demo-2026-<user>-role",
 "bucket": "riv-demo-2026-<user>-snow"}
```

Render the SQL:

```bash
python3 REPO_DIR/tests/render.py --config REPO_DIR/.riv-demo/<user>/config.json REPO_DIR/.riv-demo/<user>/sql
```

### Step 3: AWS bucket, role and Lake Formation grants

Show what will be created:
- bucket: versioned, public access blocked;
- role: three inline policies plus the managed policies `riv-demo-s3t-snowflake-access` and `riv-demo-s3t-microbatch-operator`;
- Lake Formation: `DATA_LOCATION_ACCESS` on `riv-demo-2026-w2`, database `CREATE_TABLE/ALTER/DESCRIBE` on `rivdemo_2026`, all tables `SELECT/INSERT/DELETE/ALTER/DESCRIBE`.

Preview it with `DRYRUN=1` first:

```bash
DRYRUN=1 bash SKILL_DIR/scripts/aws_setup.sh --user <user> --bucket riv-demo-2026-<user>-snow
```

**STOP** for approval. Then run it without `DRYRUN`. The last section lists the Lake Formation grants; all three must be present. If a grant fails, show the error and the failing command and stop. SEs are expected to be Lake Formation admins, so a failure here usually means the profile isn't the SE's own sandbox user.

### Step 3b: Lambda access through the deployer role

The user's sandbox identity usually can't read the Lambda logs, and the running check needs them. Lambda status, start and stop therefore run as the shared deployer role. This script:
- adds the caller to that role's trust (one shared `RivDemoSEs` statement);
- writes the `riv-demo-deployer` profile to `~/.aws/config`;
- verifies the profile.

```bash
DRYRUN=1 bash SKILL_DIR/scripts/deployer_access.sh   # preview
bash SKILL_DIR/scripts/deployer_access.sh
bash SKILL_DIR/scripts/lambda_status.sh               # expect IDLE or RUNNING, not UNKNOWN
```

It is safe to re-run. Tell the user the deployer role can also change the shared Lambda, so Lambda actions should go only through the skill's scripts.

If the trust policy would exceed 2,048 characters, the script stops; ask the sandbox admin to raise the IAM quota.

### Step 4: Demo role and warehouse

Run `.riv-demo/<user>/sql/00_setup_role_wh.sql` as ACCOUNTADMIN. It creates `RIV_DEMO_RL` (shared by all demo installs in the account), grants it to the current user, and creates the warehouse.

### Step 5: Integrations and trust

For each object below:
1. Run its file.
2. From the `DESC` output, read the IAM user ARN and ExternalId.
3. Run `aws_trust.sh`.

| File | `DESC` properties |
|---|---|
| `01_s3tables/01_catalog_integration.sql` | `API_AWS_IAM_USER_ARN`, `API_AWS_EXTERNAL_ID` |
| `02_glue_lf/01_catalog_integration.sql` | `API_AWS_IAM_USER_ARN`, `API_AWS_EXTERNAL_ID` |
| `03_snow_managed/01_external_volume.sql` | `STORAGE_AWS_IAM_USER_ARN`, `STORAGE_AWS_EXTERNAL_ID` (inside the `STORAGE_LOCATION_1` JSON) |

```bash
bash SKILL_DIR/scripts/aws_trust.sh --user <user> <iam_user_arn> <external_id>
```

Wait about 10 seconds, then verify. Each must return success:

```sql
SELECT SYSTEM$VERIFY_CATALOG_INTEGRATION('<s3t_cat_int>');
SELECT SYSTEM$VERIFY_CATALOG_INTEGRATION('<glue_cat_int>');
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('<ext_vol>');
```

On failure, wait 20 seconds and retry once, then use `REPO_DIR/docs/troubleshooting.md`.

### Step 6: Catalog-linked databases

1. Run `01_s3tables/02_catalog_linked_db.sql` and `02_glue_lf/02_catalog_linked_db.sql`.
2. Poll `SYSTEM$CATALOG_LINK_STATUS` every 30 seconds, up to 3 minutes, until `executionState` is RUNNING with empty `failureDetails` and `SHOW ICEBERG TABLES IN DATABASE` lists the tables.
3. Run the count checks:
   - From `02_glue_lf/03_verify.sql`, the first query only: item 1032, location 13, retailer_metadata 12.
   - From `01_s3tables/03_verify.sql`: `new_activity` 2000.

Run the Glue scratch write round trip in `02_glue_lf/03_verify.sql` only if the user asks.

### Step 7: Snowflake-managed Iceberg, semantic view, agent

Run, in order:
1. `03_snow_managed/02_database_dynamic_iceberg.sql`
2. `03_snow_managed/03_verify.sql`
3. `04_analytics/01_semantic_view.sql`
4. `04_analytics/02_agent.sql`

Checks:
- The dynamic Iceberg table refresh history shows SUCCEEDED. If it shows FAILED, read `state_message` before continuing.
- Files are landing in the user's bucket: `aws s3 ls --profile sesandbox --recursive s3://riv-demo-2026-<user>-snow/<user>/ | head`.
- `SHOW SEMANTIC VIEWS IN SCHEMA <snow_db>.DL_ANALYTICS;` and `SHOW AGENTS IN SCHEMA <snow_db>.DL_ANALYTICS;` each return one row.

### Step 8: Add the agent to CoWork

```sql
USE ROLE ACCOUNTADMIN;
SHOW SNOWFLAKE INTELLIGENCES;
```

If no rows come back, tell the user the account-wide CoWork object will be created, then run `CREATE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;` and `GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE RIV_DEMO_RL;`.

**Caution:** once that object exists, CoWork shows only the agents added to it. Agents other users see in CoWork today would disappear, so say so before creating it.

Then:

```sql
ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT
  ADD AGENT <snow_db>.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_AGENT;
SHOW AGENTS IN SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
```

The agent must appear in the `SHOW AGENTS` result. Users open it at https://ai.snowflake.com as **Retail Distribution Analyst**.

### Step 9: Run the demo

Walk through [references/demo-guide.md](references/demo-guide.md).

To load new rows:

```bash
bash SKILL_DIR/scripts/lambda_status.sh
```

- **IDLE (exit 0):** run `bash SKILL_DIR/scripts/lambda_start.sh` (defaults: 50 rows every 10 s, about 8 minutes).
- **UNKNOWN (exit 1):** the `riv-demo-deployer` profile is missing or can't assume the role (for example, an expired SSO session). Run `aws sso login --profile sesandbox` if it uses SSO, then `bash SKILL_DIR/scripts/deployer_access.sh`, and re-check. Do not start the Lambda while the status is unknown.
- **RUNNING (exit 2):** someone else's run (or the user's own) is active. Show the status output, then ask (ask_user_question) whether to:
  - **Wait:** re-check every 60 seconds.
  - **Watch:** run `aws logs tail /aws/lambda/riv-demo-s3t-microbatch --follow --profile riv-demo-deployer --region us-west-2`.
  - **Stop and restart:** run `scripts/lambda_stop.sh`, poll `lambda_status.sh` until IDLE, then run `lambda_start.sh`. Warn that this ends another presenter's run if it is theirs.

  Never invoke the Lambda directly.

While it runs, rerun the batch query in `01_s3tables/03_verify.sql` and the dynamic table checks in `03_snow_managed/03_verify.sql` to show data flowing.

### Step 10: Teardown (only when asked)

**STOP** for explicit confirmation, listing every object that will be removed. Then:

1. `ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT <snow_db>.DL_ANALYTICS.RIV_RETAIL_DISTRIBUTION_AGENT;`
2. Run `.riv-demo/<user>/sql/99_teardown.sql`. It sets both catalog-linked databases to `ALLOWED_WRITE_OPERATIONS = NONE` before dropping them.
3. `bash SKILL_DIR/scripts/aws_teardown.sh --user <user> --bucket riv-demo-2026-<user>-snow --confirm`. Preview it with `DRYRUN=1` first.
4. Check the shared data is intact. Both commands must still list tables:

```bash
aws glue get-tables --profile sesandbox --region us-west-2 --database-name rivdemo_2026 --query 'TableList[].Name'
aws s3tables list-tables --profile sesandbox --region us-west-2 --table-bucket-arn arn:aws:s3tables:us-west-2:484577546576:bucket/riv-demo-2026-s3t --query 'tables[].name'
```

Keep `RIV_DEMO_RL` if other installs in the account use it.

## Stopping points

- Step 0: not ACCOUNTADMIN, and switching fails. This blocks everything; end the skill.
- Step 1: the sandbox identity check doesn't pass.
- Step 2: confirm the names.
- Step 3: approve the AWS changes after the dry run.
- Step 8: before creating the CoWork object, if it doesn't exist.
- Step 9: the Lambda is already RUNNING.
- Step 10: before any teardown.

## Output

When setup finishes, report:
- a table of every object created (Snowflake and AWS) with its name;
- the verification results (row counts, link status, dynamic table refresh state);
- the CoWork link https://ai.snowflake.com and the agent name **Retail Distribution Analyst**;
- the Lambda start and stop commands.
