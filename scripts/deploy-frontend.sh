#!/usr/bin/env bash
#
# Builds the React frontend and deploys it to Amplify.
#
# Amplify's own environmentVariables are not what configures this build. Those apply
# only to builds Amplify runs itself from a connected repository, and the module
# connects none — connecting one would require a source-control access token in
# Terraform state. So the build happens here or in CI, and Vite bakes the VITE_* values
# in at build time from .env.local, which scripts/frontend-env.sh writes from Terraform
# outputs. The Amplify variables are kept in step with that set so the two paths agree
# if a repository is ever connected.
#
# Usage:
#   ./scripts/deploy-frontend.sh
#   TF_DIR=../my-infra ./scripts/deploy-frontend.sh

set -euo pipefail

MODULE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-examples/complete}"

case "${TF_DIR}" in
  /*) TF_ABS="${TF_DIR}" ;;
  *)  TF_ABS="${MODULE_ROOT}/${TF_DIR}" ;;
esac

APP_DIR="${MODULE_ROOT}/frontend"

[ -d "${TF_ABS}" ] || { echo "error: TF_DIR '${TF_DIR}' is not a directory" >&2; exit 1; }
[ -d "${APP_DIR}" ] || { echo "error: no frontend at ${APP_DIR}" >&2; exit 1; }

for cmd in terraform aws npm zip curl jq; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd not found on PATH" >&2; exit 1; }
done

# Assigned to a variable, never substituted inside a heredoc: a failing $( ) in a
# heredoc does not fail the enclosing redirect and silently yields an empty string.
tf_out() {
  local value
  if ! value="$(terraform -chdir="${TF_ABS}" output -raw "$1" 2>/dev/null)" || [ -z "${value}" ]; then
    echo "error: could not read Terraform output '$1' from ${TF_DIR}." >&2
    echo "       Not initialised?  terraform -chdir=${TF_DIR} init" >&2
    echo "       Not applied?      terraform -chdir=${TF_DIR} apply" >&2
    return 1
  fi
  printf '%s' "${value}"
}

echo "Reading configuration from ${TF_DIR}..."

APP_ID="$(tf_out amplify_app_id)"
REGION="$(tf_out region)"
BRANCH="main"

# Writes .env.local, which Vite loads for `npm run build` as well as `npm run dev`.
TF_DIR="${TF_DIR}" "${MODULE_ROOT}/scripts/frontend-env.sh"

echo "  app:    ${APP_ID}"
echo "  region: ${REGION}"
echo

# --- Build --------------------------------------------------------------------

echo "Building..."
cd "${APP_DIR}"

# npm ci deliberately, not npm install: a deploy must use locked dependencies.
if [ ! -f package-lock.json ]; then
  echo "error: ${APP_DIR}/package-lock.json is missing." >&2
  echo "       Create and commit it first: make frontend-check" >&2
  exit 1
fi

npm ci --no-audit --no-fund
npm run build

test -f dist/index.html || { echo "error: build produced no dist/index.html" >&2; exit 1; }

# The archive must contain the site at its root, not nested under dist/.
ZIP="$(mktemp -d)/frontend.zip"
( cd dist && zip -qr "${ZIP}" . )
echo "  packaged $(du -h "${ZIP}" | cut -f1)"
echo

# --- Deploy -------------------------------------------------------------------
# A manual Amplify deployment is three calls: reserve a job and get a presigned URL,
# upload the archive to it, then start the deployment.

echo "Deploying to Amplify..."

DEPLOYMENT="$(aws amplify create-deployment \
  --app-id "${APP_ID}" \
  --branch-name "${BRANCH}" \
  --region "${REGION}" \
  --output json)"

JOB_ID="$(echo "${DEPLOYMENT}" | jq -r '.jobId')"
UPLOAD_URL="$(echo "${DEPLOYMENT}" | jq -r '.zipUploadUrl')"

curl -sS -X PUT -H "Content-Type: application/zip" --upload-file "${ZIP}" "${UPLOAD_URL}"

aws amplify start-deployment \
  --app-id "${APP_ID}" \
  --branch-name "${BRANCH}" \
  --job-id "${JOB_ID}" \
  --region "${REGION}" >/dev/null

echo "  job ${JOB_ID} started"

# --- Wait ---------------------------------------------------------------------

printf '  waiting'
for _ in $(seq 1 60); do
  STATUS="$(aws amplify get-job \
    --app-id "${APP_ID}" \
    --branch-name "${BRANCH}" \
    --job-id "${JOB_ID}" \
    --region "${REGION}" \
    --query 'job.summary.status' --output text)"

  case "${STATUS}" in
    SUCCEED) echo " ${STATUS}"; break ;;
    FAILED|CANCELLED) echo " ${STATUS}"; exit 1 ;;
    *) printf '.'; sleep 5 ;;
  esac
done

rm -f "${ZIP}"

echo
echo "Deployed: $(tf_out amplify_app_url)"
