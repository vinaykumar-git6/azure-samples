#!/usr/bin/env bash
# upload-spec.sh – Uploads an API specification to an API Center version definition
set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription)   SUBSCRIPTION="$2";   shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --service-name)   SERVICE_NAME="$2";   shift 2 ;;
    --api-id)         API_ID="$2";         shift 2 ;;
    --version-id)     VERSION_ID="$2";     shift 2 ;;
    --spec-file)      SPEC_FILE="$2";      shift 2 ;;
    --spec-format)    SPEC_FORMAT="$2";    shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

: "${SUBSCRIPTION:?}"
: "${RESOURCE_GROUP:?}"
: "${SERVICE_NAME:?}"
: "${API_ID:?}"
: "${VERSION_ID:?}"
: "${SPEC_FILE:?}"
: "${SPEC_FORMAT:=openapi}"

DEFINITION_ID="openapi-definition"

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "⚠️  Spec file '$SPEC_FILE' not found – skipping upload."
  exit 0
fi

echo "📄 Uploading spec '$SPEC_FILE' (format: $SPEC_FORMAT)..."

# Check if definition already exists
EXISTING=$(az apic api definition show \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id        "$API_ID" \
  --version-id    "$VERSION_ID" \
  --definition-id "$DEFINITION_ID" \
  --query "name" -o tsv 2>/dev/null || echo "")

if [[ -z "$EXISTING" ]]; then
  echo "➕ Creating definition '$DEFINITION_ID'..."
  az apic api definition create \
    --subscription   "$SUBSCRIPTION" \
    -g "$RESOURCE_GROUP" \
    -n "$SERVICE_NAME" \
    --api-id        "$API_ID" \
    --version-id    "$VERSION_ID" \
    --definition-id "$DEFINITION_ID" \
    --title         "OpenAPI Definition"
fi

echo "⬆️  Importing spec file..."
az apic api definition import-specification \
  --subscription   "$SUBSCRIPTION" \
  -g "$RESOURCE_GROUP" \
  -n "$SERVICE_NAME" \
  --api-id        "$API_ID" \
  --version-id    "$VERSION_ID" \
  --definition-id "$DEFINITION_ID" \
  --format        "inline" \
  --value         "$(cat "$SPEC_FILE")" \
  --specification "{\"name\":\"$SPEC_FORMAT\",\"version\":\"3.0.0\"}"

echo "✅ Spec uploaded to definition '$DEFINITION_ID'."
