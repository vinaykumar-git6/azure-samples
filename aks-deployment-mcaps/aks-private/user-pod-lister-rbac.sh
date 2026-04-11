#!/bin/bash
## ============================================================
## user-pod-lister-rbac.sh
## Grants ONLY 'kubectl get pods --all-namespaces' (list) to an AAD user.
## All other verbs (get, watch, delete, exec, logs, etc.) are denied.
##
## Prerequisites:
##   - kubectl configured with admin access (kubelogin -l msi or az aks get-credentials)
##   - kubelogin installed
##
## Get your AAD user object ID:
##   az ad signed-in-user show --query id -o tsv
## ============================================================

set -euo pipefail

USER_OBJECT_ID="906db933-cfb9-4907-bdbc-879d6959021b"  # vinaykumar AAD object ID

if [[ -z "$USER_OBJECT_ID" ]]; then
    echo "ERROR: USER_OBJECT_ID is not set."
    echo "Get it with: az ad signed-in-user show --query id -o tsv"
    exit 1
fi

echo "Applying pod-lister ClusterRole for user: $USER_OBJECT_ID"

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-lister
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list"]    # ONLY list – no get, watch, exec, delete, or any other verb
EOF

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: user-pod-lister
subjects:
- kind: User
  name: "${USER_OBJECT_ID}"   # AAD user object ID (not UPN)
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pod-lister
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Done. User '$USER_OBJECT_ID' can now run 'kubectl get pods -A' only."
echo "All other operations (get, watch, exec, delete, describe, logs, etc.) are denied."
echo ""
echo "To test, run from your local machine:"
echo "  az aks get-credentials --resource-group pvt-aks-rg --name pvt-aks-cluster --overwrite-existing --format exec"
echo "  kubelogin convert-kubeconfig -l azurecli"
echo "  kubectl get pods -A        # should succeed"
echo "  kubectl get nodes          # should fail – Forbidden"
echo "  kubectl logs <pod>         # should fail – Forbidden"
