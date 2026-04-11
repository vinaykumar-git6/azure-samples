## ============================================================
## AGIC.ps1 – Application Gateway Ingress Controller Setup
##   Prereq: AKS-pvt.ps1 must have been run first (VNet must exist)
##   Creates: pvt-aks-appgw-subnet + AppGW in pvt-aks-vnet
## ============================================================

## ============================================================
## Variables – must match AKS-pvt.ps1
## ============================================================
$RESOURCE_GROUP     = "pvt-aks-rg"
$LOCATION           = "uaenorth"
$AKS_NAME           = "pvt-aks-cluster"
$VNET_NAME          = "pvt-aks-vnet"
$APPGW_SUBNET_NAME  = "pvt-aks-appgw-subnet"
$APPGW_SUBNET_CIDR  = "10.10.4.0/24"           # Follows node subnet (10.10.0.0/22 ends at .3.255)

## Application Gateway specific
$APPGW_NAME         = "pvt-aks-appgw"
$APPGW_PRIVATE_IP   = "10.10.4.10"             # Static private IP from AppGW subnet (10.10.4.0/24)

## ============================================================
## Step 1 – Create AppGW dedicated subnet in existing VNet
##   AppGW v2 requires a dedicated subnet (no other resources)
## ============================================================
az network vnet subnet create `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $APPGW_SUBNET_NAME `
    --address-prefixes $APPGW_SUBNET_CIDR

$APPGW_SUBNET_ID = $(az network vnet subnet show `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $APPGW_SUBNET_NAME `
    --query id --output tsv)

Write-Host "AppGW Subnet ID: $APPGW_SUBNET_ID"

## Create AGIC Public IP with Standard SKU (required by Standard_v2 – cannot be removed)
az network public-ip create --name appgwingresspip --resource-group $RESOURCE_GROUP --allocation-method Static --sku Standard
az network application-gateway create --name appgwingress --resource-group $RESOURCE_GROUP --sku Standard_v2 --public-ip-address appgwingresspip --vnet-name $VNET_NAME --subnet $APPGW_SUBNET_NAME --priority 100

## Add private frontend IP alongside the public one
az network application-gateway frontend-ip create `
    --gateway-name appgwingress `
    --resource-group $RESOURCE_GROUP `
    --name appGwPrivateFrontendIp `
    --private-ip-address $APPGW_PRIVATE_IP `
    --subnet $APPGW_SUBNET_ID

Write-Host "Private frontend IP '$APPGW_PRIVATE_IP' added to AppGW appgwingress"

## ============================================================
## Block public internet access via NSG on the AppGW subnet
##   Standard_v2 requires a public IP but we can deny external
##   traffic via NSG – AppGW health probes (GatewayManager) must remain allowed
## ============================================================
$APPGW_NSG_NAME = "pvt-aks-appgw-nsg"

az network nsg create `
    --resource-group $RESOURCE_GROUP `
    --name $APPGW_NSG_NAME `
    --location $LOCATION

## Allow Azure infrastructure (GatewayManager) – required for AppGW to function
az network nsg rule create `
    --resource-group $RESOURCE_GROUP `
    --nsg-name $APPGW_NSG_NAME `
    --name AllowGatewayManager `
    --priority 100 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefix GatewayManager `
    --destination-port-ranges 65200-65535

## Allow traffic from within the VNet (internal callers only)
az network nsg rule create `
    --resource-group $RESOURCE_GROUP `
    --nsg-name $APPGW_NSG_NAME `
    --name AllowVnetInbound `
    --priority 200 `
    --direction Inbound `
    --access Allow `
    --protocol Tcp `
    --source-address-prefix VirtualNetwork `
    --destination-port-ranges 80 443

## Deny all internet inbound – blocks public access on port 80/443
az network nsg rule create `
    --resource-group $RESOURCE_GROUP `
    --nsg-name $APPGW_NSG_NAME `
    --name DenyInternetInbound `
    --priority 300 `
    --direction Inbound `
    --access Deny `
    --protocol Tcp `
    --source-address-prefix Internet `
    --destination-port-ranges 80 443

## Associate NSG with the AppGW subnet
az network vnet subnet update `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $APPGW_SUBNET_NAME `
    --network-security-group $APPGW_NSG_NAME

Write-Host "NSG '$APPGW_NSG_NAME' applied – internet traffic blocked on 80/443"

# Enable AGIC Addon in AKS
$appgwId = $(az network application-gateway show `
    --name appgwingress `
    --resource-group $RESOURCE_GROUP `
    --output tsv `
    --query "id")

Write-Host "AppGW ID: $appgwId"

az aks enable-addons `
    --name $AKS_NAME `
    --resource-group $RESOURCE_GROUP `
    --addon ingress-appgw `
    --appgw-id $appgwId

Write-Host "AGIC addon enabled on cluster: $AKS_NAME"

## ============================================================
## Step 4 – Grant AGIC identity permissions
##   AGIC managed identity needs rights to update AppGW config
## ============================================================
$AGIC_IDENTITY_ID = $(az aks show `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --query addonProfiles.ingressApplicationGateway.identity.objectId `
    --output tsv)

az role assignment create `
    --assignee $AGIC_IDENTITY_ID `
    --role "Network Contributor" `
    --scope $APPGW_SUBNET_ID

az role assignment create `
    --assignee $AGIC_IDENTITY_ID `
    --role "Contributor" `
    --scope $appgwId

Write-Host "Role assignments done for AGIC identity: $AGIC_IDENTITY_ID"

## ============================================================
## Step 5 – Verify
## ============================================================
$APPGW_PRIVATE_IP_ACTUAL = $(az network application-gateway show `
    --resource-group $RESOURCE_GROUP `
    --name $APPGW_NAME `
    --query "frontendIPConfigurations[0].privateIPAddress" --output tsv)

Write-Host ""
Write-Host "============================================================"
Write-Host " AGIC Setup Complete"
Write-Host "============================================================"
Write-Host " Application Gateway : $APPGW_NAME"
Write-Host " Private IP          : $APPGW_PRIVATE_IP_ACTUAL"
Write-Host " AKS Cluster         : $AKS_NAME"
Write-Host "============================================================"
Write-Host ""
Write-Host " Deploy a test ingress from the jumpbox:"
Write-Host @'
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: <your-service>
            port:
              number: 80
EOF
'@
Write-Host "============================================================"