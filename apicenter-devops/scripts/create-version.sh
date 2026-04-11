#!/usr/bin/env bash
# create-version.sh – Idempotently creates an API version in Azure API Center
set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --service-name)   SERVICE_NAME="$2";   shift 2 ;;
    --api-id)         API_ID="$2";         shift 2 ;;
    --version)        VERSION="$2";        shift 2 ;;
    --version-id)     VERSION_ID="$2";     shift 2 ;;
    --lifecycle)      LIFECYCLE="$2";      shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

: "${SUBSCRIPTION:?}"
: "${RESOURCE_GROUP:?}"
: "${SERVICE_NAME:?}"
: "${API_ID:?}"
: "${VERSION:?}"
: "${VERSION_ID:?}"
: "${LIFECYCLE:=development}"

echo "🔍 Checking if version '$VERSION_ID' exists for API '$API_ID'..."
EXISTING=$(az apic api version show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id     "$API_ID" \
  --version-id "$VERSION_ID" \
  --query "name" -o tsv 2>/dev/null || echo "")

if [[ -n "$EXISTING" ]]; then
  echo "ℹ️  Version '$VERSION_ID' already exists – updating lifecycle stage..."
  az apic api version update \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id         "$API_ID" \
    --version-id     "$VERSION_ID" \
    --lifecycle-stage "$LIFECYCLE"
  echo "✅ Version '$VERSION_ID' updated."
else
  echo "➕ Creating version '$VERSION_ID' (title: $VERSION)..."
  az apic api version create \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id         "$API_ID" \
    --version-id     "$VERSION_ID" \
    --title          "$VERSION" \
    --lifecycle-stage "$LIFECYCLE"
  echo "✅ Version '$VERSION_ID' created."
fi

az apic api version show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id     "$API_ID" \
  --version-id "$VERSION_ID" \
  -o json
