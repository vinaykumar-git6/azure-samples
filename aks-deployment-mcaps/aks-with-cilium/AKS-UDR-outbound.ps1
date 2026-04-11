# ============================================================
# AKS with UDR Outbound Type + Azure Firewall + Cilium
# ============================================================
# This script sets up:
#   1. Azure Firewall in the existing VNet
#   2. Route Table with default route to firewall
#   3. AKS cluster with outbound type = userDefinedRouting
# ============================================================

$RESOURCE_GROUP = "azure-vk-rg"
$LOCATION = "uaenorth"
$AKS_NAME = "aks-vk-with-cilium"
$VNET_NAME = "aks-vk-vnet"
$AKS_SUBNET_NAME = "aks-subnet"
$VM_SKU = "Standard_D2as_v5"

# Firewall variables
$FW_NAME = "aks-vk-firewall"
$FW_PIP_NAME = "aks-vk-fw-pip"
$FW_SUBNET_NAME = "AzureFirewallSubnet"  # Must be exactly this name
$FW_SUBNET_PREFIX = "10.0.21.0/24"
$ROUTE_TABLE_NAME = "aks-vk-udr-rt"

# Identity variables
$AKS_IDENTITY = "aks-identity-vk"
$KUBELET_IDENTITY = "kubelet-identity-vk"

# ============================================================
# Step 1: Create Azure Firewall Subnet in existing VNet
# ============================================================
Write-Host "Creating Azure Firewall subnet..." -ForegroundColor Cyan
az network vnet subnet create `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $FW_SUBNET_NAME `
    --address-prefix $FW_SUBNET_PREFIX

# ============================================================
# Step 2: Create Public IP for Azure Firewall
# ============================================================
Write-Host "Creating Public IP for Azure Firewall..." -ForegroundColor Cyan
az network public-ip create `
    --resource-group $RESOURCE_GROUP `
    --name $FW_PIP_NAME `
    --allocation-method Static `
    --sku Standard

# ============================================================
# Step 3: Create Azure Firewall (with DNS proxy enabled)
# ============================================================
# DNS proxy is required for FQDN-based network rules to work
Write-Host "Creating Azure Firewall (this may take 5-10 minutes)..." -ForegroundColor Cyan
az network firewall create `
    --resource-group $RESOURCE_GROUP `
    --name $FW_NAME `
    --location $LOCATION `
    --sku AZFW_VNet `
    --tier Standard `
    --enable-dns-proxy true

# Associate firewall with public IP and subnet
az network firewall ip-config create `
    --firewall-name $FW_NAME `
    --name "fw-config" `
    --public-ip-address $FW_PIP_NAME `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME

# Update firewall to apply IP config
az network firewall update `
    --resource-group $RESOURCE_GROUP `
    --name $FW_NAME

# Get Firewall Private IP
$FW_PRIVATE_IP = $(az network firewall show `
    --resource-group $RESOURCE_GROUP `
    --name $FW_NAME `
    --query "ipConfigurations[0].privateIPAddress" -o tsv)
Write-Host "Firewall Private IP: $FW_PRIVATE_IP" -ForegroundColor Green

$FW_PUBLIC_IP = $(az network public-ip show `
    --resource-group $RESOURCE_GROUP `
    --name $FW_PIP_NAME `
    --query "ipAddress" -o tsv)
Write-Host "Firewall Public IP: $FW_PUBLIC_IP" -ForegroundColor Green

# ============================================================
# Step 4: Create Firewall Network Rules for AKS
# ============================================================
Write-Host "Creating firewall network rules for AKS..." -ForegroundColor Cyan

# AKS required network rules
az network firewall network-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-network-rules" `
    --priority 200 `
    --action Allow `
    --name "allow-apiserver-udp" `
    --protocols UDP `
    --source-addresses "10.0.0.0/20" `
    --destination-addresses "AzureCloud.$LOCATION" `
    --destination-ports 1194

az network firewall network-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-network-rules" `
    --name "allow-apiserver-tcp" `
    --protocols TCP `
    --source-addresses "10.0.0.0/20" `
    --destination-addresses "AzureCloud.$LOCATION" `
    --destination-ports 9000

az network firewall network-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-network-rules" `
    --name "allow-ntp" `
    --protocols UDP `
    --source-addresses "10.0.0.0/20" `
    --destination-fqdns "ntp.ubuntu.com" `
    --destination-ports 123

# GitHub Container Registry (ghcr.io)
az network firewall network-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-network-rules" `
    --name "allow-ghcr" `
    --protocols TCP `
    --source-addresses "10.0.0.0/20" `
    --destination-fqdns "ghcr.io" "pkg-containers.githubusercontent.com" `
    --destination-ports 443

# Docker Hub
az network firewall network-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-network-rules" `
    --name "allow-docker" `
    --protocols TCP `
    --source-addresses "10.0.0.0/20" `
    --destination-fqdns "docker.io" "registry-1.docker.io" "production.cloudflare.docker.com" `
    --destination-ports 443

# ============================================================
# Step 5: Create Firewall Application Rules for AKS
# ============================================================
Write-Host "Creating firewall application rules for AKS..." -ForegroundColor Cyan

# Use AzureKubernetesService FQDN tag (automatically includes all required FQDNs
# and stays up-to-date as Microsoft updates the list)
az network firewall application-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-fqdn-rules" `
    --priority 300 `
    --action Allow `
    --name "allow-aks-fqdn-tag" `
    --source-addresses "10.0.0.0/20" `
    --protocols http=80 https=443 `
    --fqdn-tags "AzureKubernetesService"

# ------------------------------------------------------------------
# AKS Backup Extension — Geneva Monitoring agent FQDNs
# Required for dataprotection-microsoft-geneva-service pod to start
# ------------------------------------------------------------------
az network firewall application-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-fqdn-rules" `
    --name "allow-geneva-monitoring" `
    --source-addresses "10.0.0.0/20" `
    --protocols https=443 `
    --target-fqdns `
        "gcs.prod.monitoring.core.windows.net" `
        "*.prod.warm.ingest.monitor.core.windows.net" `
        "global.prod.microsoftmetrics.com" `
        "shoebox2.prod.microsoftmetrics.com" `
        "*.prod.microsoftmetrics.com"

# AKS Backup Extension — Microsoft Container Registry (image pull)
az network firewall application-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-fqdn-rules" `
    --name "allow-mcr-backup" `
    --source-addresses "10.0.0.0/20" `
    --protocols https=443 `
    --target-fqdns `
        "mcr.microsoft.com" `
        "*.data.mcr.microsoft.com"

# AKS Backup Extension — Azure Backup / Data Protection endpoints
az network firewall application-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-fqdn-rules" `
    --name "allow-azure-backup" `
    --source-addresses "10.0.0.0/20" `
    --protocols https=443 `
    --target-fqdns `
        "*.backup.windowsazure.com" `
        "*.blob.core.windows.net" `
        "*.queue.core.windows.net"

# AKS Backup Extension — Azure AD authentication
az network firewall application-rule create `
    --resource-group $RESOURCE_GROUP `
    --firewall-name $FW_NAME `
    --collection-name "aks-required-fqdn-rules" `
    --name "allow-aad-backup" `
    --source-addresses "10.0.0.0/20" `
    --protocols https=443 `
    --target-fqdns `
        "login.microsoftonline.com" `
        "*.login.microsoftonline.com"
## Allow internet
az network firewall application-rule create `
    --resource-group azure-vk-rg `
    --firewall-name aks-vk-firewall `
    --collection-name "allow-internet-rules" `
    --priority 600 `
    --action Allow `
    --name "allow-internet-https" `
    --source-addresses "10.0.0.0/20" `
    --protocols http=80 https=443 `
    --target-fqdns "*"        

# ============================================================
# Azure DevOps Agent Pool - explicit allow rule
# Required for self-hosted ADO agents running in AKS pods
# ============================================================
az network firewall application-rule create `
    --resource-group azure-vk-rg `
    --firewall-name aks-vk-firewall `
    --collection-name "allow-ado-agent-rules" `
    --priority 510 `
    --action Allow `
    --name "allow-azure-devops" `
    --source-addresses "10.0.0.0/20" `
    --protocols https=443 `
    --target-fqdns `
        "dev.azure.com" `
        "*.dev.azure.com" `
        "login.microsoftonline.com" `
        "login.windows.net" `
        "vstsagentpackage.azureedge.net" `
        "*.vssps.visualstudio.com" `
        "*.vsblob.visualstudio.com" `
        "*.visualstudio.com" `
        "*.vsassets.io" `
        "packages.microsoft.com" `
        "*.blob.core.windows.net"
Write-Host "ADO agent pool rules added to firewall." -ForegroundColor Green

# ============================================================
# Step 6: Create Route Table and Associate with AKS Subnet
# ============================================================
Write-Host "Creating Route Table..." -ForegroundColor Cyan
az network route-table create `
    --resource-group $RESOURCE_GROUP `
    --name $ROUTE_TABLE_NAME `
    --location $LOCATION `
    --disable-bgp-route-propagation true

# Add default route to firewall
az network route-table route create `
    --resource-group $RESOURCE_GROUP `
    --route-table-name $ROUTE_TABLE_NAME `
    --name "default-route" `
    --address-prefix 0.0.0.0/0 `
    --next-hop-type VirtualAppliance `
    --next-hop-ip-address $FW_PRIVATE_IP

# Add internet route for firewall public IP (required for return traffic)
az network route-table route create `
    --resource-group $RESOURCE_GROUP `
    --route-table-name $ROUTE_TABLE_NAME `
    --name "fw-internet-route" `
    --address-prefix "$FW_PUBLIC_IP/32" `
    --next-hop-type Internet

Write-Host "Associating Route Table with AKS subnet..." -ForegroundColor Cyan
az network vnet subnet update `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $AKS_SUBNET_NAME `
    --route-table $ROUTE_TABLE_NAME

# ============================================================
# Step 7: Get existing identity IDs
# ============================================================
$AKS_IDENTITY_ID = $(az identity show --name $AKS_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
$KUBELET_IDENTITY_ID = $(az identity show --name $KUBELET_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
$SUBNET_ID = $(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name $AKS_SUBNET_NAME --query id -o tsv)

Write-Host "AKS Identity ID: $AKS_IDENTITY_ID"
Write-Host "Kubelet Identity ID: $KUBELET_IDENTITY_ID"
Write-Host "Subnet ID: $SUBNET_ID"

# ============================================================
# Step 8: Assign Network Contributor role to AKS identity
#         on the route table and subnet (required for UDR)
# ============================================================
Write-Host "Assigning Network Contributor role to AKS identity..." -ForegroundColor Cyan

$AKS_IDENTITY_PRINCIPAL_ID = $(az identity show --name $AKS_IDENTITY --resource-group $RESOURCE_GROUP --query principalId -o tsv)

$RT_ID = $(az network route-table show --resource-group $RESOURCE_GROUP --name $ROUTE_TABLE_NAME --query id -o tsv)

az role assignment create `
    --assignee $AKS_IDENTITY_PRINCIPAL_ID `
    --role "Network Contributor" `
    --scope $SUBNET_ID

az role assignment create `
    --assignee $AKS_IDENTITY_PRINCIPAL_ID `
    --role "Network Contributor" `
    --scope $RT_ID

# ============================================================
# Step 9: Create AKS Cluster with UDR Outbound Type + Cilium
# ============================================================
Write-Host "Updating existing AKS cluster to UDR outbound type..." -ForegroundColor Cyan

az aks update --resource-group $RESOURCE_GROUP `
              --name $AKS_NAME `
              --outbound-type userDefinedRouting `
              --api-server-authorized-ip-ranges $FW_PUBLIC_IP

Write-Host "AKS Cluster outbound type updated to UDR successfully!" -ForegroundColor Green

# ============================================================
# Step 10: Add developer IP to API server authorized ranges
# ============================================================
Write-Host "Adding your current IP to API server authorized ranges..." -ForegroundColor Cyan
$CURRENT_IP = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
az aks update `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --api-server-authorized-ip-ranges "$FW_PUBLIC_IP,$CURRENT_IP/32"

# ============================================================
# Step 11: Verify outbound type
# ============================================================
Write-Host "`nVerifying outbound configuration..." -ForegroundColor Cyan
az aks show --resource-group $RESOURCE_GROUP `
            --name $AKS_NAME `
            --query "networkProfile.outboundType" -o tsv

# Get credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing
Write-Host "Done! Use 'kubectl get nodes' to verify cluster." -ForegroundColor Green
