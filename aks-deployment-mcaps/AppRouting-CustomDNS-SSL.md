# AKS App Routing – Custom Private DNS + SSL/TLS Setup

This guide documents the end-to-end setup of:
- **App Routing** with internal nginx ingress controller
- **Private DNS zone** (`private.vinay.com`) for custom hostnames
- **TLS certificate** generated with OpenSSL, stored in Azure Key Vault
- **Ingress** with TLS termination via Key Vault CSI integration

---

## Architecture

```
Client (inside VNet)
    │
    ▼
Private DNS: store-front.private.vinay.com → 10.0.0.11
    │
    ▼
nginx-internal LoadBalancer (IP: 10.0.0.11)
    │
    ▼
Kubernetes Ingress (ingressClassName: nginx-internal)
    │  TLS cert pulled from Key Vault via annotation
    ▼
store-front Service (port 80)
```

---

## Prerequisites

- AKS cluster running with App Routing addon enabled
- Azure CLI logged in
- `kubectl` configured for the cluster
- OpenSSL installed (`winget install ShiningLight.OpenSSL.Light`)

---

## Step 1 – Enable App Routing with Internal Nginx

```powershell
# Enable app routing addon (if not already enabled)
az aks approuting enable `
    --resource-group <resource-group> `
    --name <cluster-name>

# Switch nginx to Internal LoadBalancer mode
az aks approuting update `
    --resource-group <resource-group> `
    --name <cluster-name> `
    --nginx Internal
```

**Verify the internal LoadBalancer gets a private IP:**

```powershell
kubectl get svc -n app-routing-system
# nginx-internal-0   LoadBalancer   172.x.x.x   10.0.0.11   80:xxx/TCP,443:xxx/TCP
```

Note the `EXTERNAL-IP` — this is your private LoadBalancer IP (e.g. `10.0.0.11`).

---

## Step 2 – Create Private DNS Zone

```powershell
$RESOURCE_GROUP = "azure-vk-rg"
$DNS_ZONE       = "private.vinay.com"

az network private-dns zone create `
    --resource-group $RESOURCE_GROUP `
    --name $DNS_ZONE
```

### Link DNS Zone to AKS VNet

```powershell
$AKS_VNET_ID = $(az network vnet show `
    --resource-group $RESOURCE_GROUP `
    --name <aks-vnet-name> `
    --query id --output tsv)

az network private-dns link vnet create `
    --resource-group $RESOURCE_GROUP `
    --zone-name $DNS_ZONE `
    --name "aks-dns-link" `
    --virtual-network $AKS_VNET_ID `
    --registration-enabled false
```

---

## Step 3 – Create DNS A Record

Point your app hostname to the nginx internal LoadBalancer IP:

```powershell
# store-front.private.vinay.com → 10.0.0.11 (nginx-internal LoadBalancer IP)
az network private-dns record-set a add-record `
    --resource-group $RESOURCE_GROUP `
    --zone-name private.vinay.com `
    --record-set-name store-front `
    --ipv4-address 10.0.0.11
```

**Verify:**
```powershell
az network private-dns record-set a list `
    --resource-group $RESOURCE_GROUP `
    --zone-name private.vinay.com
```

---

## Step 4 – Generate Self-Signed TLS Certificate

```powershell
# Create a cert directory
mkdir cert
cd cert

# Generate certificate and private key
openssl req -new -x509 -nodes `
    -out aks-ingress-tls.crt `
    -keyout aks-ingress-tls.key `
    -subj "/CN=*.private.vinay.com" `
    -addext "subjectAltName=DNS:store-front.private.vinay.com"

# Convert to PFX format (required for Key Vault import)
openssl pkcs12 -export `
    -out aks-ingress-tls.pfx `
    -inkey aks-ingress-tls.key `
    -in aks-ingress-tls.crt `
    -passout pass:""
```

> **Note:** If `openssl` is not found, add to PATH:
> ```powershell
> $env:Path += ";C:\Program Files\OpenSSL-Win64\bin"
> ```

---

## Step 5 – Create Azure Key Vault

```powershell
$KV_NAME = "aksciliumkv"

az keyvault create `
    --resource-group $RESOURCE_GROUP `
    --name $KV_NAME `
    --location uaenorth `
    --enable-rbac-authorization true
```

### Grant yourself permission to import certificates

```powershell
$MY_OID = $(az ad signed-in-user show --query id --output tsv)

az role assignment create `
    --assignee $MY_OID `
    --role "Key Vault Certificates Officer" `
    --scope $(az keyvault show --name $KV_NAME --resource-group $RESOURCE_GROUP --query id --output tsv)
```

> Wait ~1-2 minutes for role propagation before proceeding.

---

## Step 6 – Import Certificate to Key Vault

```powershell
az keyvault certificate import `
    --vault-name $KV_NAME `
    --name aks-ingress-cer `
    --file aks-ingress-tls.pfx `
    --password ""
```

**Verify:**
```powershell
az keyvault certificate show `
    --vault-name $KV_NAME `
    --name aks-ingress-cer `
    --query "id" --output tsv
# Returns: https://aksciliumkv.vault.azure.net/certificates/aks-ingress-cer/<version>
```

---

## Step 7 – Grant AKS Access to Key Vault

The App Routing addon needs permission to read certificates from Key Vault.

```powershell
# Get the App Routing addon managed identity
$APPROUTING_IDENTITY = $(az aks show `
    --resource-group $RESOURCE_GROUP `
    --name <cluster-name> `
    --query "ingressProfile.webAppRouting.identity.objectId" `
    --output tsv)

$KV_ID = $(az keyvault show `
    --name $KV_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id --output tsv)

az role assignment create `
    --assignee $APPROUTING_IDENTITY `
    --role "Key Vault Secrets User" `
    --scope $KV_ID
```

---

## Step 8 – Deploy Ingress with TLS

Create `ingress-with-cert.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.azure.com/tls-cert-keyvault-uri: https://aksciliumkv.vault.azure.net/certificates/aks-ingress-cer
  name: store-front
  namespace: aks-store
spec:
  ingressClassName: nginx-internal
  rules:
  - host: store-front.private.vinay.com
    http:
      paths:
      - backend:
          service:
            name: store-front
            port:
              number: 80
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - store-front.private.vinay.com
    secretName: keyvault-store-front   # auto-created by app routing from Key Vault
```

```powershell
kubectl apply -f ingress-with-cert.yaml
```

**Verify ingress gets an ADDRESS:**
```powershell
kubectl get ingress -n aks-store
# NAME          CLASS            HOSTS                           ADDRESS     PORTS     AGE
# store-front   nginx-internal   store-front.private.vinay.com   10.0.0.11   80, 443   1m
```

**Verify the TLS secret was synced from Key Vault:**
```powershell
kubectl get secret keyvault-store-front -n aks-store
```

---

## Step 9 – Test (from inside the VNet)

From a VM or jumpbox inside the same VNet:

```bash
# Test HTTP
curl http://store-front.private.vinay.com

# Test HTTPS (self-signed cert, skip verify)
curl -k https://store-front.private.vinay.com

# Test HTTPS with cert validation
curl --cacert /path/to/aks-ingress-tls.crt https://store-front.private.vinay.com
```

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| Ingress ADDRESS blank | `kubectl get pods -n app-routing-system` — check if nginx pods are Running |
| DNS not resolving | Verify VNet link: `az network private-dns link vnet list --zone-name private.vinay.com` |
| TLS secret not created | Check app routing identity has `Key Vault Secrets User` role on the vault |
| Cert import Forbidden | Assign `Key Vault Certificates Officer` role to your user identity |
| curl SSL error | Use `-k` flag or trust the self-signed CA cert |

---

## Key Resources

| Resource | Value |
|----------|-------|
| Cluster | `aks-vk-with-cilium` |
| Resource Group | `azure-vk-rg` |
| Key Vault | `aksciliumkv` |
| DNS Zone | `private.vinay.com` |
| Nginx Internal IP | `10.0.0.11` |
| App hostname | `store-front.private.vinay.com` |
| KV Certificate URI | `https://aksciliumkv.vault.azure.net/certificates/aks-ingress-cer` |
