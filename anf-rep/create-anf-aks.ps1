# =============================================================================
# Create AKS cluster anf-aks-test in anf-dest-vnet (Germany West Central)
#   - New AKS subnet inside existing VNet
#   - Azure CNI + Calico network policy
#   - Managed identity (control plane + kubelet)
#   - ACR attached to cluster
#   - System node pool (1 node) + User node pool (1 node)
# =============================================================================

$ErrorActionPreference = "Stop"

# =============================================================================
# ── VARIABLES ─────────────────────────────────────────────────────────────────
# =============================================================================

$SUBSCRIPTION      = "<YOUR-SUBSCRIPTION-ID>"
$RG                = "anf-mashreq"
$LOCATION          = "germanywestcentral"

# Existing VNet
$VNET_NAME         = "anf-dest-vnet"

# New subnet for AKS nodes — must be within VNet address space 10.0.248.0/23
# Using 10.0.248.0/24 (256 IPs). Azure CNI assigns a VNet IP per pod, /24 is
# sufficient for this test cluster. Adjust if 10.0.248.0/24 is already occupied.
$AKS_SUBNET_NAME   = "subnet-aks"
$AKS_SUBNET_CIDR   = "10.0.248.0/24"

# Service CIDR — must not overlap VNet or AKS subnet
$SERVICE_CIDR      = "172.16.0.0/16"
$DNS_SERVICE_IP    = "172.16.0.10"

# AKS
$CLUSTER_NAME      = "anf-aks-test"
$SYSTEM_POOL_NAME  = "systempool"
$USER_POOL_NAME    = "userpool"
$NODE_SIZE         = "Standard_D2ads_v6"  # smallest allowed 2-vCPU SKU in gwc for this subscription
# $ZONE not needed — Germany West Central does not support AKS availability zones

# ACR — must be globally unique, alphanumeric only
$ACR_NAME          = "<GERMANY-ACR-NAME>"

# Managed identities
$CTRL_IDENTITY     = "id-anf-aks-ctrl"    # control plane
$KUBELET_IDENTITY  = "id-anf-aks-kubelet" # kubelet / node pool

# =============================================================================
# ── HELPERS ───────────────────────────────────────────────────────────────────
# =============================================================================

function Log($msg) { Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" }
function Bail($msg) { Write-Error "[ERROR] $msg"; exit 1 }

az account set --subscription $SUBSCRIPTION | Out-Null
Log "Subscription set to $SUBSCRIPTION"

# =============================================================================
# ── STEP 1: Create AKS subnet ────────────────────────────────────────────────
# =============================================================================

Log "Creating AKS subnet '$AKS_SUBNET_NAME' ($AKS_SUBNET_CIDR) in $VNET_NAME ..."
az network vnet subnet create `
    --resource-group $RG `
    --vnet-name $VNET_NAME `
    --name $AKS_SUBNET_NAME `
    --address-prefixes $AKS_SUBNET_CIDR `
    --subscription $SUBSCRIPTION `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to create AKS subnet" }
Log "AKS subnet created OK"

$AKS_SUBNET_ID = az network vnet subnet show `
    --resource-group $RG `
    --vnet-name $VNET_NAME `
    --name $AKS_SUBNET_NAME `
    --subscription $SUBSCRIPTION `
    --query id -o tsv
Log "Subnet ID: $AKS_SUBNET_ID"

# =============================================================================
# ── STEP 2: Create ACR ───────────────────────────────────────────────────────
# =============================================================================

Log "Creating ACR '$ACR_NAME' (Basic) ..."
az acr create `
    --resource-group $RG `
    --name $ACR_NAME `
    --sku Basic `
    --location $LOCATION `
    --subscription $SUBSCRIPTION `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to create ACR" }

$ACR_ID = az acr show --name $ACR_NAME --resource-group $RG `
    --subscription $SUBSCRIPTION --query id -o tsv
Log "ACR ID: $ACR_ID"

# =============================================================================
# ── STEP 3: Create managed identities ────────────────────────────────────────
# =============================================================================

Log "Creating control-plane managed identity '$CTRL_IDENTITY' ..."
az identity create `
    --resource-group $RG `
    --name $CTRL_IDENTITY `
    --location $LOCATION `
    --subscription $SUBSCRIPTION `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to create control-plane identity" }

$CTRL_ID     = az identity show --resource-group $RG --name $CTRL_IDENTITY `
    --subscription $SUBSCRIPTION --query id -o tsv
$CTRL_PRINCIPAL = az identity show --resource-group $RG --name $CTRL_IDENTITY `
    --subscription $SUBSCRIPTION --query principalId -o tsv

Log "Creating kubelet managed identity '$KUBELET_IDENTITY' ..."
az identity create `
    --resource-group $RG `
    --name $KUBELET_IDENTITY `
    --location $LOCATION `
    --subscription $SUBSCRIPTION `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to create kubelet identity" }

$KUBELET_ID        = az identity show --resource-group $RG --name $KUBELET_IDENTITY `
    --subscription $SUBSCRIPTION --query id -o tsv
$KUBELET_PRINCIPAL = az identity show --resource-group $RG --name $KUBELET_IDENTITY `
    --subscription $SUBSCRIPTION --query principalId -o tsv

Log "Identities created"

# =============================================================================
# ── STEP 4: Role assignments ─────────────────────────────────────────────────
# =============================================================================

# Control-plane identity needs Network Contributor on the VNet subnet
$VNET_ID = az network vnet show --resource-group $RG --name $VNET_NAME `
    --subscription $SUBSCRIPTION --query id -o tsv

Log "Assigning Network Contributor to control-plane identity on VNet ..."
az role assignment create `
    --assignee $CTRL_PRINCIPAL `
    --role "Network Contributor" `
    --scope $VNET_ID `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to assign Network Contributor" }

# Kubelet identity needs AcrPull on the ACR
Log "Assigning AcrPull to kubelet identity on ACR ..."
az role assignment create `
    --assignee $KUBELET_PRINCIPAL `
    --role "AcrPull" `
    --scope $ACR_ID `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to assign AcrPull" }

# Control-plane identity needs Managed Identity Operator on kubelet identity
Log "Assigning Managed Identity Operator to control-plane identity on kubelet identity ..."
az role assignment create `
    --assignee $CTRL_PRINCIPAL `
    --role "Managed Identity Operator" `
    --scope $KUBELET_ID `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to assign Managed Identity Operator" }

Log "Role assignments complete"

# =============================================================================
# ── STEP 5: Create AKS cluster (system node pool) ────────────────────────────
# =============================================================================

Log "Creating AKS cluster '$CLUSTER_NAME' — this takes ~5 minutes ..."

az aks create `
    --resource-group $RG `
    --name $CLUSTER_NAME `
    --location $LOCATION `
    --subscription $SUBSCRIPTION `
    --node-count 1 `
    --node-vm-size $NODE_SIZE `
    --nodepool-name $SYSTEM_POOL_NAME `
    --network-plugin azure `
    --network-policy calico `
    --vnet-subnet-id $AKS_SUBNET_ID `
    --service-cidr $SERVICE_CIDR `
    --dns-service-ip $DNS_SERVICE_IP `
    --assign-identity $CTRL_ID `
    --assign-kubelet-identity $KUBELET_ID `
    --generate-ssh-keys `
    --enable-managed-identity `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to create AKS cluster" }

Log "AKS cluster '$CLUSTER_NAME' created OK"

# =============================================================================
# ── STEP 6: Add user node pool ───────────────────────────────────────────────
# =============================================================================

Log "Adding user node pool '$USER_POOL_NAME' (1 node, $NODE_SIZE) ..."

az aks nodepool add `
    --resource-group $RG `
    --cluster-name $CLUSTER_NAME `
    --name $USER_POOL_NAME `
    --node-count 1 `
    --node-vm-size $NODE_SIZE `
    --mode User `
    --subscription $SUBSCRIPTION `
    --output none
if ($LASTEXITCODE -ne 0) { Bail "Failed to add user node pool" }

Log "User node pool '$USER_POOL_NAME' added OK"

# =============================================================================
# ── STEP 7: Get kubeconfig ───────────────────────────────────────────────────
# =============================================================================

Log "Fetching kubeconfig ..."
az aks get-credentials `
    --resource-group $RG `
    --name $CLUSTER_NAME `
    --subscription $SUBSCRIPTION `
    --overwrite-existing
if ($LASTEXITCODE -ne 0) { Bail "Failed to get kubeconfig" }

# =============================================================================
# ── DONE ──────────────────────────────────────────────────────────────────────
# =============================================================================

Log "=== All done ==="
Log "  Cluster  : $CLUSTER_NAME"
Log "  ACR      : $ACR_NAME ($ACR_ID)"
Log "  Subnet   : $AKS_SUBNET_NAME ($AKS_SUBNET_CIDR)"
Log "  Network  : Azure CNI + Calico"
Log ""
Log "Quick test:"
Log "  kubectl get nodes"
Log "  kubectl get pods -A"
