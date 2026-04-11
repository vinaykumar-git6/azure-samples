# PowerShell script to create Azure Cosmos DB (SQL API) with proper syntax

# Variables
$resourceGroup = "azure-function-app-lab-rg"
$location = "eastus"
$cosmosAccountName = "mycosmosdb-$(Get-Random -Minimum 10000 -Maximum 99999)"
$databaseName = "CustomerDB"
$containerName = "Accounts"
$partitionKey = "/id"

Write-Host "Creating Cosmos DB Account: $cosmosAccountName in $location" -ForegroundColor Cyan
Write-Host "Resource Group: $resourceGroup" -ForegroundColor Cyan

# Step 1: Create Cosmos DB Account (SQL API)
Write-Host "`nStep 1: Creating Cosmos DB Account..." -ForegroundColor Green
az cosmosdb create `
  --name $cosmosAccountName `
  --resource-group $resourceGroup `
  --locations regionName=$location isZoneRedundant=false `
  --default-consistency-level "Session" `
  --enable-automatic-failover false

if ($LASTEXITCODE -ne 0) {
  Write-Host "Error creating Cosmos DB account. Trying without zone redundancy flag..." -ForegroundColor Yellow
  az cosmosdb create `
    --name $cosmosAccountName `
    --resource-group $resourceGroup `
    --kind GlobalDocumentDB `
    --default-consistency-level "Session"
}

Write-Host "✓ Cosmos DB account created" -ForegroundColor Green

# Step 2: Get endpoint and key
Write-Host "`nStep 2: Retrieving connection details..." -ForegroundColor Green
$endpoint = az cosmosdb show `
  --resource-group $resourceGroup `
  --name $cosmosAccountName `
  --query "documentEndpoint" `
  --output tsv

$primaryKey = az cosmosdb keys list `
  --resource-group $resourceGroup `
  --name $cosmosAccountName `
  --type "keys" `
  --query "primaryMasterKey" `
  --output tsv

Write-Host "✓ Connection details retrieved" -ForegroundColor Green

# Step 3: Create database
Write-Host "`nStep 3: Creating database: $databaseName..." -ForegroundColor Green
az cosmosdb sql database create `
  --resource-group $resourceGroup `
  --account-name $cosmosAccountName `
  --name $databaseName

Write-Host "✓ Database created" -ForegroundColor Green

# Step 4: Create container
Write-Host "`nStep 4: Creating container: $containerName..." -ForegroundColor Green
az cosmosdb sql container create `
  --resource-group $resourceGroup `
  --account-name $cosmosAccountName `
  --database-name $databaseName `
  --name $containerName `
  --partition-key-path $partitionKey `
  --throughput 400

Write-Host "✓ Container created" -ForegroundColor Green

# Display results
Write-Host "`n" + ("="*70) -ForegroundColor Yellow
Write-Host "COSMOS DB SUCCESSFULLY CREATED" -ForegroundColor Green
Write-Host ("="*70) -ForegroundColor Yellow

Write-Host "`nConnection Details:" -ForegroundColor Cyan
Write-Host "  Endpoint: $endpoint"
Write-Host "  Primary Key: (retrieve via Azure Portal or 'az cosmosdb keys list')"
Write-Host "  Database: $databaseName"
Write-Host "  Container: $containerName"

Write-Host "`nNow configure your Function App:" -ForegroundColor Yellow
Write-Host @"

az functionapp config appsettings set `
  --name myCustomerFunctionApp `
  --resource-group $resourceGroup `
  --settings `
    "COSMOS_ENDPOINT=$endpoint" `
    "COSMOS_KEY=$primaryKey" `
    "COSMOS_DATABASE=$databaseName" `
    "COSMOS_CONTAINER=$containerName"

"@