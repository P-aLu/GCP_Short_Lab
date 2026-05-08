#!/usr/bin/env bash
# Usage: ./scripts/lab.sh <apply|destroy|plan|validate> <lab-folder-name>
# Example: ./scripts/lab.sh apply lab-01-gsc-privesc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform.tfvars"
LABS_DIR="${REPO_ROOT}/labs"

# ── Argument validation ────────────────────────────────────────────────────────
ACTION="${1:-}"
LAB="${2:-}"

if [[ -z "$ACTION" || -z "$LAB" ]]; then
  echo "Usage: $0 <apply|destroy|plan|validate> <lab-folder-name>"
  exit 1
fi

LAB_DIR="${LABS_DIR}/${LAB}"

if [[ ! -d "$LAB_DIR" ]]; then
  echo "ERROR: Lab directory not found: ${LAB_DIR}"
  exit 1
fi

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: terraform.tfvars not found at ${TFVARS}"
  echo "       Copy terraform.tfvars.example and fill in your values."
  exit 1
fi

# ── Read state bucket from tfvars ──────────────────────────────────────────────
STATE_BUCKET=$(grep -E '^state_bucket' "$TFVARS" | sed 's/.*=\s*"\(.*\)"/\1/')

if [[ -z "$STATE_BUCKET" ]]; then
  echo "ERROR: state_bucket not set in terraform.tfvars"
  exit 1
fi

# ── Run ────────────────────────────────────────────────────────────────────────
echo "==> Lab   : ${LAB}"
echo "==> Action: ${ACTION}"
echo "==> State : gs://${STATE_BUCKET}/${LAB}/terraform.tfstate"
echo ""

cd "$LAB_DIR"

terraform init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="prefix=${LAB}" \
  -input=false

case "$ACTION" in
  validate)
    terraform validate
    ;;
  plan)
    terraform validate
    terraform plan -var-file="${TFVARS}"
    ;;
  apply)
    terraform validate
    terraform plan  -var-file="${TFVARS}"
    terraform apply -var-file="${TFVARS}" -auto-approve
    ;;
  destroy)
    terraform destroy -var-file="${TFVARS}" -auto-approve
    ;;
  *)
    echo "ERROR: Unknown action '${ACTION}'. Must be one of: apply, destroy, plan, validate"
    exit 1
    ;;
esac
