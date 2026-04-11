# #cluster creation AKS private with Azure CNI overlay, UDR egress via Firewall/NVA, and custom private DNS zone

## ============================================================
## Variables
## ============================================================
$RESOURCE_GROUP     = "pvt-aks-rg"
$LOCATION           = "uaenorth"
$AKS_NAME           = "pvt-aks-cluster"
$VNET_NAME          = "pvt-aks-vnet"
$SUBNET_NAME        = "pvt-aks-subnet"
$IDENTITY_NAME      = "pvt-aks-identity"
$DNS_ZONE_NAME      = "privatelink.uaenorth.azmk8s.io"   # format: privatelink.<region>.azmk8s.io
$VNET_CIDR          = "10.10.0.0/16"           # Smaller VNet – overlay pods don't need VNet IPs
$SUBNET_CIDR        = "10.10.0.0/22"           # /22 = 1022 usable IPs, enough for nodes only
$SERVICE_CIDR       = "10.10.8.0/22"           # Kubernetes service IPs (non-overlapping)
$DNS_SERVICE_IP     = "10.10.8.10"             # Must be within SERVICE_CIDR
$POD_CIDR           = "192.168.0.0/16"         # Overlay pod IPs – NOT routed on VNet
$ROUTE_TABLE_NAME   = "pvt-aks-routetable"
$FIREWALL_IP        = "10.10.1.4"              # Private IP of your Azure Firewall / NVA (VirtualAppliance next hop)
$NODE_VM_SIZE       = "Standard_D4s_v5"        # VM SKU for all node pools – change as per right-sizing              # Private IP of your Azure Firewall / NVA (VirtualAppliance next hop)

## ============================================================
## Step 1 – Create Resource Group
## ============================================================
az group create `
    --name $RESOURCE_GROUP `
    --location $LOCATION

## ============================================================
## Step 2 – Create VNet & Subnet
## ============================================================
az network vnet create `
    --resource-group $RESOURCE_GROUP `
    --name $VNET_NAME `
    --address-prefixes $VNET_CIDR `
    --subnet-name $SUBNET_NAME `
    --subnet-prefixes $SUBNET_CIDR

$SUBNET_ID = $(az network vnet subnet show `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $SUBNET_NAME `
    --query id --output tsv)

$VNET_ID = $(az network vnet show `
    --resource-group $RESOURCE_GROUP `
    --name $VNET_NAME `
    --query id --output tsv)

## ============================================================
## Step 2b – Create Route Table + UDR and Associate with Subnet
##   Egress via UDR (userDefinedRouting) – traffic exits through
##   Azure Firewall / NVA instead of a managed load balancer.
##   REQUIREMENT: 0.0.0.0/0 default route MUST exist on the subnet
##   before cluster creation, or az aks create will fail.
## ============================================================
az network route-table create `
    --resource-group $RESOURCE_GROUP `
    --name $ROUTE_TABLE_NAME `
    --location $LOCATION

# Default route → Azure Firewall / NVA private IP
az network route-table route create `
    --resource-group $RESOURCE_GROUP `
    --route-table-name $ROUTE_TABLE_NAME `
    --name "default-via-firewall" `
    --address-prefix "0.0.0.0/0" `
    --next-hop-type VirtualAppliance `
    --next-hop-ip-address $FIREWALL_IP

$ROUTE_TABLE_ID = $(az network route-table show `
    --resource-group $RESOURCE_GROUP `
    --name $ROUTE_TABLE_NAME `
    --query id --output tsv)

# Associate route table with the AKS subnet
az network vnet subnet update `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $SUBNET_NAME `
    --route-table $ROUTE_TABLE_ID

## ============================================================
## Step 3 – Create User-Assigned Managed Identity
##   (Required when using a custom or system private DNS zone)
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

$SUBSCRIPTION_ID = $(az account show --query id --output tsv)

## ============================================================
## Step 4 – Assign Network Contributor on VNet to the Identity
## ============================================================
az role assignment create `
    --assignee $IDENTITY_PRINCIPAL_ID `
    --role "Network Contributor" `
    --scope $VNET_ID

## ============================================================
## Step 5 – Create Private DNS Zone. if you are using System Private DNS Zone, skip this step as it will be automatically created in the managed resource group with name "privatelink.<region>.azmk8s.io"
##   Format: privatelink.<region>.azmk8s.io
## ============================================================
az network private-dns zone create `
    --resource-group $RESOURCE_GROUP `
    --name $DNS_ZONE_NAME

$DNS_ZONE_ID = $(az network private-dns zone show `
    --resource-group $RESOURCE_GROUP `
    --name $DNS_ZONE_NAME `
    --query id --output tsv)

## ============================================================
## Step 6 – Assign Private DNS Zone Contributor to the Identity
## ============================================================
az role assignment create `
    --assignee $IDENTITY_PRINCIPAL_ID `
    --role "Private DNS Zone Contributor" `
    --scope $DNS_ZONE_ID

## ============================================================
## Step 7 – Link Private DNS Zone to the VNet
## ============================================================
az network private-dns link vnet create `
    --resource-group $RESOURCE_GROUP `
    --zone-name $DNS_ZONE_NAME `
    --name "$VNET_NAME-dns-link" `
    --virtual-network $VNET_ID `
    --registration-enabled false

## ============================================================
## Step 8 – Create Private AKS Cluster
##   - Private cluster (no public API server endpoint)
##   - No public FQDN (--disable-public-fqdn)
##   - Custom private DNS zone
##   - CNI Overlay networking
##   - Egress via UDR (--outbound-type userDefinedRouting)
##     AKS will NOT create outbound LB rules; all egress flows
##     through the route table → Firewall / NVA.
##   - egress is UDR
##    - SKU is standard
##   - private-dns-zone is system . dns will be create in managed resource group with name "privatelink.<region>.azmk8s.io"
##   - Since it is UDR - for private cluster Source to Destination FQDN port opening is needed
##   - disable-local-accounts (for full Azure RBAC enforcement with no kubeconfig cert-based admin access)
## ============================================================
az aks create `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --location $LOCATION `
    --tier standard `
    --generate-ssh-keys `
    --enable-managed-identity `
    --assign-identity $IDENTITY_ID `
    --enable-azure-rbac `
    --disable-local-accounts `
    --nodepool-name system-np `
    --node-vm-size $NODE_VM_SIZE `
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
    --vnet-subnet-id $SUBNET_ID `
    --outbound-type userDefinedRouting `
    --enable-private-cluster `
    --private-dns-zone system `
    --disable-public-fqdn `
    --zones 1 2 3

## ============================================================
## Step 9 – Add App Linux Node Pool (System mode, 1 node)
##   Note: AKS node pool names must be lowercase alphanumeric, max 12 chars
##   "App Linux Node Pool" → applinux
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
    --node-vm-size $NODE_VM_SIZE `
    --os-type Linux `
    --vnet-subnet-id $SUBNET_ID `
    --zones 1 2 3

## ============================================================
## Step 10 – Get Credentials (run from within the VNet / jump box)
## ============================================================
az aks get-credentials `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME

## ============================================================
## Step 11 – Patch Karpenter default NodePool (Node Auto Provisioning)
##   Add taint karpenter.azure.com/disable:NoSchedule to the default
##   NodePool so that Karpenter does NOT auto-provision nodes for
##   general workloads on it. Only pods that explicitly tolerate
##   this taint will land on Karpenter-provisioned nodes from this pool.
##   This is the recommended pattern to disable the default NodePool
##   while keeping dedicated NodePools for specific workloads.
## ============================================================

# Check current state of the default NodePool
kubectl get nodepool default -o yaml

# Patch the default NodePool to add the disable taint
$patch = @'
{
  "spec": {
    "template": {
      "spec": {
        "taints": [
          {
            "key": "karpenter.azure.com/disable",
            "effect": "NoSchedule"
          }
        ]
      }
    }
  }
}
'@

kubectl patch nodepool default --type merge -p $patch

# Patch 2 – Set cpu limit to 0 so Karpenter cannot provision ANY new nodes
# from the default NodePool (hard capacity cap = 0 CPU = no new nodes allowed)
$patchLimits = @'
{
  "spec": {
    "limits": {
      "cpu": "0"
    }
  }
}
'@

kubectl patch nodepool default --type merge -p $patchLimits

# Verify the patch was applied
kubectl get nodepool default -o jsonpath='{.spec.template.spec.taints}' | ConvertFrom-Json
kubectl get nodepool default -o jsonpath='{.spec.limits}'

## enable App routing Add on with NGINX ingress controller
az aks approuting enable --resource-group <ResourceGroupName> --name <ClusterName>