# =============================================================================
# create-hub-vnet.ps1
# Creates a Hub VNet with a private-endpoint subnet and links all supported
# Azure Private DNS Zones for centralised private connectivity.
#
# Usage:
#   .\create-hub-vnet.ps1
#   .\create-hub-vnet.ps1 -Location "eastus" -VNetAddressPrefix "10.0.254.0/23"
# =============================================================================

param (
    [string]$SubscriptionId    = "7d1e8453-2920-4f6d-9a6e-bc7005c10a22",
    [string]$ResourceGroup     = "azure-vk-hub",
    [string]$Location          = "uaenorth",
    [string]$VNetName          = "vnet-hub",
    [string]$VNetAddressPrefix = "10.0.254.0/23",
    [string]$PeSubnetName      = "snet-private-endpoints",
    [string]$PeSubnetPrefix    = "10.0.254.0/24"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helper ────────────────────────────────────────────────────────────────────
function Log($msg) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" -ForegroundColor Cyan }

# ── Login / Subscription ──────────────────────────────────────────────────────
az account set --subscription $SubscriptionId
Log "Subscription set: $SubscriptionId"

# ── Resource Group ────────────────────────────────────────────────────────────
Log "Creating resource group '$ResourceGroup' in '$Location'..."
az group create `
    --name     $ResourceGroup `
    --location $Location `
    --output   none

# ── VNet ──────────────────────────────────────────────────────────────────────
Log "Creating VNet '$VNetName' ($VNetAddressPrefix)..."
az network vnet create `
    --resource-group  $ResourceGroup `
    --name            $VNetName `
    --address-prefix  $VNetAddressPrefix `
    --location        $Location `
    --output          none

# ── Private Endpoint Subnet ───────────────────────────────────────────────────
Log "Creating private-endpoint subnet '$PeSubnetName' ($PeSubnetPrefix)..."
az network vnet subnet create `
    --resource-group                   $ResourceGroup `
    --vnet-name                        $VNetName `
    --name                             $PeSubnetName `
    --address-prefixes                 $PeSubnetPrefix `
    --private-endpoint-network-policies Disabled `
    --output                           none

# ── Private DNS Zones ─────────────────────────────────────────────────────────
# Full list of Microsoft-recommended private DNS zone names.
# Ref: https://learn.microsoft.com/azure/private-link/private-endpoint-dns
$dnsZones = @(

    # Storage
    "privatelink.blob.core.windows.net"
    "privatelink.file.core.windows.net"
    "privatelink.queue.core.windows.net"
    "privatelink.table.core.windows.net"
    "privatelink.dfs.core.windows.net"
    "privatelink.web.core.windows.net"

    # Key Vault
    "privatelink.vaultcore.azure.net"

    # SQL / MySQL / PostgreSQL / MariaDB
    "privatelink.database.windows.net"
    "privatelink.mysql.database.azure.com"
    "privatelink.postgres.database.azure.com"
    "privatelink.mariadb.database.azure.com"

    # Cosmos DB
    "privatelink.documents.azure.com"
    "privatelink.mongo.cosmos.azure.com"
    "privatelink.cassandra.cosmos.azure.com"
    "privatelink.gremlin.cosmos.azure.com"
    "privatelink.table.cosmos.azure.com"
    "privatelink.analytics.cosmos.azure.com"

    # Container Registry
    "privatelink.azurecr.io"

    # App Service / Functions / Static Web Apps
    "privatelink.azurewebsites.net"
    "privatelink.azurestaticapps.net"

    # Service Bus / Event Hubs (share the same zone)
    "privatelink.servicebus.windows.net"

    # Event Grid
    "privatelink.eventgrid.azure.net"

    # Azure Cache for Redis
    "privatelink.redis.cache.windows.net"

    # Azure AI / Cognitive Services / OpenAI
    "privatelink.cognitiveservices.azure.com"
    "privatelink.openai.azure.com"
    "privatelink.services.ai.azure.com"

    # Azure Machine Learning
    "privatelink.api.azureml.ms"
    "privatelink.notebooks.azure.net"
    "privatelink.experiments.azureml.net"
    "privatelink.modelmanagement.azureml.net"

    # Azure Monitor / Log Analytics / App Insights
    "privatelink.monitor.azure.com"
    "privatelink.oms.opinsights.azure.com"
    "privatelink.ods.opinsights.azure.com"
    "privatelink.agentsvc.azure-automation.net"
    "privatelink.blob.core.windows.net"       # shared with storage — already listed, harmless duplicate

    # Azure Automation
    "privatelink.azure-automation.net"

    # Azure Data Factory
    "privatelink.datafactory.azure.net"
    "privatelink.adf.azure.com"

    # Azure Synapse Analytics
    "privatelink.sql.azuresynapse.net"
    "privatelink.dev.azuresynapse.net"
    "privatelink.azuresynapse.net"

    # Azure Purview / Governance
    "privatelink.purview.azure.com"
    "privatelink.purviewstudio.azure.com"

    # Azure Search
    "privatelink.search.windows.net"

    # Azure SignalR / Web PubSub
    "privatelink.service.signalr.net"
    "privatelink.webpubsub.azure.com"

    # Azure IoT Hub
    "privatelink.azure-devices.net"
    "privatelink.azure-devices-provisioning.net"

    # Azure Container Apps
    "privatelink.azurecontainerapps.io"

    # Azure Kubernetes Service (API server)
    # NOTE: AKS private DNS zone is region-scoped: privatelink.<region>.azmk8s.io
    # Uncomment and replace <region> as needed:
    # "privatelink.$Location.azmk8s.io"

    # Azure App Configuration
    "privatelink.azconfig.io"

    # Azure API Management
    "privatelink.azure-api.net"

    # Azure Databricks
    "privatelink.azuredatabricks.net"

    # Azure HDInsight
    "privatelink.azurehdinsight.net"

    # Azure Spring Apps
    "privatelink.azuremicroservices.io"

    # Azure Managed Grafana
    "privatelink.grafana.azure.com"

    # Azure Digital Twins
    "privatelink.digitaltwins.azure.net"

    # Azure Attestation
    "privatelink.attest.azure.net"

    # Azure Arc
    "privatelink.his.arc.azure.com"
    "privatelink.guestconfiguration.azure.com"

    # Azure Site Recovery
    "privatelink.siterecovery.windowsazure.com"

    # Azure Health Data Services
    "privatelink.workspace.azurehealthcareapis.com"
    "privatelink.fhir.azurehealthcareapis.com"
    "privatelink.dicom.azurehealthcareapis.com"

    # Azure Media Services
    "privatelink.media.azure.net"

    # Azure Power BI
    "privatelink.analysis.windows.net"
    "privatelink.pbidedicated.windows.net"
    "privatelink.tip1.powerquery.microsoft.com"

    # Azure Maps
    "privatelink.atlas.microsoft.com"

    # Azure Confidential Ledger
    "privatelink.confidential-ledger.azure.com"

    # Azure Dev Center / Deployment Environments
    "privatelink.devcenter.azure.com"

    # Azure Managed HSM (Key Vault)
    "privatelink.managedhsm.azure.net"

    # Azure Batch
    # NOTE: Batch private DNS zone is region-scoped: privatelink.<region>.batch.azure.com
    # Uncomment and replace <region> as needed:
    # "privatelink.$Location.batch.azure.com"
)

# De-duplicate the list (e.g. blob zone appears twice above)
$dnsZones = $dnsZones | Sort-Object -Unique

$total   = $dnsZones.Count
$current = 0

foreach ($zone in $dnsZones) {
    $current++
    Log "[$current/$total] Zone: $zone"

    # Create the Private DNS Zone
    $existing = az network private-dns zone show `
        --resource-group $ResourceGroup `
        --name           $zone `
        --query          "name" `
        --output         tsv 2>$null

    if ($existing) {
        Write-Host "         already exists — skipping creation" -ForegroundColor Yellow
    } else {
        az network private-dns zone create `
            --resource-group $ResourceGroup `
            --name           $zone `
            --output         none
    }

    # Link the zone to the hub VNet (auto-registration off — hub is not a spoke)
    $linkName     = "link-$VNetName-$(($zone -replace '\.', '-' -replace 'privatelink-', ''))"
    $linkExisting = az network private-dns link vnet show `
        --resource-group  $ResourceGroup `
        --zone-name        $zone `
        --name             $linkName `
        --query            "name" `
        --output           tsv 2>$null

    if ($linkExisting) {
        Write-Host "         VNet link already exists — skipping" -ForegroundColor Yellow
    } else {
        az network private-dns link vnet create `
            --resource-group     $ResourceGroup `
            --zone-name          $zone `
            --name               $linkName `
            --virtual-network    $(az network vnet show --resource-group $ResourceGroup --name $VNetName --query id --output tsv) `
            --registration-enabled false `
            --output             none
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Log ""
Log "=== Hub VNet setup complete ==="
Log "  Resource Group : $ResourceGroup"
Log "  VNet           : $VNetName  ($VNetAddressPrefix)"
Log "  PE Subnet      : $PeSubnetName  ($PeSubnetPrefix)"
Log "  DNS Zones      : $total zones created and linked"
