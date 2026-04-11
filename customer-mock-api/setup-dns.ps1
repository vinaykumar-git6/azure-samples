# ---------------------------------------------------------------
# Create Hub RG + Private DNS Zone for ACA (linked to aks-vk-vnet)
# ---------------------------------------------------------------

$SUBSCRIPTION       = "<YOUR-SUBSCRIPTION-ID>"
$HUB_RG             = "azure-vk-hub"
$LOCATION           = "uaenorth"
$SPOKE_RG           = "azure-vk-rg"
$VNET_NAME          = "aks-vk-vnet"
$ACA_ENV_NAME       = "aca-mock-env"

az account set --subscription $SUBSCRIPTION

# ---------------------------------------------------------------
# 1. Create Hub Resource Group
# ---------------------------------------------------------------
Write-Host "`n[1/4] Creating Hub Resource Group: $HUB_RG..." -ForegroundColor Cyan

az group create --name $HUB_RG --location $LOCATION

# ---------------------------------------------------------------
# 2. Get ACA environment default domain (DNS zone name)
# ---------------------------------------------------------------
Write-Host "`n[2/4] Getting ACA environment default domain..." -ForegroundColor Cyan

$ACA_DEFAULT_DOMAIN = $(az containerapp env show `
    --name $ACA_ENV_NAME `
    --resource-group $SPOKE_RG `
    --query "properties.defaultDomain" -o tsv)

Write-Host "  ACA Default Domain: $ACA_DEFAULT_DOMAIN"

if (-not $ACA_DEFAULT_DOMAIN) {
    Write-Host "Could not retrieve ACA default domain. Check env name and resource group." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------
# 3. Create Private DNS Zone in Hub RG
# ---------------------------------------------------------------
Write-Host "`n[3/4] Creating Private DNS Zone: $ACA_DEFAULT_DOMAIN in $HUB_RG..." -ForegroundColor Cyan

az network private-dns zone create `
    --resource-group $HUB_RG `
    --name $ACA_DEFAULT_DOMAIN

# ---------------------------------------------------------------
# 4. Get ACA static IP and create A record wildcard
# ---------------------------------------------------------------
Write-Host "`n[4/4] Getting ACA static IP and creating wildcard A record..." -ForegroundColor Cyan

$ACA_STATIC_IP = $(az containerapp env show `
    --name $ACA_ENV_NAME `
    --resource-group $SPOKE_RG `
    --query "properties.staticIp" -o tsv)

Write-Host "  ACA Static IP: $ACA_STATIC_IP"

# Wildcard A record so all apps in the env resolve correctly
az network private-dns record-set a create `
    --resource-group $HUB_RG `
    --zone-name $ACA_DEFAULT_DOMAIN `
    --name "*"

az network private-dns record-set a add-record `
    --resource-group $HUB_RG `
    --zone-name $ACA_DEFAULT_DOMAIN `
    --record-set-name "*" `
    --ipv4-address $ACA_STATIC_IP

# Also add record for the zone apex
az network private-dns record-set a create `
    --resource-group $HUB_RG `
    --zone-name $ACA_DEFAULT_DOMAIN `
    --name "@"

az network private-dns record-set a add-record `
    --resource-group $HUB_RG `
    --zone-name $ACA_DEFAULT_DOMAIN `
    --record-set-name "@" `
    --ipv4-address $ACA_STATIC_IP

# ---------------------------------------------------------------
# 5. Link DNS Zone to aks-vk-vnet
# ---------------------------------------------------------------
Write-Host "`n[5/5] Linking DNS Zone to VNet: $VNET_NAME..." -ForegroundColor Cyan

$VNET_ID = $(az network vnet show `
    --resource-group $SPOKE_RG `
    --name $VNET_NAME `
    --query "id" -o tsv)

az network private-dns link vnet create `
    --resource-group $HUB_RG `
    --zone-name $ACA_DEFAULT_DOMAIN `
    --name "link-to-$VNET_NAME" `
    --virtual-network $VNET_ID `
    --registration-enabled false

Write-Host "`nDone!" -ForegroundColor Green
Write-Host "Private DNS Zone : $ACA_DEFAULT_DOMAIN"
Write-Host "Linked VNet      : $VNET_NAME"
Write-Host "Wildcard A record: * -> $ACA_STATIC_IP"
Write-Host "`nAPIM should now resolve the ACA FQDN. Retry your API call."
