#!/usr/bin/env bash
# create-deployment.sh – Idempotently creates a deployment linking API version → environment
set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --service-name)   SERVICE_NAME="$2";   shift 2 ;;
    --api-id)         API_ID="$2";         shift 2 ;;
    --version-id)     VERSION_ID="$2";     shift 2 ;;
    --environment-id) ENVIRONMENT_ID="$2"; shift 2 ;;
    --deployment-id)  DEPLOYMENT_ID="$2";  shift 2 ;;
    --server-url)     SERVER_URL="$2";     shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

: "${SUBSCRIPTION:?}"
: "${RESOURCE_GROUP:?}"
: "${SERVICE_NAME:?}"
: "${API_ID:?}"
: "${VERSION_ID:?}"
: "${ENVIRONMENT_ID:?}"
: "${DEPLOYMENT_ID:?}"
: "${SERVER_URL:?}"

# Build the environment resource ID
ENV_RESOURCE_ID="/subscriptions/${SUBSCRIPTION}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiCenter/services/${SERVICE_NAME}/workspaces/default/environments/${ENVIRONMENT_ID}"

echo "🔍 Checking if deployment '$DEPLOYMENT_ID' exists for API '$API_ID'..."
EXISTING=$(az apic api deployment show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id         "$API_ID" \
  --deployment-id  "$DEPLOYMENT_ID" \
  --query "name" -o tsv 2>/dev/null || echo "")

SERVER_JSON="{\"runtimeUri\":[\"$SERVER_URL\"]}"

if [[ -n "$EXISTING" ]]; then
  echo "ℹ️  Deployment '$DEPLOYMENT_ID' already exists – updating..."
  az apic api deployment update \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id         "$API_ID" \
    --deployment-id  "$DEPLOYMENT_ID" \
    --title          "$DEPLOYMENT_ID" \
    --environment-id "$ENV_RESOURCE_ID" \
    --definition-id  "/subscriptions/${SUBSCRIPTION}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiCenter/services/${SERVICE_NAME}/workspaces/default/apis/${API_ID}/versions/${VERSION_ID}/definitions/openapi-definition" \
    --server         "$SERVER_JSON"
  echo "✅ Deployment '$DEPLOYMENT_ID' updated."
else
  echo "➕ Creating deployment '$DEPLOYMENT_ID'..."
  az apic api deployment create \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id         "$API_ID" \
    --deployment-id  "$DEPLOYMENT_ID" \
    --title          "$DEPLOYMENT_ID" \
    --environment-id "$ENV_RESOURCE_ID" \
    --definition-id  "/subscriptions/${SUBSCRIPTION}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiCenter/services/${SERVICE_NAME}/workspaces/default/apis/${API_ID}/versions/${VERSION_ID}/definitions/openapi-definition" \
    --server         "$SERVER_JSON"
  echo "✅ Deployment '$DEPLOYMENT_ID' created."
fi

az apic api deployment show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id         "$API_ID" \
  --deployment-id  "$DEPLOYMENT_ID" \
  -o json
