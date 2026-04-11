## ============================================================
## Variables – reuse same resource group as AKS
## ============================================================
$RESOURCE_GROUP     = "pvt-aks-rg"
$LOCATION           = "uaenorth"

## Jumpbox VNet – /25 = 128 IPs (126 usable)
$JB_VNET_NAME       = "jumpbox-vnet"
$JB_SUBNET_NAME     = "jumpbox-subnet"
$JB_VNET_CIDR       = "10.20.0.0/25"          # 128 IPs
$JB_SUBNET_CIDR     = "10.20.0.0/25"          # single subnet, uses all IPs

## Jumpbox VM
$JB_VM_NAME         = "jumpbox-vm"
$JB_ADMIN_USER      = "azureuser"
$JB_VM_SIZE         = "Standard_B2s"          # 2 vCPU, 4GB – small & cheap

## Existing AKS VNet (from AKS-pvt.ps1) – needed for peering
$AKS_VNET_NAME      = "pvt-aks-vnet"
$AKS_DNS_ZONE_NAME  = "privatelink.uaenorth.azmk8s.io"

## ============================================================
## Step 1 – Create Jumpbox VNet & Subnet (/25 = 128 IPs)
## ============================================================
az network vnet create `
    --resource-group $RESOURCE_GROUP `
    --name $JB_VNET_NAME `
    --address-prefixes $JB_VNET_CIDR `
    --subnet-name $JB_SUBNET_NAME `
    --subnet-prefixes $JB_SUBNET_CIDR

$JB_VNET_ID = $(az network vnet show `
    --resource-group $RESOURCE_GROUP `
    --name $JB_VNET_NAME `
    --query id --output tsv)

$AKS_VNET_ID = $(az network vnet show `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_VNET_NAME `
    --query id --output tsv)

## ============================================================
## Step 2 – VNet Peering (bidirectional)
##   Jumpbox VNet <-> AKS VNet
##   Required so jumpbox can reach AKS private endpoint
## ============================================================
## Peer: jumpbox → AKS
az network vnet peering create `
    --resource-group $RESOURCE_GROUP `
    --name "jumpbox-to-aks" `
    --vnet-name $JB_VNET_NAME `
    --remote-vnet $AKS_VNET_ID `
    --allow-vnet-access

## Peer: AKS → jumpbox
az network vnet peering create `
    --resource-group $RESOURCE_GROUP `
    --name "aks-to-jumpbox" `
    --vnet-name $AKS_VNET_NAME `
    --remote-vnet $JB_VNET_ID `
    --allow-vnet-access

## ============================================================
## Step 3 – Link AKS Private DNS Zone to Jumpbox VNet
##   Without this, DNS resolution of the AKS API server FQDN
##   fails even after peering
## ============================================================
az network private-dns link vnet create `
    --resource-group $RESOURCE_GROUP `
    --zone-name $AKS_DNS_ZONE_NAME `
    --name "jumpbox-dns-link" `
    --virtual-network $JB_VNET_ID `
    --registration-enabled false

## ============================================================
## Step 4 – Create Jumpbox Linux VM
##   - SSH key auth (no password)
##   - Public IP for initial SSH access
##   - Ubuntu 22.04 LTS
## ============================================================
az vm create `
    --resource-group $RESOURCE_GROUP `
    --name $JB_VM_NAME `
    --location $LOCATION `
    --vnet-name $JB_VNET_NAME `
    --subnet $JB_SUBNET_NAME `
    --image Ubuntu2204 `
    --size $JB_VM_SIZE `
    --admin-username $JB_ADMIN_USER `
    --generate-ssh-keys `
    --public-ip-sku Standard `
    --nsg-rule SSH

$JB_PUBLIC_IP = $(az vm show `
    --resource-group $RESOURCE_GROUP `
    --name $JB_VM_NAME `
    --show-details `
    --query publicIps --output tsv)

Write-Host "Jumpbox Public IP: $JB_PUBLIC_IP"

## ============================================================
## Step 5 – Install kubectl & Azure CLI on the jumpbox
##   Run via SSH after the VM is created
## ============================================================
$INSTALL_SCRIPT = @'
#!/bin/bash
set -e

## Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

## Install kubectl
sudo az aks install-cli

## Install kubelogin (needed for AAD-enabled clusters)
sudo az aks install-cli

echo "kubectl version: $(kubectl version --client --short)"
echo "az version: $(az version)"
'@

# Write script to a temp file and upload via SCP, then execute
$INSTALL_SCRIPT | Out-File -FilePath "$env:TEMP\install-tools.sh" -Encoding ascii -NoNewline

Write-Host ""
Write-Host "============================================================"
Write-Host " Jumpbox VM ready: $JB_PUBLIC_IP"
Write-Host "============================================================"
Write-Host ""
Write-Host " Step 1 – Copy install script to jumpbox:"
Write-Host "   scp $env:TEMP\install-tools.sh ${JB_ADMIN_USER}@${JB_PUBLIC_IP}:~/install-tools.sh"
Write-Host ""
Write-Host " Step 2 – SSH into jumpbox:"
Write-Host "   ssh ${JB_ADMIN_USER}@${JB_PUBLIC_IP}"
Write-Host ""
Write-Host " Step 3 – Run on jumpbox to install kubectl & az CLI:"
Write-Host "   chmod +x ~/install-tools.sh && ~/install-tools.sh"
Write-Host ""
Write-Host " Step 4 – Login to Azure on jumpbox and get AKS credentials:"
Write-Host "   az login"
Write-Host "   az aks get-credentials --resource-group $RESOURCE_GROUP --name pvt-aks-cluster"
Write-Host ""
Write-Host " Step 5 – Verify connectivity:"
Write-Host "   kubectl get nodes"
Write-Host "============================================================"

# Enable system-assigned managed identity on the jumpbox VM
az vm identity assign `
    --resource-group pvt-aks-rg `
    --name jumpbox-vm

# Get the managed identity principal ID
$JB_IDENTITY_PID = $(az vm show `
    --resource-group pvt-aks-rg `
    --name jumpbox-vm `
    --query identity.principalId --output tsv)

# Get the AKS cluster resource ID
$AKS_ID = $(az aks show `
    --resource-group pvt-aks-rg `
    --name pvt-aks-cluster `
    --query id --output tsv)

# Assign AKS Cluster User role to the jumpbox managed identity
az role assignment create `
    --assignee $JB_IDENTITY_PID `
    --role "Azure Kubernetes Service Cluster User Role" `
    --scope $AKS_ID

Write-Host "Done. Now on the jumpbox run: az login --identity"

## login to jumpbox
ssh azureuser@20.74.247.83

#Role assigned successfully. Now switch to your SSH terminal and run these on the jumpbox:
az login --identity
az aks get-credentials --resource-group pvt-aks-rg --name pvt-aks-cluster --overwrite-existing
kubelogin convert-kubeconfig -l msi
kubectl get nodes