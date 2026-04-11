# Azure API Center – DevOps Registration Pipeline

Automates registering APIs in [Azure API Center](https://learn.microsoft.com/en-us/azure/api-center/overview) via Azure DevOps pipelines.

## What it does

Each pipeline run performs the following steps (all idempotent):

```
1. Register API          →  az apic api create / update
2. Create Version        →  az apic api version create / update
3. Upload OpenAPI Spec   →  az apic api definition import-specification
4. Create Environment    →  az apic environment create / update
5. Create Deployment     →  az apic api deployment create / update
```

## Project structure

```
apicenter-devops/
├── azure-pipelines.yml          ← Main pipeline definition
├── api-spec/
│   └── openapi.yaml             ← Replace with your API spec
└── scripts/
    ├── register-api.sh          ← Step 1: Register / update API
    ├── create-version.sh        ← Step 2: Create API version
    ├── upload-spec.sh           ← Step 3: Upload OpenAPI spec
    ├── create-environment.sh    ← Step 4: Create environment
    └── create-deployment.sh     ← Step 5: Create deployment
```

## Prerequisites

### 1. Azure Service Connection in Azure DevOps
Create a service connection with the **Contributor** role on the API Center resource:

- Azure DevOps → Project Settings → Service connections → New → **Azure Resource Manager**
- Name it exactly: `azure-apic-service-connection` *(or update `AZURE_SERVICE_CONNECTION` in the pipeline variable group)*

### 2. Required RBAC on API Center
The service principal needs:
- `Azure API Center Service Contributor` on the API Center resource

```bash
az role assignment create \
  --role "Azure API Center Service Contributor" \
  --assignee <service-principal-id> \
  --scope /subscriptions/7d1e8453-2920-4f6d-9a6e-bc7005c10a22/resourceGroups/azure-vk-rg/providers/Microsoft.ApiCenter/services/vinayorg-apic
```

### 3. Pipeline Variable
Set the variable `AZURE_SERVICE_CONNECTION` in your pipeline or variable group:

| Variable | Value |
|---|---|
| `AZURE_SERVICE_CONNECTION` | Name of your Azure DevOps service connection |

## Running the pipeline

### From Azure DevOps UI
1. Go to **Pipelines** → **Run pipeline**
2. Fill in the parameters:

| Parameter | Example |
|---|---|
| `apiId` | `payments-api` |
| `apiTitle` | `Payments API` |
| `apiKind` | `rest` |
| `apiVersion` | `1.0.0` |
| `lifecycleStage` | `production` |
| `environmentId` | `prod-env` |
| `environmentTitle` | `Production` |
| `environmentKind` | `production` |
| `serverUrl` | `https://api.example.com/v1` |
| `specFile` | `api-spec/openapi.yaml` |

### From Azure CLI (trigger manually)
```bash
az pipelines run \
  --name "API Center Registration" \
  --parameters \
    apiId=payments-api \
    apiTitle="Payments API" \
    apiVersion=1.0.0 \
    environmentId=prod-env \
    serverUrl=https://api.example.com/v1
```

## API Center details

| Setting | Value |
|---|---|
| Subscription | `7d1e8453-2920-4f6d-9a6e-bc7005c10a22` |
| Resource Group | `azure-vk-rg` |
| API Center Name | `vinayorg-apic` |
| Workspace | `default` |

## Trigger on spec changes

The pipeline auto-triggers when any file under `api-spec/` changes on the `main` branch. This means committing a new `openapi.yaml` will automatically register/update the API in API Center.

## Viewing registered APIs

```bash
# List all APIs
az apic api list -g azure-vk-rg -n vinayorg-apic -o table

# List all environments
az apic environment list -g azure-vk-rg -n vinayorg-apic -o table

# List deployments for an API
az apic api deployment list -g azure-vk-rg -n vinayorg-apic --api-id <api-id> -o table
```
