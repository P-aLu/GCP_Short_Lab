#!/usr/bin/env bash
# Delete all three GCP projects created by setup.sh.
# Run this AFTER `deploy-chain.sh destroy` has cleared Terraform resources.
#
# Usage:
#   ./scripts/destroy-projects.sh [--force]
#
# Options:
#   --force   Skip the confirmation prompt (useful in CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform.tfvars"

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    -h|--help)
      sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "ERROR: Unknown argument: $arg"; exit 1 ;;
  esac
done

if [[ ! -f "$TFVARS" ]]; then
  echo "ERROR: terraform.tfvars not found — nothing to delete."
  echo "       Run setup.sh first, or the projects may already be gone."
  exit 1
fi

# ── Read project IDs from tfvars ───────────────────────────────────────────────
_read_tfvar() {
  grep -E "^${1}\s*=" "$TFVARS" | head -1 | sed 's/.*=\s*"\(.*\)"/\1/'
}

PROJECT_A=$(_read_tfvar project_id)
PROJECT_B=$(_read_tfvar webapp_project_id)
PROJECT_C=$(_read_tfvar admin_project_id)

[[ -n "$PROJECT_A" ]] || { echo "ERROR: project_id not set in terraform.tfvars";        exit 1; }
[[ -n "$PROJECT_B" ]] || { echo "ERROR: webapp_project_id not set in terraform.tfvars"; exit 1; }
[[ -n "$PROJECT_C" ]] || { echo "ERROR: admin_project_id not set in terraform.tfvars";  exit 1; }

echo "════════════════════════════════════════════════════════════════════"
echo "  Destroy GCP Projects"
echo ""
echo "  Project A (deployments) : ${PROJECT_A}"
echo "  Project B (webapp)      : ${PROJECT_B}"
echo "  Project C (admin)       : ${PROJECT_C}"
echo ""
echo "  Projects enter GCP's 30-day soft-delete window and can be"
echo "  recovered from the GCP Console if needed within that period."
echo ""
echo "  Run deploy-chain.sh destroy first if you haven't already."
echo "════════════════════════════════════════════════════════════════════"
echo ""

if [[ "$FORCE" != "true" ]]; then
  read -r -p "Type 'yes' to confirm project deletion: " _confirm
  [[ "$_confirm" == "yes" ]] || { echo "Aborted."; exit 0; }
  echo ""
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
_banner() { echo "── $* ─────────────────────────────────────────────"; }

_delete_project() {
  local id="$1"
  if gcloud projects describe "$id" &>/dev/null; then
    echo "  Deleting ${id}..."
    gcloud projects delete "$id" --quiet
  else
    echo "  [skip] ${id} not found (already deleted or never created)."
  fi
}

# ── Cancel auto-destroy timer if still running ────────────────────────────────
TIMER_PID_FILE="${REPO_ROOT}/.autodestroy.pid"
if [[ -f "$TIMER_PID_FILE" ]]; then
  OLD_PID=$(cat "$TIMER_PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "  Cancelling auto-destroy timer (PID ${OLD_PID})..."
    kill "$OLD_PID" 2>/dev/null || true
  fi
  rm -f "$TIMER_PID_FILE"
fi

# ── Delete projects (admin → webapp → deployments) ────────────────────────────
_banner "Deleting GCP projects"
_delete_project "$PROJECT_C"
_delete_project "$PROJECT_B"
_delete_project "$PROJECT_A"
echo ""

# ── Clean up local artifacts ──────────────────────────────────────────────────
_banner "Cleaning up local state"

echo "  Removing terraform.tfvars..."
rm -f "$TFVARS"

for lab_dir in "${REPO_ROOT}"/labs/*/; do
  if [[ -d "${lab_dir}.terraform" ]]; then
    echo "  Removing ${lab_dir}.terraform/"
    rm -rf "${lab_dir}.terraform"
  fi
done

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  Done. Projects are in GCP's 30-day soft-delete window."
echo ""
echo "  To start a fresh lab environment:"
echo "    ./scripts/setup.sh --billing-account=XXXXXX-XXXXXX-XXXXXX"
echo "════════════════════════════════════════════════════════════════════"
