#!/usr/bin/env bash
# register-api.sh – Idempotently registers an API in Azure API Center
set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --service-name)   SERVICE_NAME="$2";   shift 2 ;;
    --api-id)         API_ID="$2";         shift 2 ;;
    --api-title)      API_TITLE="$2";      shift 2 ;;
    --api-kind)       API_KIND="$2";       shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

: "${SUBSCRIPTION:?}"
: "${RESOURCE_GROUP:?}"
: "${SERVICE_NAME:?}"
: "${API_ID:?}"
: "${API_TITLE:?}"
: "${API_KIND:=rest}"

echo "🔍 Checking if API '$API_ID' already exists..."
EXISTING=$(az apic api show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id "$API_ID" \
  --query "name" -o tsv 2>/dev/null || echo "")

if [[ -n "$EXISTING" ]]; then
  echo "ℹ️  API '$API_ID' already exists – updating title/kind..."
  az apic api update \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id  "$API_ID" \
    --title   "$API_TITLE" \
    --type    "$API_KIND"
  echo "✅ API '$API_ID' updated."
else
  echo "➕ Registering new API '$API_ID'..."
  az apic api create \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id  "$API_ID" \
    --title   "$API_TITLE" \
    --type    "$API_KIND"
  echo "✅ API '$API_ID' registered."
fi

# Print result
az apic api show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id "$API_ID" \
  -o json
