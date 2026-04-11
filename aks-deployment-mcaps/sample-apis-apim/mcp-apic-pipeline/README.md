# MCP Server → Azure API Center: ADO Pipeline Setup Guide

Auto-register your MCP server to Azure API Center (APIC) every time you push to `main`.

---

## Files in this folder

| File | Purpose |
|---|---|
| `azure-pipelines-register-mcp.yml` | ADO pipeline definition — copy to your MCP server repo |
| `register-to-apic.ps1` | Registration script called by the pipeline — copy to your repo |

---

## Step-by-Step Setup

### STEP 1 — One-time: Create a Service Connection in ADO

> This lets the pipeline authenticate to Azure without embedding credentials.

1. Go to your ADO project → **Project Settings** (bottom-left gear icon)
2. Click **Service Connections** → **New service connection**
3. Choose **Azure Resource Manager** → **Service principal (automatic)**
4. Select your **Subscription** (`<YOUR-SUBSCRIPTION-ID>`)
5. Set **Resource Group** to `azure-vk-rg` *(scopes permission to just APIC's RG)*
6. Name it exactly: **`azure-apic-sc`**
7. Check **"Grant access permission to all pipelines"** → Save

---

### STEP 2 — One-time: Grant the Service Principal APIC permissions

The auto-created Service Principal needs permission on APIC.

```bash
# Get the Service Principal name from the service connection details in ADO
SP_NAME="<name shown in the service connection>"

az role assignment create \
  --assignee "$SP_NAME" \
  --role "API Center Service Contributor" \
  --scope "/subscriptions/<YOUR-SUBSCRIPTION-ID>/resourceGroups/azure-vk-rg/providers/Microsoft.ApiCenter/services/vinayorg-apic"
```

> If `API Center Service Contributor` is not available in your region, use **`Contributor`** on the resource group instead.

---

### STEP 3 — Copy files into your MCP server repo

Layout expected in the MCP server repo:

```
my-mcp-server/
├── openapi.json                          ← your MCP OpenAPI spec
├── register-to-apic.ps1                  ← copied from this folder
└── azure-pipelines-register-mcp.yml      ← copied from this folder
```

---

### STEP 4 — Customize the pipeline variables

Open `azure-pipelines-register-mcp.yml` and update the **Variables** section:

```yaml
variables:
  AZURE_SERVICE_CONNECTION: "azure-apic-sc"          # must match Step 1 name
  AZURE_SUBSCRIPTION_ID:    "<YOUR-SUBSCRIPTION-ID>"

  APIC_SERVICE:    "vinayorg-apic"
  APIC_RG:         "azure-vk-rg"

  API_ID:          "weather-mcp"            # ← change: unique ID for YOUR server
  API_TITLE:       "Weather MCP Server"     # ← change: display name
  API_VERSION:     "v1"                     # ← change if needed
  LIFECYCLE_STAGE: "development"            # design|development|testing|preview|production
  SPEC_FILE:       "openapi.json"           # ← change: path to your spec in the repo
```

---

### STEP 5 — Create the ADO Pipeline

1. Go to your ADO project → **Pipelines** → **New pipeline**
2. Choose **Azure Repos Git** (or GitHub if your repo is there)
3. Select your MCP server repository
4. Choose **Existing Azure Pipelines YAML file**
5. Set path to: `/azure-pipelines-register-mcp.yml`
6. Click **Save** (not Run yet — review first)

---

### STEP 6 — Set up an Approval Gate (optional but recommended)

The pipeline uses an **ADO Environment** called `apic-development` (or `apic-production` etc.) for the deploy stage. Add an approval gate so a team lead approves before each APIC registration:

1. Go to **Pipelines** → **Environments**
2. Open `apic-production` (auto-created on first run)
3. Click **Approvals and checks** → **Add** → **Approvals**
4. Add approvers → Save

---

### STEP 7 — Push to main — pipeline runs automatically

```bash
# Make a change to your spec or MCP server code
git add openapi.json
git commit -m "feat: add new tool endpoint"
git push origin main
```

The pipeline will:
1. **Stage 1** — Validate the JSON/YAML syntax of your spec
2. **Stage 2** — Log in to Azure via service connection, run `register-to-apic.ps1`, update APIC

---

## What the script does (register-to-apic.ps1)

Each run is **idempotent** — safe to run multiple times:

| Step | `az apic` command | Behavior |
|---|---|---|
| 1 | Install `apic-extension` | Skips if already installed |
| 2 | `apic api create/update` | Creates if not exists; updates title/metadata if exists |
| 3 | `apic api version create/update` | Creates version `v1`; updates lifecycle stage |
| 4 | `apic api definition create` | Creates definition entry (once) |
| 5 | `apic api definition import-specification` | **Always overwrites** — picks up latest spec |

---

## Multiple MCP Servers in one org

Copy `azure-pipelines-register-mcp.yml` into **each** MCP server repo and set the `API_ID` variable differently per repo. Each pipeline registers its own server independently.

Or, if you want a single pipeline that loops over multiple servers:

```yaml
# In a monorepo, you can use a matrix strategy:
strategy:
  matrix:
    WeatherMCP:
      API_ID: "weather-mcp"
      API_TITLE: "Weather MCP Server"
      SPEC_FILE: "services/weather-mcp/openapi.json"
    PaymentMCP:
      API_ID: "payment-mcp"
      API_TITLE: "Payment MCP Server"
      SPEC_FILE: "services/payment-mcp/openapi.json"
```

---

## Troubleshooting

| Error | Fix |
|---|---|
| `az: command not found` | Pipeline agent image must be `ubuntu-latest` or `windows-latest` (Azure CLI pre-installed) |
| `ERROR: (AuthorizationFailed)` | Service principal missing `API Center Service Contributor` role — re-check Step 2 |
| `Spec file not found` | Check `SPEC_FILE` variable path is relative to repo root |
| `ERROR: (ResourceNotFound) apic` | Run `az extension add --name apic-extension` manually first, or check APIC service name/RG |
| Pipeline doesn't trigger on push | Check `trigger.paths.include` — add your spec file extension |
