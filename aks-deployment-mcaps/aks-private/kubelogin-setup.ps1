## ============================================================
## kubelogin-setup.ps1
##   1. Enables Azure AD + Azure RBAC on AKS cluster
##   2. Grants jumpbox managed identity → Cluster Admin
##   3. Creates read-only service principal → RBAC Reader
##   Run from: PowerShell (local machine or jumpbox with az cli)
## ============================================================

## ============================================================
## Variables
## ============================================================
$RESOURCE_GROUP         = "pvt-aks-rg"
$AKS_NAME               = "pvt-aks-cluster"

## Jumpbox managed identity object ID (system-assigned)
## Get with: az vm show --resource-group pvt-aks-rg --name jumpbox-vm --query identity.principalId -o tsv
$JUMPBOX_IDENTITY_OID   = "6a2252a6-14af-426f-826e-3159bd17395c"

## Service principal to create for read-only access
$SP_NAME                = "pvt-aks-readonly-sp"

## ============================================================
## Step 1 – Enable Azure AD integration + Azure RBAC on cluster
##   Required before any Azure RBAC role assignments take effect
## ============================================================
Write-Host "Step 1 – Enabling Azure AD + Azure RBAC on $AKS_NAME..."

az aks update `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --enable-aad `
    --enable-azure-rbac

## Verify
az aks show `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --query "{aadManaged: aadProfile.managed, azureRbac: aadProfile.enableAzureRbac}" `
    --output json

## ============================================================
## Step 2 – Get AKS cluster resource ID
## ============================================================
$AKS_ID = $(az aks show `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --query id --output tsv)

Write-Host "AKS ID: $AKS_ID"

## ============================================================
## Step 3 – Grant jumpbox managed identity → Cluster Admin
##   "Azure Kubernetes Service RBAC Cluster Admin" = full k8s API access
##   Only works when enableAzureRbac = true (Step 1)
## ============================================================
Write-Host "Step 3 – Assigning Cluster Admin to jumpbox identity ($JUMPBOX_IDENTITY_OID)..."

az role assignment create `
    --assignee $JUMPBOX_IDENTITY_OID `
    --role "Azure Kubernetes Service RBAC Cluster Admin" `
    --scope $AKS_ID

Write-Host "Done. Jumpbox identity has Cluster Admin on $AKS_NAME"

## ============================================================
## Step 4 – Create read-only service principal
## ============================================================
Write-Host "Step 4 – Creating read-only service principal '$SP_NAME'..."

## Credential end-date: 1 month from today – adjust if tenant policy requires shorter
$SP_END_DATE = (Get-Date).AddMonths(1).ToString("yyyy-MM-dd")

## Check if SP already exists (idempotent – safe to re-run)
$SP_CLIENT_ID = $(az ad sp list --display-name $SP_NAME --query "[0].appId" --output tsv)

if (-not $SP_CLIENT_ID) {
    Write-Host "Creating new service principal '$SP_NAME'..."
    ## Create app registration only (no role assignment, no default credentials)
    $APP_ID = $(az ad app create --display-name $SP_NAME --query appId --output tsv)
    ## Create the SP from the app registration
    az ad sp create --id $APP_ID | Out-Null
    $SP_CLIENT_ID = $APP_ID
    Write-Host "Service principal created. App/Client ID: $SP_CLIENT_ID"
} else {
    Write-Host "Service principal '$SP_NAME' already exists. Client ID: $SP_CLIENT_ID"
}

$SP_TENANT_ID = $(az account show --query tenantId --output tsv)

## Reset credentials with explicit end-date to satisfy tenant credential lifetime policy
Write-Host "Resetting credentials with end-date $SP_END_DATE..."
$SP_CRED_JSON = $(az ad app credential reset --id $SP_CLIENT_ID --end-date $SP_END_DATE --output json) | ConvertFrom-Json
$SP_CLIENT_SECRET = $SP_CRED_JSON.password

## Get the SP object ID (needed for RBAC – NOT the appId)
$SP_OBJECT_ID = $(az ad sp show --id $SP_CLIENT_ID --query id --output tsv)

Write-Host "SP Client ID  : $SP_CLIENT_ID"
Write-Host "SP Object ID  : $SP_OBJECT_ID"
Write-Host "SP Tenant ID  : $SP_TENANT_ID"

## ============================================================
## Step 5 – Assign read-only Azure RBAC role to service principal
##   "Azure Kubernetes Service RBAC Reader" maps to k8s 'view' ClusterRole.
##   NOTE: The 'view' ClusterRole excludes cluster-scoped resources like nodes.
##   kubectl get nodes access is granted in Step 5b via a Kubernetes ClusterRoleBinding.
## ============================================================
Write-Host "Step 5 – Assigning RBAC Reader to service principal ($SP_OBJECT_ID)..."

az role assignment create `
    --assignee $SP_OBJECT_ID `
    --role "Azure Kubernetes Service RBAC Reader" `
    --scope $AKS_ID

Write-Host "Done. Service principal has Reader access on $AKS_NAME"

## ============================================================
## Step 5b – Grant node read access via Kubernetes ClusterRoleBinding
##   Azure RBAC 'RBAC Reader' maps to k8s 'view' which excludes nodes.
##   This creates a ClusterRoleBinding so 'kubectl get nodes' works.
##   Requires kubeconfig already set up with admin access (run after Step 6).
## ============================================================
Write-Host "Step 5b – Creating ClusterRoleBinding for node read access..."

## Get the SP's AAD object ID for the k8s subject
@"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: readonly-sp-node-reader
subjects:
- kind: User
  name: "$SP_OBJECT_ID"
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-reader
  apiGroup: rbac.authorization.k8s.io
"@ | kubectl apply -f -

Write-Host "Done. SP can now run 'kubectl get nodes'"

## ============================================================
## Step 6 – Get kubeconfig in exec format (required for kubelogin)
##   --format exec ensures no embedded credentials – kubelogin is invoked
## ============================================================
Write-Host "Step 6 – Fetching kubeconfig in exec format..."

az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing --format exec

## ============================================================
## Step 7 – Configure kubelogin for JUMPBOX (MSI auth)
##   Run this on the jumpbox after az login --identity
## ============================================================
Write-Host ""
Write-Host "============================================================"
Write-Host " On the JUMPBOX – run these commands (MSI / admin access):"
Write-Host "============================================================"
Write-Host @"
  az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing --format exec
  kubelogin convert-kubeconfig -l msi
  kubectl get nodes          # should succeed – Cluster Admin
  kubectl get pods -A        # should succeed
"@

## ============================================================
## Step 8 – Configure kubelogin for SERVICE PRINCIPAL (read-only)
##   Run from any machine with the SP credentials
## ============================================================
Write-Host ""
Write-Host "============================================================"
Write-Host " For SERVICE PRINCIPAL read-only access – run these:"
Write-Host "============================================================"
Write-Host @"
  az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing --format exec
  kubelogin convert-kubeconfig -l spn --client-id $SP_CLIENT_ID --client-secret '<secret>' --tenant-id $SP_TENANT_ID
  ## kubelogin convert-kubeconfig -l spn --client-id <> --client-secret '<>' --tenant-id <>
  kubectl get pods -A        # should succeed – Cluster Reader
  kubectl get nodes          # should succeed – Cluster Reader
  kubectl delete pod <name>  # should FAIL – Forbidden (read-only)
"@

## ============================================================
## Step 8b – AAD USER access via 'az aks command invoke' (LOCAL MACHINE)
##
##   Problem:  az login blocked on VM by org policy
##             Private cluster API server not reachable from local machine
##   Solution: az aks command invoke proxies kubectl through Azure Resource
##             Manager – runs on your LOCAL machine using your az login session.
##             No direct API server access or VM login required.
##
##   Run from: LOCAL MACHINE (where az login works)
## ============================================================
$USER_OBJECT_ID = "906db933-cfb9-4907-bdbc-879d6959021b"   # vinaykumar AAD object ID

Write-Host ""
Write-Host "============================================================"
Write-Host " For AAD USER access – run from LOCAL MACHINE:"
Write-Host "============================================================"
Write-Host @"
  # Pre-req: logged in locally as your AAD user
  az login

  # Run any kubectl command via ARM proxy – no VPN / no jumpbox needed
  az aks command invoke `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --command "kubectl get pods -A"

  az aks command invoke `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --command "kubectl get nodes"     # FAILS – Forbidden (no node access)

  az aks command invoke `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_NAME `
    --command "kubectl delete pod <name> -n <ns>"  # FAILS – Forbidden (read-only)

  # NOTE: 'az aks command invoke' runs as the identity used in 'az login'
  # Your AAD user object ID: $USER_OBJECT_ID
  # Apply pod-list access first: bash user-pod-lister-rbac.sh  (on jumpbox with admin kubeconfig)
"@

## ============================================================
## Step 9 – Save SP credentials to a file (keep secure!)
## ============================================================
$SP_CREDS_FILE = "$PSScriptRoot\sp-readonly-creds.json"
@{
    spName       = $SP_NAME
    clientId     = $SP_CLIENT_ID
    clientSecret = $SP_CLIENT_SECRET
    tenantId     = $SP_TENANT_ID
    objectId     = $SP_OBJECT_ID
    role         = "Azure Kubernetes Service RBAC Reader"
    scope        = $AKS_ID
} | ConvertTo-Json | Out-File -FilePath $SP_CREDS_FILE -Encoding utf8

Write-Host ""
Write-Host "============================================================"
Write-Host " Setup Complete"
Write-Host "============================================================"
Write-Host " Jumpbox identity : Cluster Admin  (MSI auth)"
Write-Host " Service principal: RBAC Reader    (SPN auth)"
Write-Host " SP credentials   : $SP_CREDS_FILE"
Write-Host "============================================================"
