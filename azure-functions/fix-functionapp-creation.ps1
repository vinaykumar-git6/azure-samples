# PowerShell script to fix Azure Function App and Storage Account issues
param(
    [string]$ResourceGroup = "azure-function-app-lab-rg",
    [string]$StorageAccount = "devstorage0603",
    [string]$FunctionAppName = "myCustomerFunctionApp",
    [string]$Location = "uaenorth"
)

Write-Host "Azure Function App & Storage Account Fix Script" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Yellow

# Step 1: Register providers
Write-Host "`n[Step 1] Registering Microsoft.Web provider..." -ForegroundColor Cyan
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Storage

$timeout = 0
while ($timeout -lt 60) {
    $state = az provider show --namespace Microsoft.Web --query "registrationState" --output tsv
    if ($state -eq "Registered") {
        Write-Host "  Provider registered" -ForegroundColor Green
        break
    }
    Start-Sleep -Seconds 5
    $timeout += 5
}

# Step 2: Check storage account
Write-Host "`n[Step 2] Checking storage account: $StorageAccount..." -ForegroundColor Cyan
$storageExists = az storage account show --name $StorageAccount --resource-group $ResourceGroup 2>$null
if (-not $storageExists) {
    Write-Host "  Creating new storage account..." -ForegroundColor Yellow
    az storage account create `
        --name $StorageAccount `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --kind StorageV2 `
        --https-only true
    
    Write-Host "  Storage account created" -ForegroundColor Green
} else {
    Write-Host "  Storage account exists" -ForegroundColor Green
}


# Step 3: Configure network access
Write-Host "`n[Step 3] Configuring storage account network access..." -ForegroundColor Cyan
az storage account update `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --default-action Allow `
    --bypass AzureServices

Write-Host "  Network access configured" -ForegroundColor Green

# Step 4: Create file share
Write-Host "`n[Step 4] Creating file share..." -ForegroundColor Cyan
$storageConnectionString = az storage account show-connection-string `
    --name $StorageAccount `
    --resource-group $ResourceGroup `
    --query "connectionString" `
    --output tsv

az storage share create `
    --name $FunctionAppName `
    --connection-string $storageConnectionString 2>$null

Write-Host "  File share created" -ForegroundColor Green

# Step 5: Create Function App
Write-Host "`n[Step 5] Creating Function App: $FunctionAppName..." -ForegroundColor Cyan
az functionapp create `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --storage-account $StorageAccount `
    --runtime python `
    --runtime-version 3.11 `
    --functions-version 4 `
    --os-type Linux `
    --consumption-plan-location $Location

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Function App created successfully" -ForegroundColor Green
} else {
    Write-Host "  Failed to create Function App" -ForegroundColor Red
    exit 1
}

# Step 6: Configure app settings
Write-Host "`n[Step 6] Configuring Function App settings..." -ForegroundColor Cyan
az functionapp config set `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --linux-fx-version "PYTHON|3.11"

Write-Host "  Settings configured" -ForegroundColor Green

# Display results
Write-Host "`n" + ("=" * 70) -ForegroundColor Yellow
Write-Host "SUCCESS - Azure Function App Ready" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Yellow

$appUrl = az functionapp show `
    --name $FunctionAppName `
    --resource-group $ResourceGroup `
    --query "defaultHostName" `
    --output tsv

Write-Host "`nFunction App URL: https://$appUrl" -ForegroundColor Yellow
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Deploy code: func azure functionapp publish $FunctionAppName"
Write-Host "2. Set Cosmos DB settings (see README.md for details)"
Write-Host "3. Test endpoints at: https://$appUrl/api/health"