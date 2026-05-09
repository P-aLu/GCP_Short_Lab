#!/usr/bin/env bash
# Usage: ./scripts/lab.sh <apply|destroy|plan|validate> <lab-folder-name> [--org]
# Example: ./scripts/lab.sh apply lab-03-admin-takeover --org
#
# --org  Pass enable_deny_policies=true to lab-03-admin-takeover.
#        Only valid when the admin project belongs to a GCP Organization.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform.tfvars"
LABS_DIR="${REPO_ROOT}/labs"

# ── Argument validation ────────────────────────────────────────────────────────
ACTION="${1:-}"
LAB="${2:-}"
ORG_MODE=false
for arg in "$@"; do [[ "$arg" == "--org" ]] && ORG_MODE=true; done

if [[ -z "$ACTION" || -z "$LAB" ]]; then
  echo "Usage: $0 <apply|destroy|plan|validate> <lab-folder-name> [--org]"
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


# ── Build -var-file chain ──────────────────────────────────────────────────────
# Root tfvars holds common variables (region, zone, owner).
# A per-lab terraform.tfvars in the lab directory overrides or extends those —
# used when a lab targets a different GCP project or needs lab-specific inputs
# (e.g. cross-lab SA emails). Create it from the lab's terraform.tfvars.example.
VAR_FILE_ARGS=(-var-file="${TFVARS}")
LAB_TFVARS="${LAB_DIR}/terraform.tfvars"
if [[ -f "$LAB_TFVARS" ]]; then
  VAR_FILE_ARGS+=(-var-file="${LAB_TFVARS}")
  echo "==> Using per-lab tfvars: ${LAB_TFVARS}"
fi

# --org flag: enable IAM Deny Policies for lab-03 (requires GCP Organization).
if [[ "$ORG_MODE" == "true" ]]; then
  if [[ "$LAB" != "lab-03-admin-takeover" ]]; then
    echo "WARNING: --org is only applicable to lab-03-admin-takeover; ignoring."
  else
    VAR_FILE_ARGS+=(-var "enable_deny_policies=true")
    echo "==> Org mode: IAM Deny Policies enabled"
  fi
fi

# ── Run ────────────────────────────────────────────────────────────────────────
echo "==> Lab   : ${LAB}"
echo "==> Action: ${ACTION}"
echo ""

cd "$LAB_DIR"

terraform init \
  -input=false

case "$ACTION" in
  validate)
    terraform validate
    ;;
  plan)
    terraform validate
    terraform plan "${VAR_FILE_ARGS[@]}"
    ;;
  apply)
    terraform validate
    terraform plan  "${VAR_FILE_ARGS[@]}"
    terraform apply "${VAR_FILE_ARGS[@]}" -auto-approve
    ;;
  destroy)
    terraform destroy "${VAR_FILE_ARGS[@]}" -auto-approve
    ;;
  *)
    echo "ERROR: Unknown action '${ACTION}'. Must be one of: apply, destroy, plan, validate"
    exit 1
    ;;
esac
