# ---------------------------------------------------------------
# AKS Cluster with Node Auto Provisioning (NAP)
# CNI Overlay | Standard Load Balancer outbound
# ---------------------------------------------------------------

$YOUR_INITIALS = "vk"
$INITIALS      = "$($YOUR_INITIALS)".ToLower()
$RESOURCE_GROUP = "azure-$($INITIALS)-rg"
$LOCATION       = "uaenorth"

# Reuse existing ACR (created by AKS-pvt-cilium-withnap.ps1)
$ACR_NAME = "acrvk012826"
$ACR_ID   = $(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
Write-Host "ACR ID: $ACR_ID"

# Managed Identities for the new cluster
$AKS_IDENTITY     = "aks-identity-nap-$($INITIALS)"
$KUBELET_IDENTITY = "kubelet-identity-nap-$($INITIALS)"

$AKS_IDENTITY_ID     = $(az identity create --name $AKS_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
$KUBELET_IDENTITY_ID = $(az identity create --name $KUBELET_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)

Write-Host "AKS Identity ID:     $AKS_IDENTITY_ID"
Write-Host "Kubelet Identity ID: $KUBELET_IDENTITY_ID"

# Reuse existing Log Analytics Workspace
$LOG_ANALYTICS_WORKSPACE_NAME = "aks-$($INITIALS)-law"
$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID = $(az monitor log-analytics workspace show `
    --resource-group $RESOURCE_GROUP `
    --workspace-name $LOG_ANALYTICS_WORKSPACE_NAME `
    --query id -o tsv)
Write-Host "Log Analytics Workspace ID: $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID"

# Virtual Network for the NAP cluster (separate VNET to avoid overlap)
$VNET_NAME   = "aks-$($INITIALS)-nap-vnet"
$SUBNET_NAME = "aks-nap-subnet"

az network vnet create `
    --resource-group $RESOURCE_GROUP `
    --name $VNET_NAME `
    --address-prefixes 10.1.0.0/16 `
    --subnet-name $SUBNET_NAME `
    --subnet-prefix 10.1.0.0/20

$SUBNET_ID = $(az network vnet subnet show `
    --resource-group $RESOURCE_GROUP `
    --vnet-name $VNET_NAME `
    --name $SUBNET_NAME `
    --query id -o tsv)
Write-Host "Subnet ID: $SUBNET_ID"

# AKS Cluster Name
$AKS_NAME = "aks-with-nap"
Write-Host "AKS Cluster Name: $AKS_NAME"

# Create AKS Cluster with Node Auto Provisioning (NAP)
# - node-provisioning-mode Auto  => enables NAP (Karpenter-based)
# - network-plugin azure + network-plugin-mode overlay => CNI Overlay
# - outbound-type loadBalancer   => Standard Load Balancer (default, made explicit)
# - node-count 1 on system pool  => minimum footprint; NAP scales workload nodes
az aks create `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --location $LOCATION `
    --generate-ssh-keys `
    --enable-managed-identity `
    --assign-identity $AKS_IDENTITY_ID `
    --assign-kubelet-identity $KUBELET_IDENTITY_ID `
    --attach-acr $ACR_ID `
    --node-count 1 `
    --nodepool-name system1 `
    --node-vm-size Standard_D2as_v5 `
    --network-plugin azure `
    --network-plugin-mode overlay `
    --pod-cidr 192.168.0.0/16 `
    --service-cidr 172.16.0.0/16 `
    --dns-service-ip 172.16.0.10 `
    --vnet-subnet-id $SUBNET_ID `
    --outbound-type loadBalancer `
    --node-provisioning-mode Auto `
    --enable-addons monitoring `
    --workspace-resource-id $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID `
    --enable-ahub
Write-Host "AKS cluster '$AKS_NAME' created with NAP enabled."

# Add User Node Pool
# Note: --enable-cluster-autoscaler must NOT be used when NAP (node-provisioning-mode Auto) is enabled
az aks nodepool add `
    --resource-group $RESOURCE_GROUP `
    --cluster-name $AKS_NAME `
    --os-type Linux `
    --name linux1 `
    --node-count 1 `
    --mode User `
    --node-vm-size Standard_D2as_v5 `
    --ssh-access disabled
Write-Host "User node pool 'linux1' added."

# Get credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing
Write-Host "kubeconfig updated for cluster: $AKS_NAME"

# Verify NAP / node provisioning status
az aks show `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --query "nodeProvisioningProfile" -o json

# ---------------------------------------------------------------
# Deploy sample Azure Voting App to the 'app' namespace
# ---------------------------------------------------------------

# Create namespace
kubectl create namespace app

# Deploy Azure Voting App (redis backend + voting frontend)
kubectl apply -n app -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-back
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-back
  template:
    metadata:
      labels:
        app: azure-vote-back
    spec:
      containers:
      - name: azure-vote-back
        image: mcr.microsoft.com/oss/bitnami/redis:6.0.8
        env:
        - name: ALLOW_EMPTY_PASSWORD
          value: "yes"
        ports:
        - containerPort: 6379
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-back
spec:
  selector:
    app: azure-vote-back
  ports:
  - port: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-front
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-front
  template:
    metadata:
      labels:
        app: azure-vote-front
    spec:
      containers:
      - name: azure-vote-front
        image: mcr.microsoft.com/azuredocs/azure-vote-front:v1
        ports:
        - containerPort: 80
        env:
        - name: REDIS
          value: azure-vote-back
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-front
spec:
  type: LoadBalancer
  selector:
    app: azure-vote-front
  ports:
  - port: 80
    targetPort: 80
EOF

Write-Host "Sample app deployed. Waiting for external IP..."
kubectl get svc azure-vote-front -n app --watch
