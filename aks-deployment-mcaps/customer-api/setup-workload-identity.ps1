# Azure Workload Identity Setup for Customer API
# This script creates the managed identity and federated credentials needed for AKS pods to access Azure PostgreSQL

# Configuration
$RESOURCE_GROUP = "azure-vinay-mcaps-rg"
$AKS_CLUSTER = "aks-vinay-mcaps"
$MANAGED_IDENTITY_NAME = "customer-api-identity"
$SERVICE_ACCOUNT_NAME = "customer-api-sa"
$SERVICE_ACCOUNT_NAMESPACE = "app"
$LOCATION = "uaenorth"

Write-Host "=== Azure Workload Identity Setup ===" -ForegroundColor Cyan
Write-Host "Resource Group: $RESOURCE_GROUP" -ForegroundColor Yellow
Write-Host "AKS Cluster: $AKS_CLUSTER" -ForegroundColor Yellow
Write-Host "Managed Identity: $MANAGED_IDENTITY_NAME" -ForegroundColor Yellow
Write-Host ""

# Step 1: Get AKS OIDC Issuer URL
Write-Host "[1/6] Getting AKS OIDC Issuer URL..." -ForegroundColor Green
$AKS_OIDC_ISSUER = az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER --query "oidcIssuerProfile.issuerUrl" -o tsv

if (-not $AKS_OIDC_ISSUER) {
    Write-Host "ERROR: Failed to get OIDC issuer URL. Make sure OIDC is enabled on your AKS cluster." -ForegroundColor Red
    Write-Host "Run: az aks update -g $RESOURCE_GROUP -n $AKS_CLUSTER --enable-oidc-issuer" -ForegroundColor Yellow
    exit 1
}
Write-Host "OIDC Issuer: $AKS_OIDC_ISSUER" -ForegroundColor White

# Step 2: Create User-Assigned Managed Identity
Write-Host "`n[2/6] Creating managed identity '$MANAGED_IDENTITY_NAME'..." -ForegroundColor Green
az identity create --name $MANAGED_IDENTITY_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

# Get the identity details
$IDENTITY_CLIENT_ID = az identity show --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query 'clientId' -o tsv
$IDENTITY_OBJECT_ID = az identity show --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query 'principalId' -o tsv
$IDENTITY_RESOURCE_ID = az identity show --resource-group $RESOURCE_GROUP --name $MANAGED_IDENTITY_NAME --query 'id' -o tsv

Write-Host "Client ID: $IDENTITY_CLIENT_ID" -ForegroundColor White
Write-Host "Object ID: $IDENTITY_OBJECT_ID" -ForegroundColor White
Write-Host "Resource ID: $IDENTITY_RESOURCE_ID" -ForegroundColor White

# Step 3: Create Kubernetes Service Account
Write-Host "`n[3/6] Creating Kubernetes service account..." -ForegroundColor Green
kubectl create serviceaccount $SERVICE_ACCOUNT_NAME --namespace $SERVICE_ACCOUNT_NAMESPACE

# Annotate the service account with the managed identity client ID
kubectl annotate serviceaccount $SERVICE_ACCOUNT_NAME `
    --namespace $SERVICE_ACCOUNT_NAMESPACE `
    azure.workload.identity/client-id=$IDENTITY_CLIENT_ID

Write-Host "Service account '$SERVICE_ACCOUNT_NAME' created in namespace '$SERVICE_ACCOUNT_NAMESPACE'" -ForegroundColor White

# Step 4: Create Federated Identity Credential
Write-Host "`n[4/6] Creating federated identity credential..." -ForegroundColor Green
az identity federated-credential create `
    --name "customer-api-federated-credential" `
    --identity-name $MANAGED_IDENTITY_NAME `
    --resource-group $RESOURCE_GROUP `
    --issuer $AKS_OIDC_ISSUER `
    --subject "system:serviceaccount:${SERVICE_ACCOUNT_NAMESPACE}:${SERVICE_ACCOUNT_NAME}" `
    --audience api://AzureADTokenExchange

Write-Host "Federated credential created successfully" -ForegroundColor White

# Step 5: Grant ACR Pull Permission to Managed Identity
Write-Host "`n[5/6] Granting AcrPull permission to managed identity..." -ForegroundColor Green
$ACR_NAME = "acrvinayaks0603"
$ACR_RESOURCE_ID = az acr show --name $ACR_NAME --query id -o tsv

az role assignment create `
    --assignee $IDENTITY_OBJECT_ID `
    --role "AcrPull" `
    --scope $ACR_RESOURCE_ID

Write-Host "AcrPull role assigned to managed identity" -ForegroundColor White

# Step 6: Display PostgreSQL Configuration Instructions
Write-Host "`n[6/6] PostgreSQL Configuration" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "To grant PostgreSQL access to the managed identity, run these SQL commands:" -ForegroundColor Yellow
Write-Host ""
Write-Host "-- Connect to your PostgreSQL server as admin user" -ForegroundColor Gray
Write-Host "-- Then execute these commands:" -ForegroundColor Gray
Write-Host ""
Write-Host "-- Add the managed identity as a PostgreSQL user" -ForegroundColor Gray
Write-Host "SELECT * FROM pgaadauth_create_principal('$MANAGED_IDENTITY_NAME', false, false);" -ForegroundColor White
Write-Host ""
Write-Host "-- Grant necessary permissions" -ForegroundColor Gray
Write-Host "GRANT ALL PRIVILEGES ON DATABASE postgres TO `"$MANAGED_IDENTITY_NAME`";" -ForegroundColor White
Write-Host "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO `"$MANAGED_IDENTITY_NAME`";" -ForegroundColor White
Write-Host "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO `"$MANAGED_IDENTITY_NAME`";" -ForegroundColor White
Write-Host "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO `"$MANAGED_IDENTITY_NAME`";" -ForegroundColor White
Write-Host "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO `"$MANAGED_IDENTITY_NAME`";" -ForegroundColor White
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan

# Step 7: Display Next Steps
Write-Host "`n=== Setup Complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Update k8s-deployment.yaml - Replace 

clearwith:" -ForegroundColor White
Write-Host "   $IDENTITY_CLIENT_ID" -ForegroundColor Cyan
Write-Host ""
Write-Host "2. Rebuild Docker image for linux/amd64 platform:" -ForegroundColor White
Write-Host "   docker build --platform linux/amd64 -t acrvinayaks0603.azurecr.io/customer-api:1.0.0 ." -ForegroundColor Cyan
Write-Host ""
Write-Host "3. Push image to ACR:" -ForegroundColor White
Write-Host "   az acr login --name acrvinayaks0603" -ForegroundColor Cyan
Write-Host "   docker push acrvinayaks0603.azurecr.io/customer-api:1.0.0" -ForegroundColor Cyan
Write-Host ""
Write-Host "4. Configure PostgreSQL access (see SQL commands above)" -ForegroundColor White
Write-Host ""
Write-Host "5. Apply updated Kubernetes manifests:" -ForegroundColor White
Write-Host "   kubectl apply -f k8s-deployment.yaml" -ForegroundColor Cyan
Write-Host ""
Write-Host "6. Verify pods are running:" -ForegroundColor White
Write-Host "   kubectl get pods -n app" -ForegroundColor Cyan
Write-Host ""

# Save the client ID to a file for easy reference
$IDENTITY_CLIENT_ID | Out-File -FilePath "client-id.txt" -Encoding UTF8
Write-Host "Managed Identity Client ID saved to client-id.txt" -ForegroundColor Green
