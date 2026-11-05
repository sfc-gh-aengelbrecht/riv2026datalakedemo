# Sourced by the admin scripts. Derives identity values at run time so none are
# hardcoded in the repo. Requires PROFILE_FOR_IDENTITY to be set by the caller.
#   ADMIN_PRINCIPAL_ARN  principal written into trust policies (override with env)
#   OWNER                value of the "owner" tag on created resources
#   trust_doc <file>     prints a trust JSON with __ADMIN_PRINCIPAL_ARN__ filled in

_caller_arn=$(aws sts get-caller-identity --profile "$PROFILE_FOR_IDENTITY" --query Arn --output text)
# SSO / assumed-role session -> trust the role itself (sessions can't be principals)
if [[ "$_caller_arn" =~ ^arn:aws:sts::([0-9]{12}):assumed-role/([^/]+)/(.+)$ ]]; then
  _default_principal="arn:aws:iam::${BASH_REMATCH[1]}:role/${BASH_REMATCH[2]}"
  _default_owner="${BASH_REMATCH[3]}"
else
  _default_principal="$_caller_arn"
  _default_owner="${_caller_arn##*/}"
fi
ADMIN_PRINCIPAL_ARN="${ADMIN_PRINCIPAL_ARN:-$_default_principal}"
OWNER="${OWNER:-$(printf '%s' "$_default_owner" | tr -cd 'A-Za-z0-9_.@-')}"

[[ "$ADMIN_PRINCIPAL_ARN" =~ ^arn:aws:iam::[0-9]{12}:(user|role)/[A-Za-z0-9+=,.@_/-]+$ ]] || {
  echo "Invalid ADMIN_PRINCIPAL_ARN: $ADMIN_PRINCIPAL_ARN" >&2; exit 1; }

trust_doc() { sed "s#__ADMIN_PRINCIPAL_ARN__#${ADMIN_PRINCIPAL_ARN}#g" "$1"; }
