## ============================================================
## AKS Private Cluster – API Server VNet Integration
##
## Key differences vs classic private cluster (AKS-pvt.ps1):
##   - API server injected directly into VNet via dedicated subnet
##   - Supports toggling private/public mode AFTER creation
##   - No Private Link / Private Endpoint used
##   - DNS zone format: private.<region>.azmk8s.io (not privatelink.*)
##   - Requires a dedicated /28 subnet for the API server
## ============================================================

## ============================================================
## Variables – reuses existing VNet from pvt-aks-cluster
## ============================================================
$RESOURCE_GROUP         = "pvt-aks-rg"
$LOCATION               = "uaenorth"
$AKS_NAME               = "pvt-aks-vnetint-cluster"     # new cluster name
$IDENTITY_NAME          = "pvt-aks-vnetint-identity"    # new identity

## Reuse existing VNet
$VNET_NAME              = "pvt-aks-vnet"
$NODE_SUBNET_NAME       = "pvt-aks-subnet"              # existing node subnet

## New dedicated API server subnet (must be /28 minimum, not shared with nodes)
$APISERVER_SUBNET_NAME  = "pvt-aks-apiserver-subnet"
$APISERVER_SUBNET_CIDR  = "10.10.12.0/28"              # 16 IPs, carved from existing VNet (10.10.0.0/16)

## DNS zone for VNet integration – different format from classic private cluster
$DNS_ZONE_NAME          = "private.uaenorth.azmk8s.io" # format: private.<region>.azmk8s.io

## Networking (same as existing cluster)
$SERVICE_CIDR           = "10.10.8.0/22"
$DNS_SERVICE_IP         = "10.10.8.10"
$POD_CIDR               = "192.168.0.0/16"

## ============================================================
## Step 1 – Get existing VNet & Node Subnet IDs
## ============================================================
$VNET_ID = $(az network vnet show `
    --resource-group $RESOURCE_GROUP `
    --name $VNET_NAME `
    --query id --output tsv)

$NODE_SUBNET_ID = $(az network vnet subnet show `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $NODE_SUBNET_NAME `
    --query id --output tsv)

Write-Host "Reusing VNet: $VNET_ID"
Write-Host "Reusing Node Subnet: $NODE_SUBNET_ID"

## ============================================================
## Step 2 – Create Dedicated API Server Subnet
##   Must be /28 minimum, delegated to AKS
##   Cannot overlap with node subnet (10.10.0.0/22) or
##   service CIDR (10.10.8.0/22)
## ============================================================
az network vnet subnet create `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $APISERVER_SUBNET_NAME `
    --address-prefixes $APISERVER_SUBNET_CIDR `
    --delegations Microsoft.ContainerService/managedClusters

$APISERVER_SUBNET_ID = $(az network vnet subnet show `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $APISERVER_SUBNET_NAME `
    --query id --output tsv)

Write-Host "API Server Subnet: $APISERVER_SUBNET_ID"

## ============================================================
## Step 3 – Create New User-Assigned Managed Identity
## ============================================================
az identity create `
    --resource-group $RESOURCE_GROUP `
    --name $IDENTITY_NAME

$IDENTITY_ID = $(az identity show `
    --resource-group $RESOURCE_GROUP `
    --name $IDENTITY_NAME `
    --query id --output tsv)

$IDENTITY_PRINCIPAL_ID = $(az identity show `
    --resource-group $RESOURCE_GROUP `
    --name $IDENTITY_NAME `
    --query principalId --output tsv)

## ============================================================
## Step 4 – Assign Network Contributor on VNet
## ============================================================
az role assignment create `
    --assignee $IDENTITY_PRINCIPAL_ID `
    --role "Network Contributor" `
    --scope $VNET_ID

## ============================================================
## Step 5 – Create Private DNS Zone
##   Note: format is "private.<region>.azmk8s.io"
##   NOT "privatelink.<region>.azmk8s.io" (that's for classic private cluster)
## ============================================================
az network private-dns zone create `
    --resource-group $RESOURCE_GROUP `
    --name $DNS_ZONE_NAME

$DNS_ZONE_ID = $(az network private-dns zone show `
    --resource-group $RESOURCE_GROUP `
    --name $DNS_ZONE_NAME `
    --query id --output tsv)

## ============================================================
## Step 6 – Assign Private DNS Zone Contributor
## ============================================================
az role assignment create `
    --assignee $IDENTITY_PRINCIPAL_ID `
    --role "Private DNS Zone Contributor" `
    --scope $DNS_ZONE_ID

## ============================================================
## Step 7 – Link DNS Zone to VNet
## ============================================================
az network private-dns link vnet create `
    --resource-group $RESOURCE_GROUP `
    --zone-name $DNS_ZONE_NAME `
    --name "pvt-aks-vnetint-dns-link" `
    --virtual-network $VNET_ID `
    --registration-enabled false

## ============================================================
## Step 8 – Create AKS Cluster with API Server VNet Integration
##
##   --enable-apiserver-vnet-integration  → injects API server into VNet
##   --apiserver-subnet-id                → dedicated /28 subnet for API server
##   --enable-private-cluster             → makes cluster private (toggleable later)
##   --private-dns-zone $DNS_ZONE_ID      → use our custom DNS zone
##   --disable-public-fqdn                → no public FQDN at all
##
##   To toggle private mode later (NOT possible with classic private cluster):
##     az aks update --enable-private-cluster  (make private)
##     az aks update --disable-private-cluster (make public)
## ============================================================
az aks create `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --location $LOCATION `
    --load-balancer-sku standard `
    --generate-ssh-keys `
    --enable-managed-identity `
    --assign-identity $IDENTITY_ID `
    --node-count 1 `
    --enable-cluster-autoscaler `
    --min-count 1 `
    --max-count 3 `
    --network-plugin azure `
    --network-plugin-mode overlay `
    --network-policy calico `
    --pod-cidr $POD_CIDR `
    --service-cidr $SERVICE_CIDR `
    --dns-service-ip $DNS_SERVICE_IP `
    --vnet-subnet-id $NODE_SUBNET_ID `
    --enable-apiserver-vnet-integration `
    --apiserver-subnet-id $APISERVER_SUBNET_ID `
    --enable-private-cluster `
    --private-dns-zone $DNS_ZONE_ID `
    --disable-public-fqdn `
    --zones 1 2 3

## ============================================================
## Step 9 – Add App Linux Node Pool
## ============================================================
az aks nodepool add `
    --resource-group $RESOURCE_GROUP `
    --cluster-name $AKS_NAME `
    --name applinux `
    --mode System `
    --node-count 1 `
    --enable-cluster-autoscaler `
    --min-count 1 `
    --max-count 3 `
    --os-type Linux `
    --vnet-subnet-id $NODE_SUBNET_ID `
    --zones 1 2 3

## ============================================================
## Step 10 – Get Credentials (from jumpbox or peered VNet)
## ============================================================
az aks get-credentials `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME

## ============================================================
## Step 11 – How to toggle private mode later (unique to VNet integration)
## ============================================================
Write-Host ""
Write-Host "============================================================"
Write-Host " To DISABLE private mode (make API server public):"
Write-Host "   az aks update --resource-group $RESOURCE_GROUP --name $AKS_NAME --disable-private-cluster"
Write-Host ""
Write-Host " To RE-ENABLE private mode:"
Write-Host "   az aks update --resource-group $RESOURCE_GROUP --name $AKS_NAME --enable-private-cluster"
Write-Host "============================================================"
