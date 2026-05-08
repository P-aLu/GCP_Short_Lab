#!/usr/bin/env bash
# Usage: ./scripts/all-labs.sh <apply|destroy>
# Env:   SKIP_LABS="lab-02-foo lab-03-bar"  (space-separated, optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LABS_DIR="${REPO_ROOT}/labs"
LAB_SCRIPT="${SCRIPT_DIR}/lab.sh"

# ── Argument validation ────────────────────────────────────────────────────────
ACTION="${1:-}"

if [[ "$ACTION" != "apply" && "$ACTION" != "destroy" ]]; then
  echo "Usage: $0 <apply|destroy>"
  exit 1
fi

# ── Discover labs ──────────────────────────────────────────────────────────────
mapfile -t ALL_LABS < <(find "$LABS_DIR" -maxdepth 1 -mindepth 1 -type d -name 'lab-*' | sort)

if [[ "${#ALL_LABS[@]}" -eq 0 ]]; then
  echo "No lab directories found under ${LABS_DIR}"
  exit 0
fi

# Reverse order for destroy so last lab is torn down first
if [[ "$ACTION" == "destroy" ]]; then
  mapfile -t ALL_LABS < <(printf '%s\n' "${ALL_LABS[@]}" | sort -r)
fi

# ── Build skip set ─────────────────────────────────────────────────────────────
declare -A SKIP=()
for s in ${SKIP_LABS:-}; do
  SKIP["$s"]=1
done

# ── Run ────────────────────────────────────────────────────────────────────────
PASSED=()
FAILED=()
SKIPPED=()

for LAB_PATH in "${ALL_LABS[@]}"; do
  LAB=$(basename "$LAB_PATH")

  if [[ -n "${SKIP[$LAB]+_}" ]]; then
    echo "==> SKIP ${LAB}"
    SKIPPED+=("$LAB")
    continue
  fi

  echo ""
  echo "════════════════════════════════════════════════════"
  echo "  ${ACTION^^}: ${LAB}"
  echo "════════════════════════════════════════════════════"

  if bash "$LAB_SCRIPT" "$ACTION" "$LAB"; then
    PASSED+=("$LAB")
  else
    FAILED+=("$LAB")
    echo ""
    echo "ERROR: ${LAB} failed. Stopping."
    break
  fi
done

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "════════════════════════════════════════════════════"
echo "  Passed  : ${#PASSED[@]}  → ${PASSED[*]:-none}"
echo "  Skipped : ${#SKIPPED[@]} → ${SKIPPED[*]:-none}"
echo "  Failed  : ${#FAILED[@]}  → ${FAILED[*]:-none}"
echo "════════════════════════════════════════════════════"

[[ "${#FAILED[@]}" -eq 0 ]]
