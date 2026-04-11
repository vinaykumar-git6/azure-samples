# Azure Container Registry (ACR) — Login, Push & Pull Commands

## Prerequisites

```powershell
# Install Azure CLI (if not already installed)
winget install Microsoft.AzureCLI

# Login to Azure
az login

# Set your subscription
az account set --subscription "<subscription-id>"
```

---

## Variables

```powershell
$ACR_NAME    = "acrvk012826"           # Your ACR name (without .azurecr.io)
$IMAGE_NAME  = "myapp"                 # Your image name
$IMAGE_TAG   = "v1.0.0"               # Your image tag
$ACR_LOGIN_SERVER = "$ACR_NAME.azurecr.io"
```

---

## 1. Login to ACR

### Using Azure CLI (recommended)
```powershell
az acr login --name $ACR_NAME
```

### Using Docker with ACR token (service principal or admin)
```powershell
# Get login server
az acr show --name $ACR_NAME --query loginServer -o tsv

# Login via docker (requires admin credentials)
$ACR_PASSWORD = $(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)
docker login $ACR_LOGIN_SERVER --username $ACR_NAME --password $ACR_PASSWORD
```

> **Note:** Admin credentials must be enabled: `az acr update --name $ACR_NAME --admin-enabled true`

---

## 2. Build & Push an Image

### Build locally and push
```powershell
# Build the image
docker build -t "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG" .

# Push to ACR
docker push "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"
```

### Build directly in ACR (no local Docker needed)
```powershell
az acr build `
    --registry $ACR_NAME `
    --image "$IMAGE_NAME`:$IMAGE_TAG" `
    .
```

### Tag an existing local image and push
```powershell
# Tag existing local image
docker tag "$IMAGE_NAME`:$IMAGE_TAG" "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"

# Push
docker push "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"
```

---

## 3. Pull an Image

```powershell
# Pull from ACR
docker pull "$ACR_LOGIN_SERVER/$IMAGE_NAME`:$IMAGE_TAG"
```

---

## 4. Import an Image from Public Registry into ACR

```powershell
# Import from Docker Hub
az acr import `
    --name $ACR_NAME `
    --source "docker.io/library/nginx:latest" `
    --image "nginx:latest"

# Import from Microsoft Container Registry (mcr.microsoft.com)
az acr import `
    --name $ACR_NAME `
    --source "mcr.microsoft.com/dotnet/aspnet:8.0" `
    --image "dotnet/aspnet:8.0"

# Import from GitHub Container Registry (ghcr.io)
az acr import `
    --name $ACR_NAME `
    --source "ghcr.io/owner/repo:tag" `
    --image "repo:tag"
```

---

## 5. List & Manage Images

```powershell
# List all repositories in ACR
az acr repository list --name $ACR_NAME -o table

# List tags for a specific repository
az acr repository show-tags --name $ACR_NAME --repository $IMAGE_NAME -o table

# Show image details (digest, size, last update)
az acr repository show --name $ACR_NAME --image "$IMAGE_NAME`:$IMAGE_TAG"

# Delete a specific tag
az acr repository delete --name $ACR_NAME --image "$IMAGE_NAME`:$IMAGE_TAG" --yes

# Delete entire repository
az acr repository delete --name $ACR_NAME --repository $IMAGE_NAME --yes
```

---

## 6. Private ACR — Using with AKS

### Attach ACR to AKS (grants AcrPull role to kubelet identity)
```powershell
az aks update `
    --resource-group <resource-group> `
    --name <aks-cluster-name> `
    --attach-acr $ACR_NAME
```

### Verify the AcrPull role assignment
```powershell
$KUBELET_OBJECT_ID = $(az aks show `
    --resource-group <resource-group> `
    --name <aks-cluster-name> `
    --query identityProfile.kubeletidentity.objectId -o tsv)

az role assignment list `
    --assignee $KUBELET_OBJECT_ID `
    --scope $(az acr show --name $ACR_NAME --query id -o tsv) `
    -o table
```

---

## 7. Useful Diagnostics

```powershell
# Check ACR health
az acr check-health --name $ACR_NAME --ignore-errors

# Show ACR login server
az acr show --name $ACR_NAME --query loginServer -o tsv

# Show storage usage
az acr show-usage --name $ACR_NAME -o table

# Run a quick connectivity test
az acr run --registry $ACR_NAME --cmd "docker pull mcr.microsoft.com/hello-world" /dev/null
```

---

## 8. Enable KEDA (Kubernetes Event-Driven Autoscaling) in AKS

KEDA allows pods to autoscale based on external event sources (Service Bus, Event Hub, HTTP, Kafka, Redis, etc.) — beyond standard CPU/memory metrics.

### Option A — Enable at cluster creation time

```powershell
az aks create `
    --resource-group <resource-group> `
    --name <aks-cluster-name> `
    --enable-keda `
    # ... other flags
```

### Option B — Enable on an existing cluster

```powershell
az aks update `
    --resource-group <resource-group> `
    --name <aks-cluster-name> `
    --enable-keda
```

### Verify KEDA is running

```powershell
# Get credentials
az aks get-credentials --resource-group <resource-group> --name <aks-cluster-name>

# Check KEDA pods in kube-system
kubectl get pods -n kube-system -l app=keda-operator

# Check KEDA version / CRDs installed
kubectl get crd | Select-String "keda"
```

### Example — Scale on Azure Service Bus Queue

```yaml
# keda-servicebus-scaledobject.yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: azure-servicebus-auth
  namespace: default
spec:
  podIdentity:
    provider: azure-workload  # uses Workload Identity (recommended)
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: myapp-scaledobject
  namespace: default
spec:
  scaleTargetRef:
    name: myapp-deployment       # name of your Deployment
  minReplicaCount: 0             # scale to zero when idle
  maxReplicaCount: 10
  triggers:
  - type: azure-servicebus
    metadata:
      queueName: my-queue
      namespace: my-servicebus-namespace
      messageCount: "5"          # scale up when queue depth > 5
    authenticationRef:
      name: azure-servicebus-auth
```

```powershell
kubectl apply -f keda-servicebus-scaledobject.yaml

# Monitor scaling activity
kubectl get scaledobject
kubectl get hpa   # KEDA creates an HPA under the hood
```

### Example — Scale on Azure Event Hub

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: eventhub-scaledobject
  namespace: default
spec:
  scaleTargetRef:
    name: myapp-deployment
  minReplicaCount: 1
  maxReplicaCount: 20
  triggers:
  - type: azure-eventhub
    metadata:
      eventHubName: my-eventhub
      eventHubNamespace: my-eventhub-namespace
      consumerGroup: "$Default"
      unprocessedEventThreshold: "100"  # scale up per 100 unprocessed events
    authenticationRef:
      name: azure-eventhub-auth
```

### Disable KEDA

```powershell
az aks update `
    --resource-group <resource-group> `
    --name <aks-cluster-name> `
    --disable-keda
```
