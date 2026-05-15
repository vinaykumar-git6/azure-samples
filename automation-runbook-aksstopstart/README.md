# AKS Start/Stop Automation Runbook

Automated daily start and stop of an AKS cluster using Azure Automation Account with Managed Identity authentication.

## Overview

This solution deploys an Azure Automation Account with a PowerShell runbook that starts and stops an AKS cluster on a daily schedule. It uses a System-Assigned Managed Identity for secure, passwordless authentication — no credentials to manage or rotate.

| Component | Value |
|-----------|-------|
| Automation Account | Configurable (default: `aa-aks-scheduler`) |
| Runbook | `AKS-StartStop-<ClusterName>` |
| Stop Schedule | Configurable (default: 17:00 UTC) |
| Start Schedule | Configurable (default: 03:00 UTC) |
| Authentication | System Managed Identity (Contributor on AKS) |

## Files

| File | Purpose |
|------|---------|
| `Deploy-AKS-Automation.ps1` | One-click deployment script — creates all Azure resources |
| `AKS-StartStop-Runbook.ps1` | The runbook code uploaded to Azure Automation |

---

## How the Runbook Works

### `AKS-StartStop-Runbook.ps1`

This is the PowerShell script that runs inside Azure Automation on schedule.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Action` | String | Yes | `Start` or `Stop` — determines the operation |
| `ClusterName` | String | Yes | Name of the AKS cluster |
| `ResourceGroupName` | String | Yes | Resource group containing the AKS cluster |
| `SubscriptionId` | String | Yes | Azure subscription ID |

**Execution Flow:**

```
1. Authenticate via Managed Identity
   └─ Connect-AzAccount -Identity
   └─ Set-AzContext -SubscriptionId <subId>

2. Execute Action
   ├─ If Action = "Stop"  → Stop-AzAksCluster
   └─ If Action = "Start" → Start-AzAksCluster

3. Log result with timestamp
   └─ Success → logs completion time
   └─ Failure → throws error with details
```

**Key Design Decisions:**
- Uses `Connect-AzAccount -Identity` — no stored credentials, no expiry
- Includes timestamped logging for job history troubleshooting
- Validates the `Action` parameter with `[ValidateSet]` to prevent invalid input
- Uses try/catch with `throw` to ensure Azure Automation marks failed jobs correctly

---

## Deployment — Step-by-Step

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- Sufficient permissions (Owner or Contributor + User Access Administrator on the resource group)
- PowerShell 5.1+ or pwsh 7+

### Running the Deployment

```powershell
cd automation-runbook-aksstopstart

# Required parameters
.\Deploy-AKS-Automation.ps1 `
    -ResourceGroupName "my-rg" `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -AksClusterName "my-aks-cluster"

# With optional parameters
.\Deploy-AKS-Automation.ps1 `
    -ResourceGroupName "my-rg" `
    -SubscriptionId "00000000-0000-0000-0000-000000000000" `
    -AksClusterName "my-aks-cluster" `
    -AutomationAccountName "my-automation-account" `
    -Location "westeurope" `
    -StopTimeUTC "20:00" `
    -StartTimeUTC "06:00"
```

**Deployment Parameters:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `ResourceGroupName` | Yes | — | Resource group for Automation Account and AKS |
| `SubscriptionId` | Yes | — | Azure subscription ID |
| `AksClusterName` | Yes | — | Name of the AKS cluster to schedule |
| `AutomationAccountName` | No | `aa-aks-scheduler` | Name of the Automation Account |
| `Location` | No | `eastus` | Azure region for the Automation Account |
| `StopTimeUTC` | No | `17:00` | UTC time (HH:mm) for daily stop |
| `StartTimeUTC` | No | `03:00` | UTC time (HH:mm) for daily start |

### What the Deployment Script Does (13 Steps)

#### Step 1: Create Automation Account
```powershell
az automation account create --name <AutomationAccountName> --resource-group <ResourceGroupName> --location <Location> --sku Free
```
Creates the Azure Automation Account with Free tier SKU.

#### Step 2: Enable System Managed Identity
```
PATCH /automationAccounts/{name}?api-version=2023-11-01
Body: {"identity":{"type":"SystemAssigned"}}
```
Enables a system-assigned managed identity on the automation account. This identity is used by the runbook to authenticate to Azure.

#### Step 3: Get Managed Identity Principal ID
```
GET /automationAccounts/{name}?api-version=2023-11-01
Query: identity.principalId
```
Retrieves the service principal object ID of the managed identity for role assignment.

#### Step 4: Assign Contributor Role on AKS Cluster
```powershell
az role assignment create --assignee-object-id <principalId> --role Contributor --scope <aksResourceId>
```
Grants the automation account's identity permission to start/stop the AKS cluster. Scoped specifically to the AKS resource (least-privilege).

#### Step 5: Import Az.Accounts Module
```
PUT /automationAccounts/{name}/modules/Az.Accounts?api-version=2023-11-01
Body: {"properties":{"contentLink":{"uri":"https://www.powershellgallery.com/api/v2/package/Az.Accounts"}}}
```
Imports the Az.Accounts PowerShell module (required for `Connect-AzAccount`). Waits 90 seconds for import to complete.

#### Step 6: Import Az.Aks Module
```
PUT /automationAccounts/{name}/modules/Az.Aks?api-version=2023-11-01
Body: {"properties":{"contentLink":{"uri":"https://www.powershellgallery.com/api/v2/package/Az.Aks"}}}
```
Imports the Az.Aks module (provides `Start-AzAksCluster` and `Stop-AzAksCluster`). Waits 90 seconds for import to complete.

#### Step 7: Create Runbook
```powershell
az automation runbook create --name AKS-StartStop-<ClusterName> --type PowerShell
```
Creates an empty PowerShell runbook in the automation account.

#### Step 8: Upload Runbook Content
```powershell
az automation runbook replace-content --name AKS-StartStop-<ClusterName> --content @AKS-StartStop-Runbook.ps1
```
Uploads the runbook script code from the local file.

#### Step 9: Publish Runbook
```powershell
az automation runbook publish --name AKS-StartStop-<ClusterName>
```
Publishes the runbook so it can be scheduled and executed.

#### Step 10: Create Stop Schedule
```powershell
az automation schedule create --name "AKS-Stop-Schedule" --frequency Day --interval 1 --start-time "<tomorrow>T<StopTimeUTC>:00Z"
```
Creates a daily schedule at the configured stop time.

#### Step 11: Create Start Schedule
```powershell
az automation schedule create --name "AKS-Start-Schedule" --frequency Day --interval 1 --start-time "<tomorrow>T<StartTimeUTC>:00Z"
```
Creates a daily schedule at the configured start time.

#### Step 12: Link Stop Schedule to Runbook
```
PUT /automationAccounts/{name}/jobSchedules/{guid}?api-version=2023-11-01
Body: {"properties":{"schedule":{"name":"AKS-Stop-Schedule"},"runbook":{"name":"..."},"parameters":{"Action":"Stop","ClusterName":"...","ResourceGroupName":"...","SubscriptionId":"..."}}}
```
Links the stop schedule to the runbook with all required parameters.

#### Step 13: Link Start Schedule to Runbook
```
PUT /automationAccounts/{name}/jobSchedules/{guid}?api-version=2023-11-01
Body: {"properties":{"schedule":{"name":"AKS-Start-Schedule"},"runbook":{"name":"..."},"parameters":{"Action":"Start","ClusterName":"...","ResourceGroupName":"...","SubscriptionId":"..."}}}
```
Links the start schedule to the runbook with all required parameters.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Automation Account                   │
│                    (AutomationAccountName)                    │
│                                                              │
│  ┌──────────────────────┐    ┌────────────────────────────┐ │
│  │  Schedule             │    │  Runbook                    │ │
│  │  AKS-Stop-Schedule    │───▶│  AKS-StartStop-<Cluster>   │ │
│  │  (StopTimeUTC daily)  │    │                             │ │
│  └──────────────────────┘    │  params:                    │ │
│  ┌──────────────────────┐    │    Action = Stop/Start      │ │
│  │  Schedule             │───▶│    ClusterName              │ │
│  │  AKS-Start-Schedule   │    │    ResourceGroupName        │ │
│  │  (StartTimeUTC daily) │    │    SubscriptionId           │ │
│  └──────────────────────┘    └────────────────────────────┘ │
│                                                              │
│  ┌──────────────────────┐                                    │
│  │  Managed Identity     │──── Contributor ────┐             │
│  │  (System Assigned)    │                     │             │
│  └──────────────────────┘                     ▼             │
└────────────────────────────────────────────────┼─────────────┘
                                                 │
                                    ┌────────────▼────────────┐
                                    │   AKS Cluster            │
                                    │   (AksClusterName)       │
                                    │   (ResourceGroupName)    │
                                    └──────────────────────────┘
```

---

## Customization

All variables are externalized as script parameters — no need to edit the scripts.

**Example — different cluster with custom schedule:**
```powershell
.\Deploy-AKS-Automation.ps1 `
    -ResourceGroupName "prod-rg" `
    -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -AksClusterName "prod-aks-cluster" `
    -AutomationAccountName "aa-prod-scheduler" `
    -Location "westeurope" `
    -StopTimeUTC "22:00" `
    -StartTimeUTC "05:00"
```

**Common UTC conversions:**
| Local Time | UTC Offset | Stop (10 PM local) | Start (7 AM local) |
|------------|------------|--------------------|-----------------------|
| GST (UAE)  | UTC+4      | 18:00              | 03:00                 |
| IST (India)| UTC+5:30   | 16:30              | 01:30                 |
| CET (EU)   | UTC+1      | 21:00              | 06:00                 |
| EST (US)   | UTC-5      | 03:00 (+1d)        | 12:00                 |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Runbook fails with auth error | Verify managed identity is enabled and has Contributor role on AKS |
| Module import fails | Wait longer (increase the 90s sleep) or check module provisioning state in portal |
| Schedule not triggering | Verify schedule is enabled and linked to runbook in Portal → Automation Account → Schedules |
| `az rest` body parse error | Ensure JSON bodies use file-based `@filename` approach (Windows PowerShell quote-stripping issue) |
| Cluster already stopped/started | The Az commands are idempotent — re-running won't cause errors |

## Monitoring

View job history in the Azure Portal:
1. Navigate to **Automation Account** → your Automation Account name
2. Click **Jobs** to see execution history
3. Click a job to view **Output** and **Errors** streams

---

## Cost Savings

Stopping a cluster deallocates the node VMs. You only pay for:
- OS disk storage (while stopped)
- Any static IPs retained

**Not charged while stopped:** VM compute, load balancer (if no static IPs), egress.

For a typical 3-node Standard_D4s_v3 cluster, this saves ~$10-15/day during off-hours.
