-- Pattern 3, step 1: external volume for Snowflake-managed Iceberg
-- Replace __user_prefix__ with your own lowercase prefix (e.g. jdoe) so your files stay separate.
-- After running, copy STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from the DESC output
-- (inside the STORAGE_LOCATION_1 JSON) and send them to the sandbox admin.

USE ROLE RIV_DEMO_RL;

CREATE EXTERNAL VOLUME IF NOT EXISTS RIV_DEMO_2026_SNOW_EXT_VOL
  STORAGE_LOCATIONS = ((
    NAME = 'riv-snow-w2'
    STORAGE_PROVIDER = 'S3'
    STORAGE_BASE_URL = 's3://riv-demo-2026-snow-w2/__user_prefix__/'
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::484577546576:role/riv-demo-2026-shared-role'))
  ALLOW_WRITES = TRUE;

DESC EXTERNAL VOLUME RIV_DEMO_2026_SNOW_EXT_VOL;
