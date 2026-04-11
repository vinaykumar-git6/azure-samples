# Event Hub to PostgreSQL Service

A production-ready Python service that consumes Azure Entra ID sign-in events from Azure Event Hub and stores them in Azure PostgreSQL database.

## Features

- ✅ **Managed Identity**: Uses Azure Managed Identity for authentication (no connection strings!)
- ✅ **Key Vault Integration**: Securely retrieves secrets from Azure Key Vault
- ✅ **Event Hub Consumer**: Processes events from Azure Event Hub in real-time
- ✅ **PostgreSQL Storage**: Stores events with proper indexing for fast queries
- ✅ **FastAPI REST API**: Provides health check and statistics endpoints
- ✅ **Docker Ready**: Multi-stage Dockerfile for optimized container images
- ✅ **Kubernetes Ready**: Complete K8s manifests with workload identity
- ✅ **Auto-scaling**: Configurable batch processing and checkpointing

## Architecture

```
Azure Entra ID → Event Hub → Python Service → PostgreSQL
                                ↓
                          Key Vault (secrets)
```

## Prerequisites

- Azure subscription
- Azure Event Hub namespace and event hub
- Azure PostgreSQL Flexible Server
- Azure Key Vault
- Azure Container Registry (for AKS deployment)
- Azure Kubernetes Service (optional)

## Local Development

### 1. Set up environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your Azure resource details
```

### 2. Store PostgreSQL password in Key Vault

```bash
az keyvault secret set \
  --vault-name your-keyvault \
  --name postgres-password \
  --value "YourSecurePassword123!"
```

### 3. Install dependencies

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 4. Run locally

```bash
# Make sure you're logged in to Azure
az login

# Run the service
python app.py
```

The service will be available at `http://localhost:8000`

## API Endpoints

### Health Check
```bash
GET /health
```

Response:
```json
{
  "status": "healthy",
  "service": "eventhub-postgres-service",
  "timestamp": "2025-11-13T10:30:00.000Z"
}
```

### Statistics
```bash
GET /stats
```

Response:
```json
{
  "total_events": 15420,
  "recent_events_1h": 234,
  "unique_users": 89,
  "timestamp": "2025-11-13T10:30:00.000Z"
}
```

## Docker Deployment

### Build the image

```bash
docker build -t events-service:latest .
```

### Run locally with Docker

```bash
docker run -d \
  --name events-service \
  -p 8000:8000 \
  -e EVENTHUB_NAMESPACE="your-eventhub-namespace" \
  -e EVENTHUB_NAME="signin-events" \
  -e POSTGRES_HOST="your-postgres.postgres.database.azure.com" \
  -e POSTGRES_DATABASE="signinevents" \
  -e POSTGRES_USER="adminuser" \
  -e KEYVAULT_URL="https://your-keyvault.vault.azure.net/" \
  events-service:latest
```

### Push to Azure Container Registry

```bash
# Login to ACR
az acr login --name yourregistry

# Tag and push
docker tag events-service:latest yourregistry.azurecr.io/events-service:latest
docker push yourregistry.azurecr.io/events-service:latest
```

## AKS Deployment

### 1. Enable Workload Identity on AKS

```bash
# Create AKS cluster with workload identity
az aks create \
  --resource-group rg-events-service \
  --name aks-events-service \
  --node-count 2 \
  --enable-managed-identity \
  --enable-workload-identity \
  --enable-oidc-issuer \
  --attach-acr yourregistry \
  --generate-ssh-keys
```

### 2. Create Managed Identity

```bash
# Create user-assigned managed identity
az identity create \
  --resource-group rg-events-service \
  --name events-service-identity

# Get identity details
IDENTITY_CLIENT_ID=$(az identity show \
  --resource-group rg-events-service \
  --name events-service-identity \
  --query clientId -o tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --resource-group rg-events-service \
  --name events-service-identity \
  --query principalId -o tsv)
```

### 3. Grant Permissions

```bash
# Event Hub Data Receiver
az role assignment create \
  --role "Azure Event Hubs Data Receiver" \
  --assignee $IDENTITY_PRINCIPAL_ID \
  --scope /subscriptions/{subscription-id}/resourceGroups/rg-events-service/providers/Microsoft.EventHub/namespaces/{eventhub-namespace}

# Key Vault Secrets User
az keyvault set-policy \
  --name your-keyvault \
  --object-id $IDENTITY_PRINCIPAL_ID \
  --secret-permissions get list
```

### 4. Configure Federated Identity

```bash
# Get AKS OIDC issuer
AKS_OIDC_ISSUER=$(az aks show \
  --resource-group rg-events-service \
  --name aks-events-service \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Create federated identity credential
az identity federated-credential create \
  --name events-service-federated-id \
  --identity-name events-service-identity \
  --resource-group rg-events-service \
  --issuer $AKS_OIDC_ISSUER \
  --subject system:serviceaccount:events-service:events-service-sa
```

### 5. Update ConfigMap

Edit `k8s-deployment.yaml` and replace placeholders:
- `${ACR_NAME}` → your ACR name
- `${MANAGED_IDENTITY_CLIENT_ID}` → $IDENTITY_CLIENT_ID
- Update all resource values in ConfigMap

### 6. Deploy to AKS

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group rg-events-service \
  --name aks-events-service

# Deploy
kubectl apply -f k8s-deployment.yaml

# Check status
kubectl get pods -n events-service
kubectl logs -f deployment/events-service -n events-service
```

## Database Schema

The service automatically creates the following table:

```sql
CREATE TABLE signin_events (
    id SERIAL PRIMARY KEY,
    event_id VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    user_principal_name VARCHAR(255),
    user_id VARCHAR(255),
    app_display_name VARCHAR(255),
    app_id VARCHAR(255),
    ip_address VARCHAR(45),
    location VARCHAR(255),
    status VARCHAR(50),
    sign_in_time TIMESTAMP,
    risk_level VARCHAR(50),
    device_detail JSONB,
    raw_event JSONB NOT NULL
);
```

Indexes:
- `idx_signin_events_user_id` - Fast user lookup
- `idx_signin_events_sign_in_time` - Time-based queries
- `idx_signin_events_status` - Status filtering

## Configuration

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `EVENTHUB_NAMESPACE` | Yes | Event Hub namespace name | - |
| `EVENTHUB_NAME` | Yes | Event Hub name | - |
| `CONSUMER_GROUP` | No | Consumer group name | `$Default` |
| `POSTGRES_HOST` | Yes | PostgreSQL server hostname | - |
| `POSTGRES_DATABASE` | Yes | Database name | - |
| `POSTGRES_USER` | Yes | Database username | - |
| `KEYVAULT_URL` | Yes | Key Vault URL | - |
| `POSTGRES_PASSWORD_SECRET_NAME` | No | Secret name in Key Vault | `postgres-password` |
| `BATCH_SIZE` | No | Events batch size | `100` |
| `MAX_WAIT_TIME` | No | Max wait time in seconds | `60` |

## Monitoring

### View logs in AKS

```bash
# Real-time logs
kubectl logs -f deployment/events-service -n events-service

# Last 100 lines
kubectl logs --tail=100 deployment/events-service -n events-service
```

### Check health

```bash
kubectl port-forward -n events-service svc/events-service 8000:80
curl http://localhost:8000/health
curl http://localhost:8000/stats
```

## Troubleshooting

### Service can't connect to Event Hub

1. Verify managed identity has "Azure Event Hubs Data Receiver" role
2. Check EVENTHUB_NAMESPACE is just the namespace name (no .servicebus.windows.net)
3. Verify workload identity is properly configured

### Can't retrieve Key Vault secrets

1. Ensure managed identity has Key Vault access policy or RBAC role
2. Verify KEYVAULT_URL format: `https://name.vault.azure.net/`
3. Check the secret name exists in Key Vault

### PostgreSQL connection fails

1. Verify firewall rules allow AKS subnet
2. Check PostgreSQL password is correct in Key Vault
3. Ensure SSL is enabled on PostgreSQL server

### Events not being processed

1. Check Event Hub has data: `az eventhub eventhub show --namespace-name ... --name ...`
2. Verify consumer group exists
3. Check service logs for errors

## Security Best Practices

✅ **Implemented:**
- Managed Identity for all Azure services
- No connection strings in code or environment
- Secrets stored in Key Vault
- Workload Identity for AKS
- SSL/TLS for all connections
- Resource limits in Kubernetes
- Health checks and readiness probes

## Scaling

The service supports horizontal scaling:

```bash
# Scale to 5 replicas
kubectl scale deployment/events-service -n events-service --replicas=5
```

Each replica will process events from different partitions of the Event Hub.

## Clean Up

```bash
# Delete Kubernetes resources
kubectl delete namespace events-service

# Delete Azure resources
az group delete --name rg-events-service --yes
```

## License

MIT
