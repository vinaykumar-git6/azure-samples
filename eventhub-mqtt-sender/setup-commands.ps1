# ============================================================
# Azure Event Grid JWT Authentication Setup Commands
# Run these commands in PowerShell terminal one by one
# ============================================================

# Set variables
$SUBSCRIPTION_ID = "86339c66-ee25-474d-b5bb-b334aad19c32"
$RESOURCE_GROUP = "MyEventHubRG"
$EVENTGRID_NAMESPACE = "myeventgrid-mqtt-ns0603"
$RESOURCE_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/namespaces/$EVENTGRID_NAMESPACE"

# ============================================================
# STEP 1: Create topic space
# ============================================================
az resource create --id "$RESOURCE_ID/topicSpaces/sensors" --properties "{`"topicTemplates`": [`"sensors/#`"]}"

# ============================================================
# STEP 2: Create publisher permission binding
# ============================================================
az eventgrid namespace permission-binding create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-publisher-binding `
  --client-group-name '$all' `
  --topic-space-name sensors `
  --permission Publisher

# ============================================================
# STEP 3: Create subscriber permission binding
# ============================================================
az eventgrid namespace permission-binding create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensors-subscriber-binding `
  --client-group-name '$all' `
  --topic-space-name sensors `
  --permission Subscriber

# ============================================================
# STEP 4: Create Azure AD app registration
# ============================================================
$clientId = az ad app create --display-name "EventGridMQTTApp" --query appId -o tsv
Write-Host "Client ID: $clientId" -ForegroundColor Cyan

# ============================================================
# STEP 5: Create service principal
# ============================================================
$spId = az ad sp create --id $clientId --query id -o tsv
Write-Host "Service Principal ID: $spId" -ForegroundColor Cyan

# ============================================================
# STEP 6: Generate client secret (SAVE THE OUTPUT!)
# ============================================================
$secretInfo = az ad app credential reset --id $clientId --append | ConvertFrom-Json

Write-Host ""
Write-Host "⚠️  SAVE THESE CREDENTIALS:" -ForegroundColor Red
Write-Host "================================" -ForegroundColor Yellow
Write-Host "Client ID:      $($secretInfo.appId)" -ForegroundColor White
Write-Host "Tenant ID:      $($secretInfo.tenant)" -ForegroundColor White
Write-Host "Client Secret:  $($secretInfo.password)" -ForegroundColor White
Write-Host "================================" -ForegroundColor Yellow
Write-Host ""

# ============================================================
# STEP 7: Assign EventGrid Publisher role
# ============================================================
az role assignment create `
  --assignee $spId `
  --role "EventGrid TopicSpaces Publisher" `
  --scope $RESOURCE_ID

# ============================================================
# STEP 8: Assign EventGrid Subscriber role
# ============================================================
az role assignment create `
  --assignee $spId `
  --role "EventGrid TopicSpaces Subscriber" `
  --scope $RESOURCE_ID

# ============================================================
# STEP 9: Register MQTT client
# ============================================================
az eventgrid namespace client create `
  --namespace-name $EVENTGRID_NAMESPACE `
  --resource-group $RESOURCE_GROUP `
  --name sensor-app-001 `
  --state Enabled `
  --description "MQTT client for sensor data"

# ============================================================
# STEP 10: Get MQTT hostname
# ============================================================
$hostname = az resource show --ids $RESOURCE_ID --query "properties.topicSpacesConfiguration.hostname" -o tsv
Write-Host "MQTT Hostname: $hostname" -ForegroundColor Cyan

# ============================================================
# STEP 11: Update .env file manually with the credentials from STEP 6
# ============================================================
Write-Host ""
Write-Host "✅ Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next: Update your .env file with the credentials shown in STEP 6" -ForegroundColor Yellow
Write-Host "Then run: uv run python mqtt_sender.py" -ForegroundColor Yellow
