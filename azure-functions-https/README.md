# Azure Functions Cosmos DB Customer Account CRUD Service

A Python-based Azure Functions application for managing customer account data stored in Azure Cosmos DB. Provides RESTful endpoints for create, read, update, and list operations with built-in validation and error handling.

## Features

- **Create Customer**: POST endpoint to insert new customer accounts
- **Read Customer**: GET endpoint to fetch customer details by ID
- **Update Customer**: PUT endpoint to modify existing customer records
- **List Customers**: GET endpoint with optional filtering by status
- **Health Check**: Anonymous endpoint for service status
- **Validation**: Pydantic-based input validation
- **Error Handling**: Comprehensive error handling with proper HTTP status codes
- **Logging**: Structured logging for debugging and monitoring

## Project Structure

```
azure-functions/
├── function_app.py           # Main Azure Functions app with HTTP triggers
├── models.py                 # Pydantic data models for validation
├── cosmos_db.py              # Cosmos DB client wrapper
├── pyproject.toml            # Python dependencies
├── host.json                 # Azure Functions host configuration
├── local.settings.json       # Local development settings
├── .env.example              # Environment variables template
└── README.md                 # This file
```

## Prerequisites

- Python 3.11 or later
- Azure Functions Core Tools v4
- Azure Cosmos DB account with SQL API
- `uv` package manager (or pip)

## Setup

### 1. Install Dependencies

```bash
cd azure-functions
uv sync
# or
pip install -r requirements.txt
```

### 2. Configure Environment

Copy `.env.example` to `.env` and fill in your Cosmos DB credentials:

```bash
cp .env.example .env
```

Edit `.env` with your Cosmos DB values:
```
COSMOS_ENDPOINT=https://<your-account>.documents.azure.com:443/
COSMOS_KEY=<your-primary-key>
COSMOS_DATABASE=CustomerDB
COSMOS_CONTAINER=Accounts
```

Also update `local.settings.json` with the same values.

### 3. Create Cosmos DB Container (if needed)

```python
from azure.cosmos import CosmosClient

client = CosmosClient(endpoint, key)
database = client.create_database_if_not_exists(id="CustomerDB")
container = database.create_container_if_not_exists(
    id="Accounts",
    partition_key="/id"
)
```

## API Endpoints

### 1. Create Customer Account

**Endpoint**: `POST /api/customers`

**Authentication**: Function key required

**Request Body**:
```json
{
  "id": "cust-001",
  "name": "John Doe",
  "email": "john@example.com",
  "phone": "+1-555-0123",
  "account_type": "premium",
  "status": "active",
  "balance": 5000.00
}
```

**Response** (201 Created):
```json
{
  "success": true,
  "message": "Customer account created successfully",
  "data": {
    "id": "cust-001",
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "+1-555-0123",
    "account_type": "premium",
    "status": "active",
    "balance": 5000.00,
    "created_at": "2025-11-07T12:34:56.789012",
    "updated_at": "2025-11-07T12:34:56.789012"
  }
}
```

### 2. Get Customer by ID

**Endpoint**: `GET /api/customers/{customer_id}`

**Authentication**: Function key required

**Example**:
```bash
GET /api/customers/cust-001
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Customer account retrieved successfully",
  "data": {
    "id": "cust-001",
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "+1-555-0123",
    "account_type": "premium",
    "status": "active",
    "balance": 5000.00,
    "created_at": "2025-11-07T12:34:56.789012",
    "updated_at": "2025-11-07T12:34:56.789012"
  }
}
```

### 3. Update Customer Account

**Endpoint**: `PUT /api/customers/{customer_id}`

**Authentication**: Function key required

**Request Body** (partial update):
```json
{
  "balance": 7500.00,
  "status": "premium"
}
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Customer account updated successfully",
  "data": {
    "id": "cust-001",
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "+1-555-0123",
    "account_type": "premium",
    "status": "premium",
    "balance": 7500.00,
    "created_at": "2025-11-07T12:34:56.789012",
    "updated_at": "2025-11-07T13:00:00.123456"
  }
}
```

### 4. List Customers

**Endpoint**: `GET /api/customers`

**Authentication**: Function key required

**Query Parameters**:
- `status` (optional): Filter by account status (active, inactive, suspended)

**Examples**:
```bash
# Get all customers
GET /api/customers

# Get only active customers
GET /api/customers?status=active
```

**Response** (200 OK):
```json
{
  "success": true,
  "message": "Retrieved 2 customer accounts",
  "data": {
    "customers": [
      {
        "id": "cust-001",
        "name": "John Doe",
        "email": "john@example.com",
        "status": "active",
        "balance": 5000.00
      },
      {
        "id": "cust-002",
        "name": "Jane Doe",
        "email": "jane@example.com",
        "status": "active",
        "balance": 7500.00
      }
    ],
    "count": 2
  }
}
```

### 5. Health Check

**Endpoint**: `GET /api/health`

**Authentication**: Anonymous

**Response** (200 OK):
```json
{
  "status": "healthy",
  "service": "Customer Account Service"
}
```

## Error Responses

### 400 Bad Request (Validation Error)
```json
{
  "success": false,
  "message": "Validation failed",
  "error": "1 validation error for CustomerAccount\nname\n  String should have at least 1 character"
}
```

### 404 Not Found
```json
{
  "success": false,
  "message": "Customer not found",
  "error": "Customer with ID cust-999 not found"
}
```

### 500 Internal Server Error
```json
{
  "success": false,
  "message": "Error creating customer account",
  "error": "Connection to Cosmos DB failed"
}
```

## Local Testing

### 1. Start the Functions Runtime

```bash
func start
```

The API will be available at `http://localhost:7071/api/`

### 2. Test Endpoints with curl

**Create customer**:
```bash
curl -X POST http://localhost:7071/api/customers \
  -H "Content-Type: application/json" \
  -d '{
    "id": "cust-001",
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "+1-555-0123",
    "account_type": "premium",
    "status": "active",
    "balance": 5000.00
  }'
```

**Get customer**:
```bash
curl http://localhost:7071/api/customers/cust-001
```

**Update customer**:
```bash
curl -X PUT http://localhost:7071/api/customers/cust-001 \
  -H "Content-Type: application/json" \
  -d '{
    "balance": 7500.00,
    "account_type": "enterprise"
  }'
```

**List customers**:
```bash
curl http://localhost:7071/api/customers
curl "http://localhost:7071/api/customers?status=active"
```

**Health check**:
```bash
curl http://localhost:7071/api/health
```

## Deployment to Azure

### 1. Create Azure Resources

```bash
# Create resource group
az group create --name myResourceGroup --location eastus

# Create storage account
az storage account create \
  --name mystorageaccount \
  --resource-group myResourceGroup \
  --location eastus \
  --sku Standard_LRS

# Create Function App
az functionapp create \
  --resource-group myResourceGroup \
  --consumption-plan-location eastus \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --name myCustomerFunctionApp \
  --storage-account mystorageaccount
```

### 2. Configure App Settings

```bash
az functionapp config appsettings set \
  --name myCustomerFunctionApp \
  --resource-group myResourceGroup \
  --settings \
    "COSMOS_ENDPOINT=https://<your-account>.documents.azure.com:443/" \
    "COSMOS_KEY=<your-key>" \
    "COSMOS_DATABASE=CustomerDB" \
    "COSMOS_CONTAINER=Accounts"
```

### 3. Deploy Code

```bash
func azure functionapp publish myCustomerFunctionApp
```

## Best Practices Applied

- **Validation**: Pydantic models ensure data integrity
- **Error Handling**: Comprehensive try-catch with meaningful error messages
- **Logging**: Structured logging for debugging and monitoring
- **Singleton Pattern**: Cosmos DB client initialized once (lazy)
- **Timestamps**: Automatic `created_at` and `updated_at` tracking
- **Partition Key**: Uses `customer_id` as partition key for optimal distribution
- **Security**: Function-level authentication (keys) for protected endpoints
- **Documentation**: Clear docstrings and comprehensive README

## Troubleshooting

**Issue**: Connection to Cosmos DB failed
- Verify `COSMOS_ENDPOINT` and `COSMOS_KEY` are correct
- Ensure Cosmos DB firewall allows your IP address
- Check network connectivity

**Issue**: Container not found
- Create the container manually or via setup script
- Verify `COSMOS_DATABASE` and `COSMOS_CONTAINER` names

**Issue**: Validation errors
- Check JSON request body matches the `CustomerAccount` schema
- Ensure required fields are provided

## References

- [Azure Functions Python Developer Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [Azure Cosmos DB SQL API Python SDK](https://learn.microsoft.com/en-us/azure/cosmos-db/sql/quickstart-python)
- [Pydantic Documentation](https://docs.pydantic.dev/)
