$YOUR_INITIALS="vk"
$INITIALS="$($YOUR_INITIALS)".ToLower()
$RESOURCE_GROUP="azure-$($INITIALS)-rg"
$LOCATION="uaenorth"
$AKS_IDENTITY="aks-identity-$($INITIALS)"
$KUBELET_IDENTITY="kubelet-identity-$($INITIALS)"

$VM_SKU="Standard_D2as_v5"

# Create Resource Group
az group create --location $LOCATION --resource-group $RESOURCE_GROUP

# Define AKS Cluster Name
$AKS_NAME="aks-$($INITIALS)-with-cilium"
Write-Host "AKS Cluster Name: $AKS_NAME"

# Create User Assigned Managed Identities
$AKS_IDENTITY_ID=$(az identity create --name $AKS_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)
$KUBELET_IDENTITY_ID=$(az identity create --name $KUBELET_IDENTITY --resource-group $RESOURCE_GROUP --query id -o tsv)

# Output the Managed Identity IDs
Write-Host "AKS Identity ID: $AKS_IDENTITY_ID"
Write-Host "Kubelet Identity ID: $KUBELET_IDENTITY_ID"

# Create Log Analytics Workspace
$LOG_ANALYTICS_WORKSPACE_NAME="aks-$($INITIALS)-law"
$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace create --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_WORKSPACE_NAME --query id -o tsv)

# Output the Log Analytics Workspace Resource ID
Write-Host "Log Analytics Workspace Resource ID: 
$LOG_ANALYTICS_WORKSPACE_RESOURCE_ID"

# Define ACR Name
$SUFFIX=(Get-Date -Format "MMddyy")
$ACR_NAME="acr$($INITIALS)$($SUFFIX)"
Write-Host "ACR Name: $ACR_NAME"

$ACR_ID=$(az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard --workspace $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID --query id -o tsv)
Write-Host "ACR ID: $ACR_ID"

# Create AKS Cluster with Cilium Networking
# Create Virtual Network and Subnet for AKS
$VNET_NAME="aks-$($INITIALS)-vnet"
$SUBNET_NAME="aks-subnet"
az network vnet create --resource-group $RESOURCE_GROUP `
                       --name $VNET_NAME `
                       --address-prefixes 10.0.0.0/16 `
                       --subnet-name $SUBNET_NAME `
                       --subnet-prefix 10.0.0.0/20

$SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name $SUBNET_NAME --query id -o tsv)
Write-Host "SUBNET ID: $SUBNET_ID"



# az aks create --resource-group $RESOURCE_GROUP `
#               --name $AKS_NAME `
#               --generate-ssh-keys `
#               --enable-managed-identity `
#               --assign-identity $AKS_IDENTITY_ID `
#               --assign-kubelet-identity $KUBELET_IDENTITY_ID `
#               --attach-acr $ACR_ID `
#               --node-count 1 `
#               --enable-cluster-autoscaler `
#               --min-count 1 `
#               --max-count 3 `
#               --network-plugin azure `
#               --network-plugin-mode overlay `
#               --network-dataplane cilium `
#               --pod-cidr 192.168.0.0/16 `
#               --service-cidr 172.16.0.0/16 `
#               --vnet-subnet-id $SUBNET_ID `
#               --node-vm-size $VM_SKU `
#               --nodepool-name system1 `
#               --enable-addons monitoring `
#               --workspace-resource-id $LOG_ANALYTICS_WORKSPACE_RESOURCE_ID `
#               --zones 1 2 3 `
#               --enable-ahub
# Write-Host "AKS Created..."              


# Add User Node Pool
# az aks nodepool add --resource-group $RESOURCE_GROUP `
#                     --cluster-name $AKS_NAME `
#                     --os-type Linux `
#                     --name linux1 `
#                     --node-count 1 `
#                     --enable-cluster-autoscaler `
#                     --min-count 1 `
#                     --max-count 3 `
#                     --mode User `
#                     --zones 1 2 3 `
#                     --node-vm-size $VM_SKU

# create nginx ingress 
$REGISTRY_NAME="acrvk012826"
$CONTROLLER_IMAGE="ingress-nginx/controller"
$CONTROLLER_TAG="v1.11.3"
$PATCH_IMAGE="ingress-nginx/kube-webhook-certgen"
$PATCH_TAG="v1.4.4"
$DEFAULTBACKEND_IMAGE="defaultbackend-amd64"
$DEFAULTBACKEND_TAG="1.5"

# Import from official registries
az acr import --name $REGISTRY_NAME --source "registry.k8s.io/$CONTROLLER_IMAGE`:$CONTROLLER_TAG" --image "$CONTROLLER_IMAGE`:$CONTROLLER_TAG"
az acr import --name $REGISTRY_NAME --source "registry.k8s.io/$PATCH_IMAGE`:$PATCH_TAG" --image "$PATCH_IMAGE`:$PATCH_TAG"
az acr import --name $REGISTRY_NAME --source "registry.k8s.io/$DEFAULTBACKEND_IMAGE`:$DEFAULTBACKEND_TAG" --image "$DEFAULTBACKEND_IMAGE`:$DEFAULTBACKEND_TAG"

# Add the ingress-nginx repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Set variable for ACR location to use for pulling images
ACR_URL=<REGISTRY_URL>

# Use Helm to deploy an NGINX ingress controller
helm install nginx-ingress ingress-nginx/ingress-nginx `
    --namespace ingress-basic --create-namespace `
    --set controller.replicaCount=2 `
    --set controller.nodeSelector."kubernetes\.io/os"=linux `
    --set controller.image.registry=$AcrUrl `
    --set controller.image.image=$ControllerImage `
    --set controller.image.tag=$ControllerTag `
    --set controller.image.digest="" `
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux `
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz `
    --set controller.admissionWebhooks.patch.image.registry=$AcrUrl `
    --set controller.admissionWebhooks.patch.image.image=$PatchImage `
    --set controller.admissionWebhooks.patch.image.tag=$PatchTag `
    --set controller.admissionWebhooks.patch.image.digest="" `
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux `
    --set defaultBackend.image.registry=$AcrUrl `
    --set defaultBackend.image.image=$DefaultBackendImage `
    --set defaultBackend.image.repository=$DefaultBackendRegistry/$DefaultBackendImage `
    --set defaultBackend.image.tag=$DefaultBackendTag `
    --set defaultBackend.image.digest=""