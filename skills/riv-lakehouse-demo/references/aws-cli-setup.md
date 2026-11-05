# Configure the AWS CLI for the SE Sandbox

The demo uses AWS account `484577546576` (SE Sandbox), region `us-west-2`, through a CLI profile named `sesandbox`.

## 1. Install the AWS CLI v2

```bash
brew install awscli        # macOS with Homebrew
aws --version              # expect aws-cli/2.x
```

Without Homebrew, use the installer at https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html.

## 2. Create the `sesandbox` profile

Use the SSO details from the SE Sandbox access page (the AWS access portal start URL and your permission set):

```bash
aws configure sso --profile sesandbox
#   SSO session name:   sesandbox
#   SSO start URL:      <AWS access portal URL for the SE Sandbox>
#   SSO region:         <region shown on the access portal>
#   Account:            484577546576
#   Role:               <your SE Sandbox permission set>
#   Default region:     us-west-2
#   Output format:      json
```

If your sandbox access uses access keys instead of SSO:

```bash
aws configure --profile sesandbox    # access key, secret, region us-west-2, output json
```

## 3. Sign in and check

```bash
aws sso login --profile sesandbox    # SSO only; repeat when the session expires
aws sts get-caller-identity --profile sesandbox
```

`Account` must be `484577546576`.

Your user also needs:
- IAM rights to create roles and attach policies;
- S3 rights to create a bucket;
- Lake Formation admin.

All SEs in the sandbox have these.

## 4. Lambda profile `riv-demo-deployer` (the skill does this)

The micro-batch Lambda is started, stopped and watched as the shared deployer role `riv-demo-s3t-deployer-role`, which can read the Lambda logs. The skill runs this once per machine:

```bash
bash skills/riv-lakehouse-demo/scripts/deployer_access.sh
```

It adds your sandbox identity to the role's trust and writes this profile to `~/.aws/config`:

```ini
[profile riv-demo-deployer]
role_arn = arn:aws:iam::484577546576:role/riv-demo-s3t-deployer-role
source_profile = sesandbox
region = us-west-2
role_session_name = riv-demo-<your login>
```

Check: `aws sts get-caller-identity --profile riv-demo-deployer` shows `assumed-role/riv-demo-s3t-deployer-role/...`.

The deployer role can also change or delete the shared Lambda. Use only the skill's Lambda scripts: `lambda_status.sh`, `lambda_start.sh`, `lambda_stop.sh`.
