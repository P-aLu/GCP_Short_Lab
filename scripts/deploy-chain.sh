#!/usr/bin/env bash
# Deploy or destroy the full lab chain in the correct order, passing cross-lab
# outputs automatically as -var flags so no manual tfvars editing is needed.
#
# Usage:
#   ./scripts/deploy-chain.sh apply           — provision all labs
#   ./scripts/deploy-chain.sh apply --org     — provision with IAM Deny Policies (requires GCP Org)
#   ./scripts/deploy-chain.sh destroy         — tear down all labs in reverse order
#   ./scripts/deploy-chain.sh destroy --org   — destroy when deployed with --org

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform.tfvars"
LABS_DIR="${REPO_ROOT}/labs"

# ── Argument validation ────────────────────────────────────────────────────────
ACTION="${1:-}"
ORG_MODE=false
for arg in "$@"; do [[ "$arg" == "--org" ]] && ORG_MODE=true; done

if [[ "$ACTION" != "apply" && "$ACTION" != "destroy" ]]; then
  echo "Usage: $0 <apply|destroy> [--org]"
  exit 1
fi

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: terraform.tfvars not found."
  echo "       Copy terraform.tfvars.example and fill in project_id, webapp_project_id,"
  echo "       admin_project_id, region, zone, and owner."
  exit 1
fi

# ── Read shared config from root tfvars ────────────────────────────────────────
_read_tfvar() {
  grep -E "^${1}\s*=" "$TFVARS" | head -1 | sed 's/.*=\s*"\(.*\)"/\1/'
}

PROJECT_A=$(_read_tfvar project_id)
WEBAPP_PROJECT=$(_read_tfvar webapp_project_id)
ADMIN_PROJECT=$(_read_tfvar admin_project_id)
PRESET_UID=$(_read_tfvar deployment_uid)   # optional — set by setup.sh

[[ -n "$PROJECT_A" ]]      || { echo "ERROR: project_id not set in terraform.tfvars";        exit 1; }
[[ -n "$WEBAPP_PROJECT" ]] || { echo "ERROR: webapp_project_id not set in terraform.tfvars"; exit 1; }
[[ -n "$ADMIN_PROJECT" ]]  || { echo "ERROR: admin_project_id not set in terraform.tfvars";  exit 1; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Print a visible step banner.
_banner() { echo ""; echo "── $* ─────────────────────────────────────────────"; }

# Init a lab's local backend (idempotent, output suppressed).
_init() {
  local lab="$1"
  pushd "${LABS_DIR}/${lab}" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  popd > /dev/null
}

# Read a Terraform output from a lab (requires state to exist).
_output() {
  local lab="$1" key="$2"
  _init "$lab"
  pushd "${LABS_DIR}/${lab}" > /dev/null
  local val
  val=$(terraform output -raw "$key" 2>/dev/null) || val=""
  popd > /dev/null
  echo "$val"
}

# ── APPLY ─────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "apply" ]]; then

  echo "==> deploy-chain: apply"
  echo "    Deployments project  (A) : ${PROJECT_A}"
  echo "    Webapp project       (B) : ${WEBAPP_PROJECT}"
  echo "    Admin project        (C) : ${ADMIN_PROJECT}"
  echo ""

  # ── Step 1: deployments project ──────────────────────────────────────────────
  _banner "1/5  lab-01-gsc-privesc — deployments project"
  pushd "${LABS_DIR}/lab-01-gsc-privesc" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform validate
  # Pass pre-set UID from setup.sh when available so Terraform uses the same
  # value that was used to name the GCP projects.
  if [[ -n "${PRESET_UID:-}" ]]; then
    terraform apply -var-file="${TFVARS}" -var "deployment_uid=${PRESET_UID}" -auto-approve
  else
    terraform apply -var-file="${TFVARS}" -auto-approve
  fi
  UID=$(terraform output -raw deployment_uid)
  CF_API_USER=$(terraform output -raw cf_api_user)
  CF_API_PASSWORD=$(terraform output -raw cf_api_password)
  SA_KEY_CMD=$(terraform output -raw sa_key_create_command)
  popd > /dev/null
  echo "    deployment_uid = ${UID}"

  # ── Step 2: Cloud Function (webapp project) ───────────────────────────────────
  _banner "2/5  lab-01-gsc-privesc-b — Cloud Function"
  pushd "${LABS_DIR}/lab-01-gsc-privesc-b" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform validate
  terraform apply \
    -var-file="${TFVARS}" \
    -var "project_id=${WEBAPP_PROJECT}" \
    -var "deployment_uid=${UID}" \
    -var "cf_api_user=${CF_API_USER}" \
    -var "cf_api_password=${CF_API_PASSWORD}" \
    -auto-approve
  FUNCTION_URL=$(terraform output -raw function_url)
  CF_RUNTIME_SA=$(terraform output -raw cf_runtime_sa_email)
  popd > /dev/null
  echo "    function_url     = ${FUNCTION_URL}"
  echo "    cf_runtime_sa    = ${CF_RUNTIME_SA}"

  # ── Step 3: seed Cloud Function URL back into the deployments project ──────────
  _banner "3/5  lab-01-gsc-privesc — seed function URL into Web APIs table"
  pushd "${LABS_DIR}/lab-01-gsc-privesc" > /dev/null
  terraform apply \
    -var-file="${TFVARS}" \
    -var "cf_function_url=${FUNCTION_URL}" \
    -auto-approve
  popd > /dev/null

  # ── Step 4: webapp project resources (KMS, Secret Manager, BigQuery) ──────────
  _banner "4/5  lab-02-kms-privesc — KMS / Secret Manager / BigQuery"
  pushd "${LABS_DIR}/lab-02-kms-privesc" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform validate
  terraform apply \
    -var-file="${TFVARS}" \
    -var "project_id=${WEBAPP_PROJECT}" \
    -var "deployment_uid=${UID}" \
    -var "cf_runtime_sa_email=${CF_RUNTIME_SA}" \
    -auto-approve
  SCANNER_SA=$(terraform output -raw projects_scanner_sa_email)
  popd > /dev/null
  echo "    projects_scanner_sa  = ${SCANNER_SA}"

  # ── Step 5: admin project (IAM Deny Policies, credentials bucket, flag secret) ─
  _banner "5/5  lab-03-admin-takeover — admin project"
  pushd "${LABS_DIR}/lab-03-admin-takeover" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform validate
  LAB03_VARS=(
    -var-file="${TFVARS}"
    -var "project_id=${ADMIN_PROJECT}"
    -var "deployment_uid=${UID}"
    -var "projects_scanner_sa_email=${SCANNER_SA}"
  )
  [[ "$ORG_MODE" == "true" ]] && LAB03_VARS+=(-var "enable_deny_policies=true")
  terraform apply "${LAB03_VARS[@]}" -auto-approve
  popd > /dev/null

  # Post-apply: disable Secret Manager API (Stage 4 puzzle).
  # Students must re-enable it via GCP Console after granting their personal
  # account project owner. The IAM Deny Policy handles the API-enable constraint
  # on admin-owner — disabling serviceusage itself is not needed and breaks destroy.
  echo ""
  echo "    Disabling secretmanager.googleapis.com in admin project (Stage 4 puzzle)..."
  gcloud services disable secretmanager.googleapis.com \
    --project="${ADMIN_PROJECT}" \
    --quiet || true

  # ── Auto-destroy timer ────────────────────────────────────────────────────────
  # Spawn a detached background process that destroys the chain after 2 hours.
  # Uses nohup + disown so the timer survives terminal closure.
  TIMER_PID_FILE="${REPO_ROOT}/.autodestroy.pid"
  TIMER_LOG_FILE="${REPO_ROOT}/.autodestroy.log"

  # Cancel any previous timer that may still be running.
  if [[ -f "$TIMER_PID_FILE" ]]; then
    OLD_PID=$(cat "$TIMER_PID_FILE")
    kill "$OLD_PID" 2>/dev/null || true
    rm -f "$TIMER_PID_FILE"
  fi

  nohup bash -c "sleep 7200 && cd '${REPO_ROOT}' && ./scripts/deploy-chain.sh destroy" \
    > "$TIMER_LOG_FILE" 2>&1 &
  TIMER_PID=$!
  disown "$TIMER_PID"
  echo "$TIMER_PID" > "$TIMER_PID_FILE"

  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo "  Chain deployed successfully."
  echo ""
  echo "  Deployment UID : ${UID}"
  echo "  Projects       : ${PROJECT_A} | ${WEBAPP_PROJECT} | ${ADMIN_PROJECT}"
  echo "  Function URL   : ${FUNCTION_URL}"
  echo ""
  echo "  Generate the learner's starting SA key:"
  echo "  ${SA_KEY_CMD}"
  echo ""
  echo "  ⚠  Auto-destroy scheduled in 2 hours (PID ${TIMER_PID})"
  echo "     To cancel : kill ${TIMER_PID} && rm ${TIMER_PID_FILE}"
  echo "     To destroy now : ./scripts/deploy-chain.sh destroy"
  echo "     Timer log : ${TIMER_LOG_FILE}"
  echo "════════════════════════════════════════════════════════════════════"

# ── DESTROY ───────────────────────────────────────────────────────────────────
elif [[ "$ACTION" == "destroy" ]]; then

  echo "==> deploy-chain: destroy (reverse order)"

  # Cancel the auto-destroy timer if it is still running.
  TIMER_PID_FILE="${REPO_ROOT}/.autodestroy.pid"
  if [[ -f "$TIMER_PID_FILE" ]]; then
    OLD_PID=$(cat "$TIMER_PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
      echo "    Cancelling auto-destroy timer (PID ${OLD_PID})..."
      kill "$OLD_PID" 2>/dev/null || true
    fi
    rm -f "$TIMER_PID_FILE"
  fi
  echo ""

  # Collect outputs from existing state BEFORE any destroy call, so values
  # are available for later steps even after earlier states are cleared.
  echo "    Reading state outputs..."
  UID=$(_output lab-01-gsc-privesc deployment_uid)
  CF_API_PASSWORD=$(_output lab-01-gsc-privesc cf_api_password)
  CF_RUNTIME_SA=$(_output lab-01-gsc-privesc-b cf_runtime_sa_email)
  SCANNER_SA=$(_output lab-02-kms-privesc projects_scanner_sa_email)

  if [[ -z "$UID" ]]; then
    echo "ERROR: Cannot read deployment_uid from lab-01-gsc-privesc state."
    echo "       Has the chain been deployed? Check: cd labs/lab-01-gsc-privesc && terraform output"
    exit 1
  fi

  echo "    deployment_uid = ${UID}"
  echo ""

  # ── Step 1: destroy admin project resources ────────────────────────────────
  _banner "1/4  lab-03-admin-takeover"
  # Re-enable secretmanager before destroy — Terraform needs it to delete the
  # flag secret. The API was disabled post-apply as part of the Stage 4 puzzle.
  echo "    Re-enabling secretmanager.googleapis.com for teardown..."
  gcloud services enable secretmanager.googleapis.com \
    --project="${ADMIN_PROJECT}" \
    --quiet || true
  pushd "${LABS_DIR}/lab-03-admin-takeover" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  LAB03_VARS=(
    -var-file="${TFVARS}"
    -var "project_id=${ADMIN_PROJECT}"
    -var "deployment_uid=${UID}"
    -var "projects_scanner_sa_email=${SCANNER_SA:-placeholder@placeholder.iam.gserviceaccount.com}"
  )
  [[ "$ORG_MODE" == "true" ]] && LAB03_VARS+=(-var "enable_deny_policies=true")
  terraform destroy "${LAB03_VARS[@]}" -auto-approve
  popd > /dev/null

  # ── Step 2: destroy webapp project resources ───────────────────────────────
  _banner "2/4  lab-02-kms-privesc"
  pushd "${LABS_DIR}/lab-02-kms-privesc" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform destroy \
    -var-file="${TFVARS}" \
    -var "project_id=${WEBAPP_PROJECT}" \
    -var "deployment_uid=${UID}" \
    -var "cf_runtime_sa_email=${CF_RUNTIME_SA:-placeholder@x.iam.gserviceaccount.com}" \
    -auto-approve
  popd > /dev/null

  # ── Step 3: destroy Cloud Function ────────────────────────────────────────
  _banner "3/4  lab-01-gsc-privesc-b"
  pushd "${LABS_DIR}/lab-01-gsc-privesc-b" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform destroy \
    -var-file="${TFVARS}" \
    -var "project_id=${WEBAPP_PROJECT}" \
    -var "deployment_uid=${UID}" \
    -var "cf_api_user=placeholder" \
    -var "cf_api_password=${CF_API_PASSWORD:-placeholder}" \
    -auto-approve
  popd > /dev/null

  # ── Step 4: destroy deployments project ────────────────────────────────────
  _banner "4/4  lab-01-gsc-privesc"
  pushd "${LABS_DIR}/lab-01-gsc-privesc" > /dev/null
  terraform init \
    -input=false -upgrade=false > /dev/null
  terraform destroy \
    -var-file="${TFVARS}" \
    -auto-approve
  popd > /dev/null

  echo ""
  echo "════════════════════════════════════════════════════════════════════"
  echo "  Chain destroyed."
  echo "  Note: KMS key rings remain in GCP (cannot be deleted) at no cost."
  echo "════════════════════════════════════════════════════════════════════"

fi
