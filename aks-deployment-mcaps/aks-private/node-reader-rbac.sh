#!/bin/bash
## ============================================================
## node-reader-rbac.sh
## Grants ONLY 'kubectl get pods --all-namespaces' (list) to a SP.
## All other verbs (get, watch, delete, exec, etc.) are denied.
##
## Usage:
##   chmod +x node-reader-rbac.sh
##   ./node-reader-rbac.sh <SP_OBJECT_ID>
##
## Prerequisites:
##   - kubectl configured with admin access (kubelogin -l msi or az aks get-credentials)
##   - kubelogin installed
## ============================================================

set -euo pipefail

SP_OBJECT_ID="5f12b978-4931-4722-a7b2-2830e3284f21"

if [[ -z "$SP_OBJECT_ID" ]]; then
    echo "ERROR: SP_OBJECT_ID is required."
    echo "Usage: $0 <SP_OBJECT_ID>"
    exit 1
fi

echo "Applying pod-lister ClusterRole and ClusterRoleBinding for SP: $SP_OBJECT_ID"

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
  name: sp-pod-lister
subjects:
- kind: User
  name: "5f12b978-4931-4722-a7b2-2830e3284f21"
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: pod-lister
  apiGroup: rbac.authorization.k8s.io
EOF

echo "Done. SP '$SP_OBJECT_ID' can now run 'kubectl get pods -A' only."
echo "All other operations (get, watch, exec, delete, describe, logs, etc.) are denied."
