# Kubelogin Authentication Guide for AKS

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- [kubelogin](https://github.com/Azure/kubelogin) installed
- An AKS cluster with **Azure AD (Entra ID) integration** and **Azure RBAC** enabled

---

## 1. Enable Azure AD & Azure RBAC on AKS Cluster

### Enable Azure AD Integration

```powershell
az aks update --resource-group <resource-group> --name <cluster-name> --enable-aad
```

### Enable Azure RBAC for Kubernetes Authorization

```powershell
az aks update --resource-group <resource-group> --name <cluster-name> --enable-azure-rbac
```

### Verify Configuration

```powershell
az aks show --resource-group <resource-group> --name <cluster-name> \
  --query "{aadProfile: aadProfile, enableRBAC: enableRbac, azureRBACEnabled: aadProfile.enableAzureRbac}" -o json
```

Expected output should show:
- `managed: true` — Azure AD integration is enabled
- `enableAzureRbac: true` — Azure RBAC for Kubernetes is enabled
- `enableRBAC: true` — Kubernetes RBAC is enabled

---

## 2. Get Kubeconfig in Exec Format

> **Important**: Use `--format exec` to get a kubeconfig that uses the `exec` credential plugin instead of embedded certificates/tokens. Without this flag, kubelogin has no effect because kubectl always prefers embedded credentials.

```powershell
az aks get-credentials --resource-group <resource-group> --name <cluster-name> --overwrite-existing --format exec
```

### Verify the Kubeconfig

```powershell
Get-Content "$env:USERPROFILE\.kube\config"
```

The `users` section should contain an `exec` block (not `client-certificate-data` or `token`):

```yaml
users:
- name: clusterUser_<resource-group>_<cluster-name>
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - get-token
      - --login
      - azurecli
      - --server-id
      - 6dae42f8-4368-4678-94ff-3960e28e3630
      command: kubelogin
```

---

## 3. Authentication Method: Azure CLI

This method uses your current `az login` session to authenticate with the cluster.

### Step 1: Login to Azure

```powershell
az login
```

### Step 2: Get Kubeconfig

```powershell
az aks get-credentials --resource-group <resource-group> --name <cluster-name> --overwrite-existing --format exec
```

### Step 3: Convert Kubeconfig to Use Azure CLI Auth

```powershell
kubelogin convert-kubeconfig -l azurecli
```

### Step 4: Assign Azure RBAC Role

```powershell
# Get your user Object ID
az ad signed-in-user show --query id -o tsv

# Assign Cluster Admin role
az role assignment create \
  --assignee <your-object-id> \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope $(az aks show --resource-group <resource-group> --name <cluster-name> --query id -o tsv)
```

### Step 5: Verify Access

```powershell
kubectl get nodes
kubectl get pods -A
```

---

## 4. Authentication Method: Service Principal (SPN)

This method uses a service principal with client ID and secret to authenticate.

### Step 1: Create a Service Principal

```powershell
# Create the app registration and generate credentials (adjust --end-date per your tenant policy)
az ad app credential reset --id <app-id> --end-date "2026-03-01" -o json

# Or create a new app + SP
az ad sp create-for-rbac --name "aks-pod-reader" -o json
```

Save the output:
```json
{
  "appId": "<client-id>",
  "password": "<client-secret>",
  "tenant": "<tenant-id>"
}
```

### Step 2: Ensure Service Principal Exists

```powershell
# If SP doesn't exist yet, create it from the app registration
az ad sp create --id <app-id>

# Get the SP Object ID (needed for RBAC bindings)
az ad sp show --id <app-id> --query id -o tsv
```

### Step 3: Create Kubernetes RBAC (Pod Read-Only Example)

```yaml
# pod-reader-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pod-reader-binding
subjects:
- kind: User
  name: "<service-principal-object-id>"   # Use the SP's Object ID (not appId)
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Apply it (as a cluster admin):

```powershell
kubectl apply -f pod-reader-rbac.yaml
```

### Step 4: Convert Kubeconfig to Use SPN Auth

```powershell
kubelogin convert-kubeconfig -l spn \
  --client-id <client-id> \
  --client-secret <client-secret> \
  --tenant-id <tenant-id>
```

### Step 5: Verify Access

```powershell
# Should SUCCEED — pods are allowed
kubectl get pods -A

# Should FAIL (Forbidden) — nodes are not allowed
kubectl get nodes

# Should FAIL (Forbidden) — services are not allowed
kubectl get svc -A
```

---

## 5. Switch Between Auth Methods

### Switch to Azure CLI Auth

```powershell
kubelogin convert-kubeconfig -l azurecli
```

### Switch to SPN Auth

```powershell
kubelogin convert-kubeconfig -l spn \
  --client-id <client-id> \
  --client-secret <client-secret> \
  --tenant-id <tenant-id>
```

### Reset to Default (Re-fetch Kubeconfig)

```powershell
az aks get-credentials --resource-group <resource-group> --name <cluster-name> --overwrite-existing --format exec
kubelogin convert-kubeconfig -l azurecli
```

---

## 6. Common Issues & Troubleshooting

### Issue: `kubelogin convert-kubeconfig` has no effect

**Cause**: Kubeconfig has embedded `client-certificate-data`, `client-key-data`, or `token`. kubectl uses these before the exec plugin.

**Fix**: Re-fetch with `--format exec`:
```powershell
az aks get-credentials --resource-group <resource-group> --name <cluster-name> --overwrite-existing --format exec
```

### Issue: `Forbidden` error after Azure AD is enabled

**Cause**: Azure AD identity has no Kubernetes RBAC permissions. Being an Azure **Owner** does NOT grant Kubernetes API access.

**Fix**: Assign an AKS RBAC role:
```powershell
az role assignment create \
  --assignee <object-id> \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope $(az aks show -g <resource-group> -n <cluster-name> --query id -o tsv)
```

> **Note**: The `Azure Kubernetes Service RBAC *` roles only work when `enableAzureRbac` is `true` on the cluster.

### Issue: `--tenant-id is required` with SPN login

**Cause**: SPN auth requires explicit tenant ID.

**Fix**: Add `--tenant-id`:
```powershell
kubelogin convert-kubeconfig -l spn \
  --client-id <client-id> \
  --client-secret <client-secret> \
  --tenant-id <tenant-id>
```

---

## 7. Available Azure RBAC Roles for AKS

| Role | Access Level |
|------|-------------|
| `Azure Kubernetes Service RBAC Cluster Admin` | Full admin access to all resources |
| `Azure Kubernetes Service RBAC Admin` | Admin access (except modifying RBAC) |
| `Azure Kubernetes Service RBAC Writer` | Read/write to most resources |
| `Azure Kubernetes Service RBAC Reader` | Read-only access to most resources |

---

## 8. kubectl Auth Credential Precedence

kubectl evaluates credentials in this order:

1. **`client-certificate-data` + `client-key-data`** — used first if present
2. **`token`** — used next if present
3. **`exec` plugin** — used only if no embedded credentials exist
4. **`auth-provider`** — legacy method (deprecated)

This is why `--format exec` is critical — it ensures no embedded credentials are present so the exec plugin (kubelogin) is actually invoked.

---

## Reference Commands Used in This Guide

```powershell
# Cluster details
az aks show -g azure-vk-rg -n aks-vk-with-cilium --query "{aadProfile: aadProfile, enableRBAC: enableRbac}" -o json

# Current user
az ad signed-in-user show --query "{displayName: displayName, id: id}" -o json

# View kubeconfig
Get-Content "$env:USERPROFILE\.kube\config"
kubectl config view --minify
```
