#!/usr/bin/env bash
#
# Creates or resets a Cognito user, interactively.
#
# The username *is* the email address: the pool sets username_attributes = ["email"], so
# Cognito rejects a non-email username. It does not have to be deliverable —
# --message-action SUPPRESS sends no mail and email_verified is set here — so
# admin@example.com is fine.
#
# The pool has self sign-up disabled and the frontend hides the sign-up form, so a user
# must be created administratively. This does it without the password reaching Terraform
# state, shell history or the terminal, which is why the module has no test-user
# variables: aws_cognito_user stores the password in state in plaintext regardless of
# how the variable is marked.
#
# Safe to re-run: an existing user has its password reset rather than failing.
#
# Usage:
#   ./scripts/create-user.sh
#   EMAIL=admin@example.com TF_DIR=../my-infra ./scripts/create-user.sh

set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-examples/complete}"

case "${TF_DIR}" in
  /*) TF_ABS="${TF_DIR}" ;;
  *)  TF_ABS="${MODULE_ROOT}/${TF_DIR}" ;;
esac

[ -d "${TF_ABS}" ] || { echo "error: TF_DIR '${TF_DIR}' is not a directory" >&2; exit 1; }

for cmd in terraform aws; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd not found on PATH" >&2; exit 1; }
done

# Assigned rather than substituted inside a heredoc, so failure aborts under set -e.
read_output() {
  local name="$1" value
  if ! value="$(terraform -chdir="${TF_ABS}" output -raw "$name" 2>/dev/null)" || [ -z "${value}" ]; then
    echo "error: could not read Terraform output '${name}' from ${TF_DIR}." >&2
    echo "       Not initialised?  terraform -chdir=${TF_DIR} init" >&2
    echo "       Not applied?      terraform -chdir=${TF_DIR} apply" >&2
    return 1
  fi
  printf '%s' "${value}"
}

POOL_ID="$(read_output user_pool_id)"
REGION="$(read_output region)"
APP_URL="$(read_output amplify_app_url)"

echo "User pool: ${POOL_ID}"
echo

EMAIL="${EMAIL:-}"
if [ -z "${EMAIL}" ]; then
  read -rp "email: " EMAIL
fi
if [ -z "${EMAIL}" ]; then
  echo "error: email is required" >&2
  exit 1
fi

# Checked here so a weak password fails immediately rather than after two API calls.
# Mirrors the pool's policy: 8+ characters with lower, upper, digit and symbol.
validate_password() {
  local pw="$1"
  [ "${#pw}" -ge 8 ]          || { echo "  too short, minimum 8 characters"; return 1; }
  [[ "$pw" =~ [a-z] ]]        || { echo "  needs a lowercase letter"; return 1; }
  [[ "$pw" =~ [A-Z] ]]        || { echo "  needs an uppercase letter"; return 1; }
  [[ "$pw" =~ [0-9] ]]        || { echo "  needs a digit"; return 1; }
  [[ "$pw" =~ [^a-zA-Z0-9] ]] || { echo "  needs a symbol"; return 1; }
  return 0
}

PASSWORD=""
for _ in 1 2 3; do
  read -rsp "password: " PASSWORD && echo
  read -rsp "confirm:  " CONFIRM && echo
  if [ "${PASSWORD}" != "${CONFIRM}" ]; then
    echo "  passwords do not match"
    continue
  fi
  if validate_password "${PASSWORD}"; then
    break
  fi
  PASSWORD=""
done

if [ -z "${PASSWORD}" ]; then
  echo "error: no acceptable password provided" >&2
  exit 1
fi

echo

if aws cognito-idp admin-get-user \
     --user-pool-id "${POOL_ID}" --username "${EMAIL}" --region "${REGION}" >/dev/null 2>&1; then
  echo "exists    ${EMAIL}, resetting password"
else
  aws cognito-idp admin-create-user \
    --user-pool-id "${POOL_ID}" \
    --username "${EMAIL}" \
    --region "${REGION}" \
    --message-action SUPPRESS \
    --user-attributes "Name=email,Value=${EMAIL}" "Name=email_verified,Value=true" >/dev/null
  echo "created   ${EMAIL}"
fi

# --permanent matters: without it the account lands in FORCE_CHANGE_PASSWORD and the
# Amplify Authenticator demands a new password at first sign-in.
aws cognito-idp admin-set-user-password \
  --user-pool-id "${POOL_ID}" \
  --username "${EMAIL}" \
  --password "${PASSWORD}" \
  --region "${REGION}" \
  --permanent

echo "set       password, permanent"
echo
echo "Sign in at ${APP_URL}"
