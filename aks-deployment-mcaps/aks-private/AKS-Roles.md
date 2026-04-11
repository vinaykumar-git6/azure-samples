# AKS Role-Based Access Control – Reference Guide

## Overview

AKS has two layers of access control that work together:

| Layer | Controlled by | Purpose |
|-------|--------------|---------|
| **Azure Plane** | Azure RBAC (`az role assignment`) | Who can manage the cluster resource, download kubeconfig |
| **Kubernetes Plane** | Kubernetes RBAC (requires `--enable-azure-rbac`) | What kubectl operations are allowed inside the cluster |

---

## Azure Plane Roles

These roles control access to the **AKS cluster as an Azure resource**.

### Azure Kubernetes Service Cluster Admin Role
- Downloads **admin kubeconfig** using `az aks get-credentials --admin`
- Bypasses Azure AD and Kubernetes RBAC entirely — uses static local cluster-admin account
- **Use case**: Break-glass / emergency access only
- ⚠️ Not recommended for day-to-day use — no audit trail per user

### Azure Kubernetes Service Cluster User Role
- Allows running `az aks get-credentials` (without `--admin`)
- Downloads user kubeconfig bound to the caller's Azure AD identity
- Does **NOT** grant any kubectl permissions inside the cluster
- **Use case**: Required as a prerequisite alongside RBAC roles

### AKS Contributor
- Can modify the AKS cluster resource itself — scale, upgrade, add node pools, change settings
- No kubectl/Kubernetes access
- **Use case**: Platform/infra teams managing cluster lifecycle

### Azure Kubernetes Service Service Mesh Admin Role
- Manage Istio/OSM service mesh configuration
- **Use case**: Service mesh operators

---

## Kubernetes RBAC Roles (requires `--enable-azure-rbac` on cluster)

These roles control what **kubectl commands** the identity can run inside the cluster.

### Azure Kubernetes Service RBAC Cluster Admin
- Maps to Kubernetes `cluster-admin` ClusterRole
- **Full access** to all resources in all namespaces — `kubectl *` on everything
- Assigned at cluster scope = admin everywhere
- Assigned at namespace scope = admin within that namespace only
- **Use case**: Jumpbox VMs, CI/CD pipelines, cluster administrators

### Azure Kubernetes Service RBAC Admin
- Full read/write access within a **specific namespace**
- Can create/modify/delete RBAC roles and bindings within that namespace
- Cannot access other namespaces
- **Use case**: Team leads managing their own namespace

### Azure Kubernetes Service RBAC Writer
- Read + write access to most resources in a namespace
- Can deploy pods, services, configmaps, secrets
- **Cannot** modify RBAC roles/bindings
- **Use case**: Application deployment pipelines, developers

### Azure Kubernetes Service RBAC Reader
- Read-only access to resources in a namespace
- Cannot `kubectl exec`, cannot view secrets
- **Use case**: Monitoring tools, auditors, read-only developers

---

## Typical Role Combinations

### Jumpbox / Automation VM (Managed Identity)
```
Azure Kubernetes Service Cluster User Role     → download kubeconfig
Azure Kubernetes Service RBAC Cluster Admin    → full kubectl access
```

### Developer (namespace-scoped)
```
Azure Kubernetes Service Cluster User Role     → download kubeconfig
Azure Kubernetes Service RBAC Writer           → deploy/manage apps in their namespace
```

### Read-only auditor
```
Azure Kubernetes Service Cluster User Role     → download kubeconfig
Azure Kubernetes Service RBAC Reader           → read-only kubectl
```

### CI/CD Pipeline
```
Azure Kubernetes Service Cluster User Role     → download kubeconfig
Azure Kubernetes Service RBAC Writer           → deploy to specific namespace
```

---

## Role Assignment Commands

### Assign to a Managed Identity (MSI)
```powershell
$PRINCIPAL_ID = "<object-id-of-msi>"
$AKS_ID = $(az aks show --resource-group <rg> --name <cluster> --query id --output tsv)

# Prereq: download kubeconfig
az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Azure Kubernetes Service Cluster User Role" `
    --scope $AKS_ID

# Full kubectl access
az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Azure Kubernetes Service RBAC Cluster Admin" `
    --scope $AKS_ID
```

### Namespace-scoped assignment
```powershell
$NAMESPACE_SCOPE = "$AKS_ID/namespaces/<namespace-name>"

az role assignment create `
    --assignee $PRINCIPAL_ID `
    --role "Azure Kubernetes Service RBAC Writer" `
    --scope $NAMESPACE_SCOPE
```

---

## How it flows end-to-end (Managed Identity example)

```
Jumpbox VM (MSI)
    │
    ├─ az login --identity
    │       └─ authenticates using VM's system-assigned identity
    │
    ├─ az aks get-credentials           ← requires: Cluster User Role
    │       └─ downloads kubeconfig with AAD token
    │
    ├─ kubelogin convert-kubeconfig -l msi
    │       └─ converts kubeconfig to use MSI token for kubectl
    │
    └─ kubectl get nodes                ← requires: RBAC Cluster Admin
            └─ Azure AD validates token → checks RBAC assignment → allows
```

---

## Enabling AAD + Azure RBAC on an Existing Cluster

### Why Both `--enable-aad` AND `--enable-azure-rbac` Are Required

They serve two completely different purposes — **authentication** vs **authorization**:

```
WHO are you?        →  --enable-aad         (Authentication via Azure AD)
WHAT can you do?    →  --enable-azure-rbac  (Authorization via Azure Role Assignments)
```

| Flag | Purpose | Without it |
|------|---------|------------|
| `--enable-aad` | Verify identity via Azure Active Directory | Anyone with a kubeconfig can access — no AAD login required |
| `--enable-azure-rbac` | Check Azure role assignments for what you can do | Authorization falls back to k8s-native RBAC (ClusterRoles/RoleBindings) |

**You can have AAD without Azure RBAC:**
```
--enable-aad only:
  Login → AAD ✅  →  Authorized by k8s ClusterRoleBinding
```

**You cannot have Azure RBAC without AAD** — Azure RBAC needs AAD identities to assign roles to.

**Recommended (both together):**
```
--enable-aad + --enable-azure-rbac:
  Login → AAD ✅  →  Authorized by Azure Role Assignment ✅
```

### Command to Enable on Existing Cluster

```powershell
az aks update `
  --resource-group <resource-group> `
  --name <cluster-name> `
  --enable-aad `
  --enable-azure-rbac
```

> ⚠️ **Downtime impact**: API server restarts for ~2–5 minutes. Running pods/workloads are **not affected** — only the control plane restarts briefly.

### After Enabling — Assign Admin Access Immediately

After enabling, existing k8s ClusterRoleBindings **no longer apply for AAD users**. Assign Azure roles right away or users will get `Forbidden`:

```powershell
az role assignment create `
  --assignee <aad-user-or-group-object-id> `
  --role "Azure Kubernetes Service RBAC Cluster Admin" `
  --scope "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster>"
```

### Verify AAD + Azure RBAC is Enabled

```powershell
az aks show --resource-group <rg> --name <cluster> --query "aadProfile" -o json
# Expected output:
# {
#   "enableAzureRbac": true,
#   "managed": true,
#   "tenantId": "<your-tenant-id>",
#   "adminGroupObjectIDs": null,   ← assign Azure roles explicitly if null
#   ...
# }
```

---

## Key Notes

- **`--enable-aad`** enables Azure AD authentication — required before Azure RBAC can be used
- **`--enable-azure-rbac`** must be set on the cluster for Kubernetes RBAC roles to work
- **`--disable-local-accounts`** disables the static admin kubeconfig (recommended for production)
- Role propagation can take **1-2 minutes** after assignment before kubectl works
- Always assign **both** `Cluster User Role` + an RBAC role — one alone is not sufficient
- If `adminGroupObjectIDs` is `null`, you **must** assign Azure RBAC roles manually post-enablement
