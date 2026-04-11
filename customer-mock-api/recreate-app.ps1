# ---------------------------------------------------------------
# Recreate customer-mock-api container app (env already exists)
# ---------------------------------------------------------------

$SUBSCRIPTION   = "<YOUR-SUBSCRIPTION-ID>"
$RESOURCE_GROUP = "azure-vk-rg"
$ACR_NAME       = "<UAE-ACR-NAME>"
$IMAGE_NAME     = "customer-mock-api"
$IMAGE_TAG      = "latest"
$ACR_IMAGE      = "$ACR_NAME.azurecr.io/$IMAGE_NAME`:$IMAGE_TAG"
$ACA_ENV_NAME   = "aca-mock-env"
$ACA_APP_NAME   = "customer-mock-api"
$IDENTITY_NAME  = "aca-mock-identity"

az account set --subscription $SUBSCRIPTION

# Get managed identity resource ID
Write-Host "`n[1/3] Fetching managed identity..." -ForegroundColor Cyan
$IDENTITY_ID = az identity show `
    --name $IDENTITY_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id -o tsv

if (-not $IDENTITY_ID) {
    Write-Error "Managed identity '$IDENTITY_NAME' not found in '$RESOURCE_GROUP'. Run deploy.ps1 first."
    exit 1
}
Write-Host "Identity: $IDENTITY_ID"

# Create the container app
Write-Host "`n[2/3] Creating container app '$ACA_APP_NAME'..." -ForegroundColor Cyan
az containerapp create `
    --name $ACA_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --environment $ACA_ENV_NAME `
    --image $ACR_IMAGE `
    --registry-server "$ACR_NAME.azurecr.io" `
    --registry-identity $IDENTITY_ID `
    --user-assigned $IDENTITY_ID `
    --ingress internal `
    --target-port 8000 `
    --transport http `
    --min-replicas 1 `
    --max-replicas 3 `
    --cpu 0.25 `
    --memory 0.5Gi `
    --no-wait

# Poll until provisioning completes
Write-Host "`n[3/3] Waiting for provisioning to complete..." -ForegroundColor Cyan
$timeout = 300
$elapsed = 0
do {
    Start-Sleep -Seconds 10
    $elapsed += 10
    $state = az containerapp show `
        --name $ACA_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "properties.provisioningState" -o tsv 2>$null
    Write-Host "  [$elapsed s] State: $state"
} while ($state -notin @("Succeeded", "Failed", "Canceled") -and $elapsed -lt $timeout)

if ($state -eq "Succeeded") {
    $fqdn = az containerapp show `
        --name $ACA_APP_NAME `
        --resource-group $RESOURCE_GROUP `
        --query "properties.configuration.ingress.fqdn" -o tsv
    Write-Host "`n✅ Deployment succeeded!" -ForegroundColor Green
    Write-Host "   FQDN: $fqdn" -ForegroundColor Yellow
} else {
    Write-Error "Deployment ended with state: $state"
}
