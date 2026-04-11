# ---------------------------------------------------------------
# Deploy customer-mock-api to Azure Container Apps (private VNet)
# ---------------------------------------------------------------

$SUBSCRIPTION   = "<YOUR-SUBSCRIPTION-ID>"
$RESOURCE_GROUP = "azure-vk-rg"
$LOCATION       = "uaenorth"
$ACR_NAME       = "<UAE-ACR-NAME>"
$IMAGE_NAME     = "customer-mock-api"
$IMAGE_TAG      = "latest"
$ACR_IMAGE      = "$ACR_NAME.azurecr.io/$IMAGE_NAME`:$IMAGE_TAG"

$VNET_NAME      = "aks-vk-vnet"
$SUBNET_NAME    = "aca-subnet"
$SUBNET_CIDR    = "10.0.32.0/23"  # min /23 required for ACA, non-overlapping with aks-subnet (10.0.0.0/20)

$ACA_ENV_NAME   = "aca-mock-env"
$ACA_APP_NAME   = "customer-mock-api"
$IDENTITY_NAME  = "aca-mock-identity"

az account set --subscription $SUBSCRIPTION

# ---------------------------------------------------------------
# 1. Build & push image to ACR
# ---------------------------------------------------------------
Write-Host "`n[1/5] Building and pushing Docker image..." -ForegroundColor Cyan

az acr login --name $ACR_NAME

docker build -t $ACR_IMAGE "$PSScriptRoot"
docker push $ACR_IMAGE

# ---------------------------------------------------------------
# 2. Create ACA subnet in existing VNet aks-vk-vnet (with required delegation)
# ---------------------------------------------------------------
Write-Host "`n[2/5] Creating aca-subnet in existing VNet $VNET_NAME..." -ForegroundColor Cyan

az network vnet subnet create `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $SUBNET_NAME `
    --address-prefix $SUBNET_CIDR `
    --delegations Microsoft.App/environments

$SUBNET_ID = $(az network vnet subnet show `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $SUBNET_NAME `
    --query id -o tsv)

Write-Host "Subnet ID: $SUBNET_ID"

# ---------------------------------------------------------------
# 3. Create Container Apps Environment (internal / private)
# ---------------------------------------------------------------
Write-Host "`n[3/5] Creating Container Apps Environment (internal)..." -ForegroundColor Cyan

$envExists = $(az containerapp env show --name $ACA_ENV_NAME --resource-group $RESOURCE_GROUP --query "properties.provisioningState" -o tsv 2>$null)
if ($envExists -eq "Succeeded") {
    Write-Host "  Environment already exists and is Succeeded. Skipping creation." -ForegroundColor Yellow
} else {
    az containerapp env create `
        --name $ACA_ENV_NAME `
        --resource-group $RESOURCE_GROUP `
        --location $LOCATION `
        --infrastructure-subnet-resource-id $SUBNET_ID `
        --internal-only true `
        --enable-workload-profiles false `
        --logs-destination none `
        --no-wait

    Write-Host "Waiting for Container Apps Environment to be ready..."
    do {
        Start-Sleep -Seconds 15
        $envState = $(az containerapp env show --name $ACA_ENV_NAME --resource-group $RESOURCE_GROUP --query "properties.provisioningState" -o tsv 2>$null)
        Write-Host "  State: $envState"
    } while ($envState -notin @("Succeeded", "Failed", "Canceled"))

    if ($envState -ne "Succeeded") {
        Write-Host "Environment provisioning failed with state: $envState" -ForegroundColor Red
        exit 1
    }
}

# ---------------------------------------------------------------
# 4. Create user-assigned managed identity + AcrPull role
# ---------------------------------------------------------------
Write-Host "`n[4/5] Setting up Managed Identity for ACR access..." -ForegroundColor Cyan

# Create identity if not exists
$identityExists = $(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query "id" -o tsv 2>$null)
if (-not $identityExists) {
    az identity create --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --location $LOCATION
}

$IDENTITY_ID     = $(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query "id" -o tsv)
$IDENTITY_CLIENT_ID = $(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query "clientId" -o tsv)
$ACR_ID          = $(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" -o tsv)

# Assign AcrPull role (idempotent)
az role assignment create `
    --assignee $IDENTITY_CLIENT_ID `
    --role AcrPull `
    --scope $ACR_ID `
    2>$null

Write-Host "  Identity: $IDENTITY_ID"
Write-Host "  AcrPull role assigned on ACR."

# ---------------------------------------------------------------
# 5. Create Container App (internal ingress, port 8000)
# ---------------------------------------------------------------
Write-Host "`n[5/5] Deploying Container App..." -ForegroundColor Cyan

az containerapp create `
    --name $ACA_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --environment $ACA_ENV_NAME `
    --image $ACR_IMAGE `
    --registry-server "$ACR_NAME.azurecr.io" `
    --registry-identity $IDENTITY_ID `
    --user-assigned $IDENTITY_ID `
    --target-port 8000 `
    --ingress internal `
    --min-replicas 1 `
    --max-replicas 5 `
    --cpu 0.25 `
    --memory 0.5Gi `
    --env-vars APP_ENV=production `
    --no-wait

Write-Host "Waiting for Container App to be ready..."
do {
    Start-Sleep -Seconds 10
    $appState = $(az containerapp show --name $ACA_APP_NAME --resource-group $RESOURCE_GROUP --query "properties.provisioningState" -o tsv 2>$null)
    Write-Host "  State: $appState"
} while ($appState -notin @("Succeeded", "Failed", "Canceled"))

# ---------------------------------------------------------------
# Show result
# ---------------------------------------------------------------
Write-Host "`nDeployment complete!" -ForegroundColor Green

az containerapp show `
    --name $ACA_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "{name:name, fqdn:properties.configuration.ingress.fqdn, state:properties.runningStatus}" `
    -o table

Write-Host "`nInternal FQDN (accessible only within the VNet):"
az containerapp show `
    --name $ACA_APP_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "properties.configuration.ingress.fqdn" -o tsv
