$YOUR_INITIALS="digitaltwins"
$INITIALS="$($YOUR_INITIALS)".ToLower()
$RESOURCE_GROUP="dewa-rg"
$AKS_IDENTITY="aks-identity-$($INITIALS)"
$KUBELET_IDENTITY="kubelet-identity-$($INITIALS)"

$VM_SKU="Standard_D2as_v5"

# Define AKS Cluster Name
$AKS_NAME="aks-$($INITIALS)-with-calico"
Write-Host "AKS Cluster Name: $AKS_NAME"

# Create User Assigned Managed Identities
$AKS_IDENTITY_ID=$(az identity create --name $AKS_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
$KUBELET_IDENTITY_ID=$(az identity create --name $KUBELET_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)

# Output the Managed Identity IDs
Write-Host "AKS Identity ID: $AKS_IDENTITY_ID"
Write-Host "Kubelet Identity ID: $KUBELET_IDENTITY_ID"

# Create Log Analytics Workspace
# NO need to create law, as we will use the one created by DEWA team and pass its resource id in the command below to link with AKS cluster
$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID="/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourcegroups/innovationhub/providers/microsoft.operationalinsights/workspaces/redis-law"

# Output the Log Analytics Workspace Resource ID
Write-Host "Log Analytics Workspace Resource ID: 
$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID"

# Define ACR Name
$SUFFIX=(Get-Date -Format "MMddyy")
$ACR_NAME="acr$($INITIALS)$($SUFFIX)"
Write-Host "ACR Name: $ACR_NAME"

$VNET_ID="/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourceGroups/dewa-rg/providers/Microsoft.Network/virtualNetworks/aks-vnet"
$ACR_PE_SUBNET_ID="/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourceGroups/dewa-rg/providers/Microsoft.Network/virtualNetworks/aks-vnet/subnets/node-snet"

# Premium SKU is required for private endpoint support
$ACR_ID=$(az acr create `
    --resource-group $RESOURCE_GROUP `
    --name $ACR_NAME `
    --sku Premium `
    --workspace $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID `
    --public-network-enabled false `
    --query id -o tsv)
Write-Host "ACR ID: $ACR_ID"

# Create Private Endpoint for ACR
$ACR_PE_NAME="pe-$($ACR_NAME)"
az network private-endpoint create `
    --name $ACR_PE_NAME `
    --resource-group $RESOURCE_GROUP `
    --subnet $ACR_PE_SUBNET_ID `
    --private-connection-resource-id $ACR_ID `
    --group-id registry `
    --connection-name "$($ACR_PE_NAME)-conn"
Write-Host "ACR Private Endpoint '$ACR_PE_NAME' created."

# Create Private DNS Zone for ACR
az network private-dns zone create `
    --resource-group $RESOURCE_GROUP `
    --name "privatelink.azurecr.io"

# Link DNS Zone to VNet
az network private-dns link vnet create `
    --resource-group $RESOURCE_GROUP `
    --zone-name "privatelink.azurecr.io" `
    --name "acr-dns-link" `
    --virtual-network $VNET_ID `
    --registration-enabled false

# Register DNS records via DNS zone group (auto-populates A records)
az network private-endpoint dns-zone-group create `
    --resource-group $RESOURCE_GROUP `
    --endpoint-name $ACR_PE_NAME `
    --name "acr-zone-group" `
    --private-dns-zone "privatelink.azurecr.io" `
    --zone-name "privatelink.azurecr.io"
Write-Host "ACR Private DNS Zone and link configured."

# Create AKS Cluster with Cilium Networking
# Create Virtual Network and Subnet for AKS
$SUBNET_ID="/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourceGroups/dewa-rg/providers/Microsoft.Network/virtualNetworks/aks-vnet/subnets/node-snet"
Write-Host "SUBNET ID: $SUBNET_ID"

# Create Private AKS Cluster with Calico Network Policy
az aks create --resource-group $RESOURCE_GROUP `
              --name $AKS_NAME `
              --generate-ssh-keys `
              --enable-managed-identity `
              --assign-identity $AKS_IDENTITY_ID `
              --assign-kubelet-identity $KUBELET_IDENTITY_ID `
              --attach-acr $ACR_ID `
              --node-count 1 `
              --enable-cluster-autoscaler `
              --min-count 1 `
              --max-count 3 `
              --network-plugin azure `
              --network-policy calico `
              --pod-cidr 192.168.0.0/16 `
              --service-cidr 172.16.0.0/16 `
              --dns-service-ip 172.16.0.10 `
              --vnet-subnet-id $SUBNET_ID `
              --node-vm-size $VM_SKU `
              --nodepool-name system1 `
              --enable-addons monitoring `
              --workspace-resource-id $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID `
              --zones 1 2 3 `
              --enable-ahub `
              --enable-private-cluster `
              --private-dns-zone system `
              --enable-app-routing
Write-Host "Private AKS Cluster with Calico Created..."
          
#Add User Node Pool
az aks nodepool add --resource-group $RESOURCE_GROUP `
                    --cluster-name $AKS_NAME `
                    --os-type Linux `
                    --name appnodepool `
                    --node-count 1 `
                    --enable-cluster-autoscaler `
                    --min-count 1 `
                    --max-count 3 `
                    --mode User `
                    --zones 1 2 3 `
                    --node-vm-size $VM_SKU


## Create AGIC Public IP with Standard SKU

# Application Gateway parameters
$APPGW_NAME = "appgw-$($INITIALS)"
$APPGW_PRIVATE_IP = "10.0.0.129 "  # Must be within the APPGW subnet range
$APPGW_SKU = "Standard_v2"
$APPGW_PRIORITY = 100
$APPGW_SUBNET_ID="/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourceGroups/dewa-rg/providers/Microsoft.Network/virtualNetworks/aks-vnet/subnets/appg-snet"

# Create Application Gateway with private frontend IP only (no public IP)
az network application-gateway create --name $APPGW_NAME `
                                      --resource-group $RESOURCE_GROUP `
                                      --sku $APPGW_SKU `
                                      --subnet $APPGW_SUBNET_ID `
                                      --private-ip-address $APPGW_PRIVATE_IP `
                                      --priority $APPGW_PRIORITY `
                                      --no-wait

Write-Host "Application Gateway '$APPGW_NAME' with private frontend IP '$APPGW_PRIVATE_IP' created..."

# Wait for Application Gateway to be fully provisioned
az network application-gateway wait --name $APPGW_NAME `
                                    --resource-group $RESOURCE_GROUP `
                                    --created

# Remove the default public frontend IP configuration (keep only private)
az network application-gateway frontend-ip delete --gateway-name $APPGW_NAME `
                                                   --resource-group $RESOURCE_GROUP `
                                                   --name "appGatewayFrontendIP"

Write-Host "Public frontend IP removed. Application Gateway now uses private IP only."

# Enable AGIC addon in AKS
$APPGW_ID=$(az network application-gateway show --name $APPGW_NAME `
                                                 --resource-group $RESOURCE_GROUP `
                                                 --query id -o tsv)


az aks enable-addons --name $AKS_NAME `
                     --resource-group $RESOURCE_GROUP `
                     --addon ingress-appgw `
                     --appgw-id $APPGW_ID

Write-Host "AGIC addon enabled on AKS cluster '$AKS_NAME'..."                     