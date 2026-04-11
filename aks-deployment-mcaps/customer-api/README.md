# Customer REST API

A production-ready Flask REST API for managing customer data with Azure PostgreSQL Flexible Server integration and Azure AD authentication support.

## 🚀 Features

- ✅ **CRUD Operations**: Complete customer management
- ✅ **Azure AD Authentication**: Token-based authentication with Azure PostgreSQL
- ✅ **Connection Pooling**: Efficient database connection management
- ✅ **Health Checks**: Built-in health endpoint for monitoring
- ✅ **Pagination**: Efficient data retrieval with pagination support
- ✅ **Filtering**: Query customers by city, country
- ✅ **Docker Support**: Multi-stage build for optimized images
- ✅ **Kubernetes Ready**: Production-grade K8s manifests with HPA
- ✅ **Security**: Non-root user, SSL/TLS, token refresh
- ✅ **Logging**: Comprehensive application logging

## 📋 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| POST | `/api/customers` | Create new customer |
| GET | `/api/customers` | Get all customers (with pagination) |
| GET | `/api/customers/{id}` | Get customer by ID |
| PUT | `/api/customers/{id}` | Update customer |
| DELETE | `/api/customers/{id}` | Delete customer |

## 🏗️ Architecture

```
Flask REST API
    ↓
Connection Pool (psycopg2)
    ↓
Azure AD Token (Azure Identity SDK)
    ↓
Azure PostgreSQL Flexible Server
```

## 📦 Project Structure

```
customer-api/
├── app.py                  # Main Flask application
├── requirements.txt        # Python dependencies
├── Dockerfile             # Multi-stage Docker build
├── .dockerignore          # Docker ignore patterns
├── .env                   # Environment configuration
├── .env.template          # Environment template
├── .gitignore            # Git ignore patterns
├── k8s-deployment.yaml   # Kubernetes manifests
└── README.md             # This file
```

## 🛠️ Local Development Setup

### Prerequisites

- Python 3.11+
- Azure CLI (for Azure AD authentication)
- Access to Azure PostgreSQL Flexible Server

### Step 1: Clone and Setup

```powershell
cd customer-api

# Create virtual environment
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt
```

### Step 2: Configure Environment

Copy `.env.template` to `.env` and update values:

```env
POSTGRES_HOST=mypgflexserver0603.postgres.database.azure.com
POSTGRES_DATABASE=postgres
POSTGRES_PORT=5432
POSTGRES_USER=admin@MngEnvMCAP463940.onmicrosoft.com
USE_AZURE_AD=true
PORT=5000
FLASK_ENV=development
```

### Step 3: Azure AD Setup

```powershell
# Login to Azure
az login

# Set PostgreSQL Azure AD admin
az postgres flexible-server ad-admin create `
  --resource-group MyEventHubRG `
  --server-name mypgflexserver0603 `
  --display-name "Admin User" `
  --object-id $(az ad signed-in-user show --query id -o tsv)
```

### Step 4: Run Application

```powershell
python app.py
```

API will be available at: `http://localhost:5000`

## 🧪 Testing the API

### Health Check

```powershell
curl http://localhost:5000/health
```

### Create Customer

```powershell
curl -X POST http://localhost:5000/api/customers `
  -H "Content-Type: application/json" `
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone": "+1234567890",
    "address": "123 Main St",
    "city": "New York",
    "country": "USA"
  }'
```

### Get All Customers

```powershell
# Basic query
curl http://localhost:5000/api/customers

# With pagination
curl "http://localhost:5000/api/customers?page=1&limit=10"

# With filters
curl "http://localhost:5000/api/customers?city=New York&country=USA"
```

### Get Customer by ID

```powershell
curl http://localhost:5000/api/customers/1
```

### Update Customer

```powershell
curl -X PUT http://localhost:5000/api/customers/1 `
  -H "Content-Type: application/json" `
  -d '{
    "phone": "+9876543210",
    "city": "Los Angeles"
  }'
```

### Delete Customer

```powershell
curl -X DELETE http://localhost:5000/api/customers/1
```

## 🐳 Docker Build and Run

### Build Docker Image

```powershell
# Build image
docker build -t customer-api:latest .

# Build with specific tag
docker build -t customer-api:v1.0 .
```

### Run Docker Container

```powershell
# Run with environment variables
docker run -d `
  -p 5000:5000 `
  -e POSTGRES_HOST=mypgflexserver0603.postgres.database.azure.com `
  -e POSTGRES_DATABASE=postgres `
  -e POSTGRES_USER=admin@MngEnvMCAP463940.onmicrosoft.com `
  -e USE_AZURE_AD=true `
  --name customer-api `
  customer-api:latest

# View logs
docker logs -f customer-api

# Stop container
docker stop customer-api
docker rm customer-api
```

## ☸️ Deploy to Azure Kubernetes Service (AKS)

### Step 1: Push to Azure Container Registry

```powershell
# Variables
$ACR_NAME = "myacrregistry"
$IMAGE_NAME = "customer-api"
$TAG = "v1.0"

# Login to ACR
az acr login --name $ACR_NAME

# Tag image
docker tag customer-api:latest ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${TAG}

# Push to ACR
docker push ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${TAG}
```

### Step 2: Configure AKS to Access ACR

```powershell
# Get AKS credentials
az aks get-credentials --resource-group MyEventHubRG --name MyAKSCluster

# Attach ACR to AKS
az aks update `
  --resource-group MyEventHubRG `
  --name MyAKSCluster `
  --attach-acr $ACR_NAME
```

### Step 3: Update Kubernetes Manifests

Edit `k8s-deployment.yaml`:

1. Update image URL:
   ```yaml
   image: <your-acr-name>.azurecr.io/customer-api:v1.0
   ```

2. Update PostgreSQL credentials in Secret (base64 encoded):
   ```powershell
   # Encode PostgreSQL user
   echo -n 'admin@MngEnvMCAP463940.onmicrosoft.com' | base64
   ```

### Step 4: Deploy to AKS

```powershell
# Apply manifests
kubectl apply -f k8s-deployment.yaml

# Verify deployment
kubectl get deployments
kubectl get pods
kubectl get services

# Check pod logs
kubectl logs -f deployment/customer-api

# Port forward for testing
kubectl port-forward service/customer-api 8080:80
```

### Step 5: Test in AKS

```powershell
# From port-forward
curl http://localhost:8080/health

# Or from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://customer-api/health
```

## 🔐 Azure Workload Identity (Recommended for Production)

For production AKS deployments, use Workload Identity instead of storing credentials:

```powershell
# Enable Workload Identity on AKS
az aks update `
  --resource-group MyEventHubRG `
  --name MyAKSCluster `
  --enable-workload-identity `
  --enable-oidc-issuer

# Create managed identity
az identity create `
  --resource-group MyEventHubRG `
  --name customer-api-identity

# Get identity details
$IDENTITY_CLIENT_ID = az identity show `
  --resource-group MyEventHubRG `
  --name customer-api-identity `
  --query clientId -o tsv

# Assign PostgreSQL roles to managed identity
# (Follow Azure documentation for PostgreSQL RBAC setup)

# Update k8s-deployment.yaml with workload identity annotations
```

## 📊 Database Schema

```sql
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## 🔍 Monitoring and Logging

### View Application Logs

```powershell
# Local
python app.py

# Docker
docker logs -f customer-api

# Kubernetes
kubectl logs -f deployment/customer-api
```

### Health Check Monitoring

```powershell
# Check health endpoint
curl http://localhost:5000/health

# Expected response:
{
  "status": "healthy",
  "service": "customer-api",
  "database": "connected",
  "timestamp": "2025-11-24T10:00:00.000000"
}
```

## 🛡️ Security Best Practices

✅ **Non-root user**: Container runs as user 1000  
✅ **Azure AD tokens**: No passwords stored in code  
✅ **SSL/TLS**: All database connections encrypted  
✅ **Token refresh**: Automatic token renewal on expiry  
✅ **Resource limits**: CPU/Memory limits in Kubernetes  
✅ **Read-only filesystem**: Minimizes attack surface  
✅ **Security context**: Drop all capabilities in K8s  

## 🚨 Troubleshooting

### Connection Timeout

```
Error: connection to server timeout expired
```

**Solutions:**
- Check firewall rules on PostgreSQL server
- Verify VNet connectivity if using private endpoint
- Ensure AKS can reach PostgreSQL (VNet peering, private endpoint)

### Authentication Failed

```
Error: password authentication failed
```

**Solutions:**
- Verify Azure AD user exists in PostgreSQL
- Run `az login` to refresh Azure CLI credentials
- Check token hasn't expired (tokens are valid for 1 hour)
- Verify `POSTGRES_USER` matches Azure AD user email

### Token Expired

The application automatically refreshes tokens. If issues persist:

```powershell
# Re-login to Azure
az login

# Restart application
kubectl rollout restart deployment/customer-api
```

## 📚 Additional Resources

- [Azure PostgreSQL Flexible Server](https://learn.microsoft.com/azure/postgresql/flexible-server/)
- [Azure AD Authentication](https://learn.microsoft.com/azure/postgresql/flexible-server/how-to-configure-sign-in-azure-ad-authentication)
- [AKS Workload Identity](https://learn.microsoft.com/azure/aks/workload-identity-overview)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [psycopg2 Documentation](https://www.psycopg.org/docs/)

## 📄 License

MIT License - See LICENSE file for details

## 👥 Contributing

Contributions welcome! Please open an issue or submit a pull request.
