# Naming convention

The user picks a short **user prefix**: lowercase letters, digits and underscores, starting with a letter, 2 to 20 characters (for example `jdoe`).

`<USER>` below is the prefix in uppercase (`JDOE`). `<user>` is the prefix as given. AWS names replace `_` with `-`, because bucket names cannot contain underscores.

## Asked (pre-filled with the default)

| Object | Default |
|---|---|
| Snowflake-managed Iceberg database | `RIVDEMO_<USER>_SNOW_DB` |
| Glue catalog-linked database | `RIVDEMO_<USER>_GLUE_CLD` |
| S3 Tables catalog-linked database | `RIVDEMO_<USER>_S3T_CLD` |

Users may change these. Keep the `RIVDEMO_` start so the demo objects sort together and are easy to find. Names must be UPPER_SNAKE (letters, digits, underscore).

## Derived

| Object | Name | Config key |
|---|---|---|
| S3 Tables catalog integration | `RIVDEMO_<USER>_S3T_CAT_INT` | `s3t_cat_int` |
| Glue catalog integration | `RIVDEMO_<USER>_GLUE_CAT_INT` | `glue_cat_int` |
| External volume | `RIVDEMO_<USER>_EXT_VOL` | `ext_vol` |
| Warehouse | `RIVDEMO_<USER>_WH` | `warehouse` |
| AWS S3 bucket | `riv-demo-2026-<user>-snow` | `bucket` |
| AWS IAM role | `riv-demo-2026-<user>-role` | `role_arn` (full ARN) |

The three databases map to the config keys `snow_db`, `glue_db` and `s3t_db`.

## Fixed (not renamed)

- Role `RIV_DEMO_RL`, shared by every install in the account.
- Inside the Snowflake-managed database:
  - schemas `DYNAMIC_ICEBERG` and `DL_ANALYTICS`;
  - `ACTIVITY_AGG_DIT`;
  - `RIV_RETAIL_DISTRIBUTION_SV`;
  - `RIV_RETAIL_DISTRIBUTION_AGENT`.
- Shared AWS data: `riv-demo-2026-s3t`, `rivdemo_2026`, `riv-demo-2026-w2`, `riv-demo-s3t-microbatch`.

## Validation

- Bucket names are global across AWS. If `riv-demo-2026-<user>-snow` already exists and isn't the user's, add a suffix, for example `riv-demo-2026-<user>-snow-2`.
- If any Snowflake name already exists, ask the user whether it's theirs from an earlier install (the skill is then safe to re-run) or a conflict (pick another name).
