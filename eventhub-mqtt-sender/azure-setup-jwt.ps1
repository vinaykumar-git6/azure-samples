# ============================================================
# Azure Event Grid MQTT - JWT Authentication Setup
# ============================================================
# This script configures Azure Event Grid for JWT (Azure AD) authentication

# Variables
$SUBSCRIPTION_ID = "86339c66-ee25-474d-b5bb-b334aad19c32"
$RESOURCE_GROUP = "MyEventHubRG"
$EVENTGRID_NAMESPACE = "myeventgrid-mqtt-ns0603"
$RESOURCE_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/namespaces/$EVENTGRID_NAMESPACE"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Azure Event Grid JWT Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 1: Create Topic Space
# ============================================================
# Topic space defines MQTT topic patterns that clients can access
# Pattern "sensors/#" allows: sensors/telemetry, sensors/data, etc.

Write-Host "STEP 1: Creating topic space..." -ForegroundColor Yellow
az resource create --id "$RESOURCE_ID/topicSpaces/sensors" --properties '{
    "topicTemplates": ["sensors/#"]
}'
Write-Host "✅ Topic space 'sensors' created" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 2: Create Client Group (uses $all for simplicity)
# ============================================================
# Client group $all includes all clients - simplifies permissions
# Alternative: Create custom group with query filter

Write-Host "STEP 2: Using \$all client group (built-in)" -ForegroundColor Yellow
Write-Host "ℹ️  The \$all group includes all registered clients" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# STEP 3: Create Permission Bindings
# ============================================================
# Grant publish and subscribe permissions to $all client group

Write-Host "STEP 3: Creating permission bindings..." -ForegroundColor Yellow

# Publisher permission
az eventgrid namespace permission-binding create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-publisher-binding `
  --client-group-name '$all' `
  --topic-space-name sensors `
  --permission Publisher

Write-Host "✅ Publisher permission created" -ForegroundColor Green

# Subscriber permission
az eventgrid namespace permission-binding create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-subscriber-binding `
  --client-group-name '$all' `
  --topic-space-name sensors `
  --permission Subscriber

Write-Host "✅ Subscriber permission created" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 4: Create Azure AD App Registration (Service Principal)
# ============================================================
# Service Principal is used to generate JWT tokens

Write-Host "STEP 4: Creating Azure AD App Registration..." -ForegroundColor Yellow

$clientId = az ad app create --display-name "EventGridMQTTApp" --query appId -o tsv
Write-Host "App Client ID: $clientId" -ForegroundColor Cyan

$spId = az ad sp create --id $clientId --query id -o tsv
Write-Host "Service Principal ID: $spId" -ForegroundColor Cyan

# Generate client secret
$secretInfo = az ad app credential reset --id $clientId --append | ConvertFrom-Json

Write-Host ""
Write-Host "⚠️  SAVE THESE CREDENTIALS!" -ForegroundColor Red
Write-Host "================================" -ForegroundColor Yellow
Write-Host "Client ID:      $($secretInfo.appId)" -ForegroundColor White
Write-Host "Tenant ID:      $($secretInfo.tenant)" -ForegroundColor White
Write-Host "Client Secret:  $($secretInfo.password)" -ForegroundColor White
Write-Host "================================" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# STEP 5: Assign RBAC Roles
# ============================================================
# Grant the service principal permission to publish/subscribe

Write-Host "STEP 5: Assigning RBAC roles..." -ForegroundColor Yellow

az role assignment create `
  --assignee $spId `
  --role "EventGrid TopicSpaces Publisher" `
  --scope $RESOURCE_ID

az role assignment create `
  --assignee $spId `
  --role "EventGrid TopicSpaces Subscriber" `
  --scope $RESOURCE_ID

Write-Host "✅ RBAC roles assigned" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 6: Register MQTT Client (No attributes needed with $all)
# ============================================================
# Register the MQTT client in Event Grid namespace

Write-Host "STEP 6: Registering MQTT client..." -ForegroundColor Yellow

az eventgrid namespace client create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensor-app-001 `
  --state Enabled `
  --description "MQTT client for sensor data"

Write-Host "✅ MQTT client 'sensor-app-001' registered" -ForegroundColor Green
Write-Host ""

# ============================================================
# STEP 7: Update .env File
# ============================================================

Write-Host "STEP 7: Updating .env file..." -ForegroundColor Yellow

$hostname = az resource show --ids $RESOURCE_ID --query "properties.topicSpacesConfiguration.hostname" -o tsv

$envContent = @"
# Azure Event Grid MQTT Configuration

# Event Grid MQTT Hostname
EVENTGRID_HOSTNAME=$hostname

# MQTT Topic (must match topic space pattern)
MQTT_TOPIC=sensors/telemetry

# MQTT Port (8883 for TLS)
MQTT_PORT=8883

# MQTT Client ID (must match Event Grid registered client name)
MQTT_CLIENT_ID=sensor-app-001

# Azure AD JWT Authentication (Service Principal)
AZURE_CLIENT_ID=$($secretInfo.appId)
AZURE_TENANT_ID=$($secretInfo.tenant)
AZURE_CLIENT_SECRET=$($secretInfo.password)
"@

$envContent | Out-File -FilePath ".env" -Encoding ASCII

Write-Host "✅ .env file updated" -ForegroundColor Green
Write-Host ""

# ============================================================
# Summary
# ============================================================

Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  - Topic Space: sensors (pattern: sensors/#)" -ForegroundColor White
Write-Host "  - Client Group: `$all (includes all clients)" -ForegroundColor White
Write-Host "  - Permissions: Publisher + Subscriber" -ForegroundColor White
Write-Host "  - Client ID: sensor-app-001" -ForegroundColor White
Write-Host "  - MQTT Hostname: $hostname" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Run: uv run python mqtt_sender.py" -ForegroundColor White
Write-Host "  2. Messages will be published to: sensors/telemetry" -ForegroundColor White
Write-Host ""
