# AKS Start/Stop Automation Runbook

Automated daily start and stop of an AKS cluster using Azure Automation Account with Managed Identity authentication.

## Overview

This solution deploys an Azure Automation Account with a PowerShell runbook that starts and stops an AKS cluster on a daily schedule. It uses a System-Assigned Managed Identity for secure, passwordless authentication — no credentials to manage or rotate.

| Component | Value |
|-----------|-------|
| Automation Account | `aa-aks-scheduler` |
| Runbook | `AKS-StartStop-Cilium` |
| Stop Schedule | 9 PM GST (17:00 UTC) daily |
| Start Schedule | 7 AM GST (03:00 UTC) daily |
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

| Parameter | Type | Values | Description |
|-----------|------|--------|-------------|
| `Action` | String | `Start` / `Stop` | Determines whether to start or stop the cluster |

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
.\Deploy-AKS-Automation.ps1
```

### What the Deployment Script Does (13 Steps)

#### Step 1: Create Automation Account
```powershell
az automation account create --name aa-aks-scheduler --resource-group azure-vk-rg --location eastus --sku Free
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
az automation runbook create --name AKS-StartStop-Cilium --type PowerShell
```
Creates an empty PowerShell runbook in the automation account.

#### Step 8: Upload Runbook Content
```powershell
az automation runbook replace-content --name AKS-StartStop-Cilium --content @AKS-StartStop-Runbook.ps1
```
Uploads the runbook script code from the local file.

#### Step 9: Publish Runbook
```powershell
az automation runbook publish --name AKS-StartStop-Cilium
```
Publishes the runbook so it can be scheduled and executed.

#### Step 10: Create Stop Schedule
```powershell
az automation schedule create --name "AKS-Stop-9PM-GST" --frequency Day --interval 1 --start-time "2026-05-16T17:00:00Z"
```
Creates a daily schedule that triggers at 17:00 UTC (9 PM GST).

#### Step 11: Create Start Schedule
```powershell
az automation schedule create --name "AKS-Start-7AM-GST" --frequency Day --interval 1 --start-time "2026-05-16T03:00:00Z"
```
Creates a daily schedule that triggers at 03:00 UTC (7 AM GST).

#### Step 12: Link Stop Schedule to Runbook
```
PUT /automationAccounts/{name}/jobSchedules/{guid}?api-version=2023-11-01
Body: {"properties":{"schedule":{"name":"AKS-Stop-9PM-GST"},"runbook":{"name":"AKS-StartStop-Cilium"},"parameters":{"Action":"Stop"}}}
```
Links the stop schedule to the runbook with parameter `Action=Stop`.

#### Step 13: Link Start Schedule to Runbook
```
PUT /automationAccounts/{name}/jobSchedules/{guid}?api-version=2023-11-01
Body: {"properties":{"schedule":{"name":"AKS-Start-7AM-GST"},"runbook":{"name":"AKS-StartStop-Cilium"},"parameters":{"Action":"Start"}}}
```
Links the start schedule to the runbook with parameter `Action=Start`.

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Automation Account                   │
│                      (aa-aks-scheduler)                       │
│                                                              │
│  ┌──────────────────────┐    ┌────────────────────────────┐ │
│  │  Schedule             │    │  Runbook                    │ │
│  │  AKS-Stop-9PM-GST    │───▶│  AKS-StartStop-Cilium      │ │
│  │  (17:00 UTC daily)   │    │                             │ │
│  └──────────────────────┘    │  param: Action = Stop/Start │ │
│  ┌──────────────────────┐    │                             │ │
│  │  Schedule             │───▶│  1. Connect-AzAccount       │ │
│  │  AKS-Start-7AM-GST   │    │  2. Stop/Start-AzAksCluster│ │
│  │  (03:00 UTC daily)   │    └────────────────────────────┘ │
│  └──────────────────────┘                                    │
│                                                              │
│  ┌──────────────────────┐                                    │
│  │  Managed Identity     │──── Contributor ────┐             │
│  │  (System Assigned)    │                     │             │
│  └──────────────────────┘                     ▼             │
└────────────────────────────────────────────────┼─────────────┘
                                                 │
                                    ┌────────────▼────────────┐
                                    │   AKS Cluster            │
                                    │   aks-vk-with-cilium     │
                                    │   (azure-vk-rg)          │
                                    └──────────────────────────┘
```

---

## Customization

To use this for a different cluster, update these variables:

**In `Deploy-AKS-Automation.ps1`:**
```powershell
$rgName = "your-resource-group"
$automationAccountName = "your-automation-account"
$location = "your-region"
$aksClusterName = "your-aks-cluster"
$subscriptionId = "your-subscription-id"
```

**In `AKS-StartStop-Runbook.ps1`:**
```powershell
$ClusterName = "your-aks-cluster"
$ResourceGroupName = "your-resource-group"
$SubscriptionId = "your-subscription-id"
```

**To change the schedule times**, modify the `--start-time` values in Steps 10/11:
- Convert your desired time to UTC
- GST = UTC+4, so 9 PM GST = 17:00 UTC, 7 AM GST = 03:00 UTC

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
1. Navigate to **Automation Account** → `aa-aks-scheduler`
2. Click **Jobs** to see execution history
3. Click a job to view **Output** and **Errors** streams

---

## Cost Savings

Stopping a cluster deallocates the node VMs. You only pay for:
- OS disk storage (while stopped)
- Any static IPs retained

**Not charged while stopped:** VM compute, load balancer (if no static IPs), egress.

For a typical 3-node Standard_D4s_v3 cluster, this saves ~$10-15/day during off-hours.
