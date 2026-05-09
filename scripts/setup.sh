#!/usr/bin/env bash
# One-shot project bootstrap for the GCP lab chain.
#
# Generates a deployment UID, creates three GCP projects, links billing,
# enables all required APIs, creates the Terraform state bucket, and writes
# a ready-to-use terraform.tfvars so deploy-chain.sh can run immediately.
#
# Usage:
#   ./scripts/setup.sh --billing-account=XXXXXX-XXXXXX-XXXXXX [options]
#
# Options:
#   --billing-account=ID   (required) GCP billing account ID
#                          Find yours: gcloud billing accounts list
#   --owner=NAME           Value for the 'owner' resource label
#                          (default: prefix of the active gcloud account)
#   --region=REGION        GCP region  (default: europe-west1)
#   --zone=ZONE            GCP zone    (default: europe-west1-b)
#   --org-id=ID            Create projects under this GCP organization
#   --folder-id=ID         Create projects under this GCP folder
#                          (If neither is given, projects are created at the
#                           account level — fine for personal GCP accounts)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TFVARS="${REPO_ROOT}/terraform.tfvars"

# ── Parse arguments ────────────────────────────────────────────────────────────
BILLING_ACCOUNT=""
OWNER=""
REGION="europe-west1"
ZONE="europe-west1-b"
ORG_ID=""
FOLDER_ID=""

for arg in "$@"; do
  case "$arg" in
    --billing-account=*) BILLING_ACCOUNT="${arg#*=}" ;;
    --owner=*)           OWNER="${arg#*=}" ;;
    --region=*)          REGION="${arg#*=}" ;;
    --zone=*)            ZONE="${arg#*=}" ;;
    --org-id=*)          ORG_ID="${arg#*=}" ;;
    --folder-id=*)       FOLDER_ID="${arg#*=}" ;;
    -h|--help)
      sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "ERROR: Unknown argument: $arg"; exit 1 ;;
  esac
done

if [[ -z "$BILLING_ACCOUNT" ]]; then
  echo "ERROR: --billing-account is required."
  echo "       Find yours with: gcloud billing accounts list"
  echo "Usage: $0 --billing-account=XXXXXX-XXXXXX-XXXXXX"
  exit 1
fi

# Default owner to active gcloud account prefix (e.g. "john" from john@example.com)
if [[ -z "$OWNER" ]]; then
  OWNER=$(gcloud config get-value account 2>/dev/null | cut -d@ -f1 | tr '.' '-')
  [[ -n "$OWNER" ]] || OWNER="lab-owner"
fi

# ── Generate UID ───────────────────────────────────────────────────────────────
# 4 random bytes → 8 lowercase hex chars. GCP project IDs must start with a
# letter, so we force the first char to "a".
_raw=$(python3 -c "import secrets; print(secrets.token_hex(4))" 2>/dev/null \
       || openssl rand -hex 4)
UID_HEX="a${_raw:1}"

PROJECT_A="${UID_HEX}-deployments-palu"
PROJECT_B="${UID_HEX}-webapp-palu"
PROJECT_C="${UID_HEX}-admin-palu"

echo "════════════════════════════════════════════════════════════════════"
echo "  GCP Lab Setup"
echo ""
echo "  Deployment UID : ${UID_HEX}"
echo "  Project A      : ${PROJECT_A}"
echo "  Project B      : ${PROJECT_B}"
echo "  Project C      : ${PROJECT_C}"
echo "  Billing        : ${BILLING_ACCOUNT}"
echo "  Region / Zone  : ${REGION} / ${ZONE}"
echo "  Owner label    : ${OWNER}"
echo "════════════════════════════════════════════════════════════════════"
echo ""

# ── Guard: don't silently overwrite an existing terraform.tfvars ──────────────
if [[ -f "$TFVARS" ]]; then
  echo "WARNING: terraform.tfvars already exists."
  read -r -p "         Overwrite? [y/N] " _confirm
  [[ "$_confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  echo ""
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
_banner() { echo "── $* ─────────────────────────────────────────────"; }

_create_project() {
  local id="$1" name="$2"
  if gcloud projects describe "$id" &>/dev/null; then
    echo "  [skip] ${id} already exists."
    return
  fi
  echo "  Creating ${id}..."
  local args=("$id" --name="$name")
  if [[ -n "$FOLDER_ID" ]];   then args+=(--folder="$FOLDER_ID")
  elif [[ -n "$ORG_ID" ]];    then args+=(--organization="$ORG_ID")
  fi
  gcloud projects create "${args[@]}"
}

_link_billing() {
  local id="$1"
  echo "  Linking billing to ${id}..."
  gcloud billing projects link "$id" \
    --billing-account="$BILLING_ACCOUNT" --quiet
}

_enable_apis() {
  local id="$1"; shift
  echo "  ${id}: enabling $(echo "$@" | tr ' ' '\n' | wc -l | tr -d ' ') APIs..."
  gcloud services enable "$@" --project="$id" --quiet
}

# ── Step 1: Create projects ───────────────────────────────────────────────────
_banner "1/3  Create GCP projects"
_create_project "$PROJECT_A" "Lab Deployments ${UID_HEX}"
_create_project "$PROJECT_B" "Lab Webapp ${UID_HEX}"
_create_project "$PROJECT_C" "Lab Admin ${UID_HEX}"
echo ""

# ── Step 2: Link billing ──────────────────────────────────────────────────────
_banner "2/3  Link billing"
_link_billing "$PROJECT_A"
_link_billing "$PROJECT_B"
_link_billing "$PROJECT_C"
echo ""

# ── Step 3: Enable APIs ───────────────────────────────────────────────────────
_banner "3/3  Enable required APIs"

# Project A — deployments: compute, Cloud SQL, IAM, GCS
_enable_apis "$PROJECT_A" \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  compute.googleapis.com \
  sqladmin.googleapis.com

# Project B — webapp: Cloud Functions, KMS, Secret Manager, BigQuery
_enable_apis "$PROJECT_B" \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iam.googleapis.com \
  storage.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  bigquery.googleapis.com

# Project C — admin: IAM, GCS, Secret Manager, IAM Credentials (token generation)
_enable_apis "$PROJECT_C" \
  cloudresourcemanager.googleapis.com \
  serviceusage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com
echo ""

# ── Write terraform.tfvars ────────────────────────────────────────────────────
_banner "Writing terraform.tfvars"
cat > "$TFVARS" <<EOF
# Generated by scripts/setup.sh — do not commit this file.

# ── GCP projects ──────────────────────────────────────────────────────────────
project_id        = "${PROJECT_A}"
webapp_project_id = "${PROJECT_B}"
admin_project_id  = "${PROJECT_C}"

# ── Shared settings ───────────────────────────────────────────────────────────
region = "${REGION}"
zone   = "${ZONE}"
owner  = "${OWNER}"

# ── Pre-set deployment UID ────────────────────────────────────────────────────
# Generated by setup.sh and used by lab-01 instead of random_id.deployment,
# ensuring project names match the UID chosen above.
deployment_uid = "${UID_HEX}"
EOF

echo "  Written: terraform.tfvars"
echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "  Setup complete. Deploy the full lab chain with:"
echo ""
echo "    ./scripts/deploy-chain.sh apply"
echo ""
echo "  Tear everything down with:"
echo ""
echo "    ./scripts/deploy-chain.sh destroy"
echo "════════════════════════════════════════════════════════════════════"
