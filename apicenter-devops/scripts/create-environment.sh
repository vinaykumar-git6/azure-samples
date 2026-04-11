#!/usr/bin/env bash
# create-environment.sh – Idempotently creates an environment in Azure API Center
set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)      SUBSCRIPTION="$2";       shift 2 ;;
    --resource-group)    RESOURCE_GROUP="$2";     shift 2 ;;
    --service-name)      SERVICE_NAME="$2";       shift 2 ;;
    --environment-id)    ENVIRONMENT_ID="$2";     shift 2 ;;
    --environment-title) ENVIRONMENT_TITLE="$2";  shift 2 ;;
    --environment-kind)  ENVIRONMENT_KIND="$2";   shift 2 ;;
    --server-url)        SERVER_URL="$2";         shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

: "${SUBSCRIPTION:?}"
: "${RESOURCE_GROUP:?}"
: "${SERVICE_NAME:?}"
: "${ENVIRONMENT_ID:?}"
: "${ENVIRONMENT_TITLE:=$ENVIRONMENT_ID}"
: "${ENVIRONMENT_KIND:=production}"
: "${SERVER_URL:?}"

echo "🔍 Checking if environment '$ENVIRONMENT_ID' exists..."
EXISTING=$(az apic environment show \
  --subscription      "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --environment-id    "$ENVIRONMENT_ID" \
  --query "name" -o tsv 2>/dev/null || echo "")

if [[ -n "$EXISTING" ]]; then
  echo "ℹ️  Environment '$ENVIRONMENT_ID' already exists – updating..."
  az apic environment update \
    --subscription      "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --environment-id    "$ENVIRONMENT_ID" \
    --title             "$ENVIRONMENT_TITLE" \
    --kind              "$ENVIRONMENT_KIND" \
    --server            "{\"managementPortalUri\":[\"$SERVER_URL\"]}"
  echo "✅ Environment '$ENVIRONMENT_ID' updated."
else
  echo "➕ Creating environment '$ENVIRONMENT_ID'..."
  az apic environment create \
    --subscription      "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --environment-id    "$ENVIRONMENT_ID" \
    --title             "$ENVIRONMENT_TITLE" \
    --kind              "$ENVIRONMENT_KIND" \
    --server            "{\"managementPortalUri\":[\"$SERVER_URL\"]}"
  echo "✅ Environment '$ENVIRONMENT_ID' created."
fi

az apic environment show \
  --subscription      "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --environment-id    "$ENVIRONMENT_ID" \
  -o json
