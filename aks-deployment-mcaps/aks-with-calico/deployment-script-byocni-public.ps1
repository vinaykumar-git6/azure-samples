# ======================================================================
# PUBLIC AKS Cluster with BYOCNI (Bring Your Own CNI)
# No CNI plugin installed by default — Calico installed via Helm post-creation
# ======================================================================

# Common Parameters
$YOUR_INITIALS = "digitaltwins"
$INITIALS = "$($YOUR_INITIALS)".ToLower()
$RESOURCE_GROUP = "dewa-rg"
$LOCATION = "uaenorth"

# Identity Parameters
$AKS_IDENTITY = "aks-identity-byocni-$($INITIALS)"
$KUBELET_IDENTITY = "kubelet-identity-byocni-$($INITIALS)"

# VM & Cluster Parameters
$VM_SKU = "Standard_D2as_v5"
$AKS_NAME = "aks-$($INITIALS)-byocni-public"
$SYSTEM_NODEPOOL_NAME = "system1"
$USER_NODEPOOL_NAME = "userpool1"
$NODE_COUNT = 1
$MIN_COUNT = 1
$MAX_COUNT = 3

# Network Parameters (no pod-cidr — Calico CNI will define it)
$SERVICE_CIDR = "172.18.0.0/16"
$DNS_SERVICE_IP = "172.18.0.10"
$SUBNET_ID = "/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourceGroups/dewa-rg/providers/Microsoft.Network/virtualNetworks/aks-vnet/subnets/node-snet"

# Calico Helm Parameters
$CALICO_VERSION = "3.29.2"
$CALICO_NAMESPACE = "calico-system"
$POD_CIDR = "192.168.0.0/16"

# Monitoring Parameters
$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID = "/subscriptions/86339c66-ee25-474d-b5bb-b334aad19c32/resourcegroups/innovationhub/providers/microsoft.operationalinsights/workspaces/redis-law"

# ACR Parameters
$SUFFIX = (Get-Date -Format "MMddyy")
$ACR_NAME = "acrbyocni$($INITIALS)$($SUFFIX)"

Write-Host "============================================="
Write-Host "Public AKS Cluster (BYOCNI) + Calico via Helm"
Write-Host "============================================="
Write-Host "AKS Cluster Name: $AKS_NAME"

# -----------------------------------------------
# Create User Assigned Managed Identities
# -----------------------------------------------
$AKS_IDENTITY_ID = $(az identity create --name $AKS_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
$KUBELET_IDENTITY_ID = $(az identity create --name $KUBELET_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
Write-Host "AKS Identity ID: $AKS_IDENTITY_ID"
Write-Host "Kubelet Identity ID: $KUBELET_IDENTITY_ID"

# -----------------------------------------------
# Create ACR
# -----------------------------------------------
$ACR_ID = $(az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard --workspace $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID --query id -o tsv)
Write-Host "ACR Name: $ACR_NAME"
Write-Host "ACR ID: $ACR_ID"

# -----------------------------------------------
# Create Public AKS Cluster with BYOCNI (--network-plugin none)
# -----------------------------------------------
Write-Host "`nCreating Public AKS Cluster with BYOCNI..."
Write-Host "SUBNET ID: $SUBNET_ID"

az aks create --resource-group $RESOURCE_GROUP `
              --name $AKS_NAME `
              --location $LOCATION `
              --generate-ssh-keys `
              --enable-managed-identity `
              --assign-identity $AKS_IDENTITY_ID `
              --assign-kubelet-identity $KUBELET_IDENTITY_ID `
              --attach-acr $ACR_ID `
              --node-count $NODE_COUNT `
              --enable-cluster-autoscaler `
              --min-count $MIN_COUNT `
              --max-count $MAX_COUNT `
              --network-plugin none `
              --service-cidr $SERVICE_CIDR `
              --dns-service-ip $DNS_SERVICE_IP `
              --vnet-subnet-id $SUBNET_ID `
              --node-vm-size $VM_SKU `
              --nodepool-name $SYSTEM_NODEPOOL_NAME `
              --enable-addons monitoring `
              --workspace-resource-id $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID `
              --zones 1 2 3

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: AKS cluster creation failed. Exiting." -ForegroundColor Red
    exit 1
}
Write-Host "Public AKS Cluster (BYOCNI) '$AKS_NAME' Created..."

# -----------------------------------------------
# Add User Node Pool
# -----------------------------------------------
Write-Host "`nAdding User Node Pool '$USER_NODEPOOL_NAME'..."

az aks nodepool add --resource-group $RESOURCE_GROUP `
                    --cluster-name $AKS_NAME `
                    --os-type Linux `
                    --name $USER_NODEPOOL_NAME `
                    --node-count $NODE_COUNT `
                    --enable-cluster-autoscaler `
                    --min-count $MIN_COUNT `
                    --max-count $MAX_COUNT `
                    --mode User `
                    --zones 1 2 3 `
                    --node-vm-size $VM_SKU

Write-Host "User Node Pool '$USER_NODEPOOL_NAME' added."

# -----------------------------------------------
# Get Credentials
# -----------------------------------------------
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing
Write-Host "Credentials configured for '$AKS_NAME'"

# -----------------------------------------------
# Verify nodes are NotReady (expected before CNI)
# -----------------------------------------------
Write-Host "`n============================================="
Write-Host "Nodes should be NotReady - installing Calico CNI via Helm..."
Write-Host "============================================="
kubectl get nodes -o wide

# -----------------------------------------------
# Install Calico CNI via Helm
# -----------------------------------------------

# Step 1: Create the Tigera operator namespace
kubectl create namespace tigera-operator --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Add the Calico Helm repo
helm repo add projectcalico https://docs.tigera.io/calico/charts
helm repo update

# Step 3: Install Calico using the Tigera operator Helm chart
helm install calico projectcalico/tigera-operator `
    --version "v3.29.2" `
    --namespace tigera-operator `
    --set installation.kubernetesProvider=AKS `
    --set installation.cni.type=Calico `
    --set installation.calicoNetwork.bgp=Disabled `
    --set "installation.calicoNetwork.ipPools[0].cidr=192.168.0.0/16" `
    --set "installation.calicoNetwork.ipPools[0].encapsulation=VXLAN" `
    --wait --timeout 10m

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Calico Helm installation failed." -ForegroundColor Red
    exit 1
}
Write-Host "Calico CNI installed via Helm (version $CALICO_VERSION)"

# -----------------------------------------------
# Wait for Calico pods to be ready
# -----------------------------------------------
Write-Host "Waiting for Calico system pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=300s
kubectl wait --for=condition=Ready pods --all -n tigera-operator --timeout=300s

# -----------------------------------------------
# Verify nodes are now Ready
# -----------------------------------------------
Write-Host "`n============================================="
Write-Host "Post-CNI Installation Verification"
Write-Host "============================================="

Write-Host "`n--- Node Status ---"
kubectl get nodes -o wide

Write-Host "`n--- Calico System Pods ---"
kubectl get pods -n calico-system -o wide

Write-Host "`n--- Tigera Operator Pods ---"
kubectl get pods -n tigera-operator -o wide

Write-Host "`n--- Calico Installation Status ---"
kubectl get installation default -o jsonpath='{.status.conditions}' | ConvertFrom-Json | Format-Table

Write-Host "`n============================================="
Write-Host "Deployment Complete!"
Write-Host "Cluster: $AKS_NAME - Public, BYOCNI + Calico $CALICO_VERSION"
Write-Host "============================================="
