# PowerShell script to create Azure Cosmos DB account in Europe location
# Prerequisites: Azure CLI installed and authenticated (az login)

# Configuration variables
$resourceGroupName = "myResourceGroup"
$cosmosAccountName = "mycosmosaccount-$(Get-Random -Minimum 1000 -Maximum 9999)"  # Globally unique name
$databaseName = "CustomerDB"
$containerName = "Accounts"
$location = "westeurope"  # Europe location (other options: northeurope, germanywestcentral, etc.)
$partitionKey = "/id"

Write-Host "Starting Cosmos DB creation process in Europe..." -ForegroundColor Green

# Step 1: Create or get resource group
Write-Host "`n[1/5] Creating/getting resource group: $resourceGroupName in $location..." -ForegroundColor Cyan
az group create `
  --name $resourceGroupName `
  --location $location

if ($LASTEXITCODE -ne 0) {
  Write-Host "Error creating resource group" -ForegroundColor Red
  exit 1
}

Write-Host "✓ Resource group created successfully" -ForegroundColor Green

# Step 2: Create Cosmos DB account
Write-Host "`n[2/5] Creating Cosmos DB account: $cosmosAccountName..." -ForegroundColor Cyan
az cosmosdb create `
  --resource-group $resourceGroupName `
  --name $cosmosAccountName `
  --kind GlobalDocumentDB `
  --default-consistency-level "Session" `
  --locations regionName=$location failoverPriority=0

if ($LASTEXITCODE -ne 0) {
  Write-Host "Error creating Cosmos DB account" -ForegroundColor Red
  exit 1
}

Write-Host "✓ Cosmos DB account created successfully" -ForegroundColor Green

# Step 3: Get connection details
Write-Host "`n[3/5] Retrieving connection details..." -ForegroundColor Cyan
$endpoint = az cosmosdb show `
  --resource-group $resourceGroupName `
  --name $cosmosAccountName `
  --query "documentEndpoint" `
  --output tsv

$primaryKey = az cosmosdb keys list `
  --resource-group $resourceGroupName `
  --name $cosmosAccountName `
  --type "keys" `
  --query "primaryMasterKey" `
  --output tsv

Write-Host "✓ Retrieved connection details" -ForegroundColor Green

# Step 4: Create database
Write-Host "`n[4/5] Creating database: $databaseName..." -ForegroundColor Cyan
az cosmosdb sql database create `
  --resource-group $resourceGroupName `
  --account-name $cosmosAccountName `
  --name $databaseName

if ($LASTEXITCODE -ne 0) {
  Write-Host "Error creating database" -ForegroundColor Red
  exit 1
}

Write-Host "✓ Database created successfully" -ForegroundColor Green

# Step 5: Create container with partition key
Write-Host "`n[5/5] Creating container: $containerName with partition key: $partitionKey..." -ForegroundColor Cyan
az cosmosdb sql container create `
  --resource-group $resourceGroupName `
  --account-name $cosmosAccountName `
  --database-name $databaseName `
  --name $containerName `
  --partition-key-path $partitionKey `
  --throughput 400

if ($LASTEXITCODE -ne 0) {
  Write-Host "Error creating container" -ForegroundColor Red
  exit 1
}

Write-Host "✓ Container created successfully" -ForegroundColor Green

# Display results
Write-Host "`n" + ("="*70) -ForegroundColor Yellow
Write-Host "COSMOS DB SETUP COMPLETE - EUROPE LOCATION" -ForegroundColor Green
Write-Host ("="*70) -ForegroundColor Yellow

Write-Host "`nConfiguration Details:" -ForegroundColor Cyan
Write-Host "  Resource Group:    $resourceGroupName"
Write-Host "  Account Name:      $cosmosAccountName"
Write-Host "  Database:          $databaseName"
Write-Host "  Container:         $containerName"
Write-Host "  Partition Key:     $partitionKey"
Write-Host "  Region:            $location"

Write-Host "`nConnection Details:" -ForegroundColor Yellow
Write-Host "  Endpoint: $endpoint"
Write-Host "  Primary Key: $primaryKey"

# Create .env file content
$envContent = @"
COSMOS_ENDPOINT=$endpoint
COSMOS_KEY=$primaryKey
COSMOS_DATABASE=$databaseName
COSMOS_CONTAINER=$containerName
FUNCTIONS_WORKER_RUNTIME=python
"@

Write-Host "`n" + ("="*70) -ForegroundColor Yellow
Write-Host "ENVIRONMENT VARIABLES FOR .env" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Yellow
Write-Host $envContent

# Save to clipboard for easy copying
$envContent | Set-Clipboard
Write-Host "`n✓ Environment variables copied to clipboard!" -ForegroundColor Green

Write-Host "`n" + ("="*70) -ForegroundColor Yellow
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host ("="*70) -ForegroundColor Yellow

Write-Host @"
1. Create or update your .env file:
   
   Option A: Paste from clipboard (already copied)
   Option B: Copy the values shown above manually

2. Update local.settings.json with the same values:
   {
     "COSMOS_ENDPOINT": "$endpoint",
     "COSMOS_KEY": "$primaryKey",
     "COSMOS_DATABASE": "$databaseName",
     "COSMOS_CONTAINER": "$containerName"
   }

3. Start your Azure Functions app:
   cd azure-functions
   `$env:UV_LINK_MODE='copy'
   func start

4. Test the endpoints (in another PowerShell window):
   
   # Health check
   curl http://localhost:7071/api/health
   
   # Create customer
   curl -X POST http://localhost:7071/api/customers `
     -H "Content-Type: application/json" `
     -d '{
       "id": "cust-001",
       "name": "John Doe",
       "email": "john@example.com",
       "phone": "+44-555-0123",
       "account_type": "premium",
       "status": "active",
       "balance": 5000
     }'
   
   # Get customer
   curl http://localhost:7071/api/customers/cust-001
   
   # List all customers
   curl http://localhost:7071/api/customers
   
   # Update customer
   curl -X PUT http://localhost:7071/api/customers/cust-001 `
     -H "Content-Type: application/json" `
     -d '{"balance": 7500, "account_type": "enterprise"}'

5. Deploy to Azure:
   func azure functionapp publish <YOUR_FUNCTION_APP_NAME>

6. Manage Cosmos DB:
   - Azure Portal: https://portal.azure.com
   - Resource Group: $resourceGroupName
   - Account: $cosmosAccountName
   - Location: $location (West Europe)

Available Europe Locations:
   - westeurope      (Amsterdam)
   - northeurope     (Ireland)
   - germanywestcentral (Frankfurt)
   - francecentral   (Paris)
   - uksouth         (London)
   - swedencentral   (Gävle)
   - switzerlandnorth (Zurich)
   - norwayeast      (Norway)
"@

Write-Host "`n✓ Script completed successfully!" -ForegroundColor Green
Write-Host "`nYour Cosmos DB is now ready in $location!" -ForegroundColor Green
