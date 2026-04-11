# Variables
$resourceGroup = "azure-function-app-lab-rg"
$location = "uaenorth"
$cosmosAccountName = "mycosmosdbacct123"  # must be globally unique
$apiKind = "MongoDB"  # Options: SQL, MongoDB, Cassandra, Gremlin, Table

# Create Cosmos DB Account without zone redundancy
az cosmosdb create `
  --name $cosmosAccountName `
  --resource-group $resourceGroup `
  --location $location `
  --kind $apiKind `
  --default-consistency-level "Session" `
  --enable-automatic-failover false `
  --enable-analytical-storage false `
  --enable-free-tier true `
  --enable-local-auth true `
  --enable-availability-zones false