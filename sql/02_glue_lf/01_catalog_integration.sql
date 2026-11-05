-- Pattern 2, step 1: AWS Glue Iceberg REST catalog integration (Lake Formation vended credentials)
-- After running, copy API_AWS_IAM_USER_ARN and API_AWS_EXTERNAL_ID from the DESC output
-- and send them to the sandbox admin (docs/00_onboarding.md).

USE ROLE RIV_DEMO_RL;

CREATE CATALOG INTEGRATION IF NOT EXISTS RIV_DEMO_2026_GLUE_CAT_INT
  CATALOG_SOURCE = ICEBERG_REST
  TABLE_FORMAT = ICEBERG
  CATALOG_NAMESPACE = 'rivdemo_2026'
  REST_CONFIG = (
    CATALOG_URI = 'https://glue.us-west-2.amazonaws.com/iceberg'
    CATALOG_API_TYPE = AWS_GLUE
    CATALOG_NAME = '484577546576'
    ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS)
  REST_AUTHENTICATION = (
    TYPE = SIGV4
    SIGV4_IAM_ROLE = 'arn:aws:iam::484577546576:role/riv-demo-2026-shared-role'
    SIGV4_SIGNING_REGION = 'us-west-2')
  ENABLED = TRUE;

DESC CATALOG INTEGRATION RIV_DEMO_2026_GLUE_CAT_INT;
