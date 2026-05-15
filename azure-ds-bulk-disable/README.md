# Azure Diagnostic Settings Bulk Disable Toolkit

A two-script PowerShell toolkit for safely discovering and removing Azure diagnostic settings that forward logs to a specific Log Analytics / Microsoft Sentinel workspace — at scale across multiple subscriptions.

---

## Overview

When decommissioning or migrating a Log Analytics workspace, you need to identify all Azure resources sending diagnostic data to it and remove those forwarding rules. Doing this manually in the portal is impractical for environments with hundreds or thousands of resources.

This toolkit automates the process in two phases:

| Phase | Script | Purpose |
|-------|--------|---------|
| **1 — Inventory** | `StopDS-CSV-LIST.ps1` | Scans subscriptions, finds resources with diagnostic settings pointing to the target workspace, exports a CSV |
| **2 — Execute** | `StopDS-Execute-from-CSV.ps1` | Reads the CSV, backs up settings and locks, removes diagnostic settings (with dry-run support) |

---

## Prerequisites

- **Azure CLI** (`az`) installed and authenticated (`az login`)
- **PowerShell 5.1+** or **PowerShell 7+**
- Appropriate RBAC permissions:
  - `Reader` on subscriptions/resources (for inventory)
  - `Monitoring Contributor` + `Microsoft.Authorization/locks/*` (for execution)

---

## Script 1: StopDS-CSV-LIST.ps1 (Inventory)

### What It Does

1. Accepts a target workspace identifier (full ARM resource ID **or** workspace GUID/customerId)
2. If a GUID is provided, automatically resolves it to the full ARM resource ID via `az monitor log-analytics workspace list`
3. Enumerates resources across one or more subscriptions (with optional resource group and resource type filters)
4. For each resource, queries `az monitor diagnostic-settings list` and checks if any setting forwards to the target workspace
5. Exports matched resources to a timestamped CSV file

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-TargetWorkspaceResourceId` | Yes | Full ARM resource ID or workspace GUID (customerId) of the target Log Analytics workspace |
| `-SubscriptionIds` | No | Array of subscription IDs to scan. Defaults to current `az` subscription |
| `-ResourceGroupName` | No | Filter to only resources in this resource group |
| `-ResourceType` | No | Filter to only resources of this type (e.g., `Microsoft.ApiManagement/service`) |
| `-OutputFolder` | No | Output directory. Defaults to `./DiagSettings_Inventory_<timestamp>/` |

### Usage Examples

```powershell
# Scan all resources in the current subscription using workspace GUID
.\.StopDS-CSV-LIST.ps1 -TargetWorkspaceResourceId "<workspace-customer-id-guid>"

# Scan specific subscription with full ARM resource ID
.\.StopDS-CSV-LIST.ps1 `
    -TargetWorkspaceResourceId "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>" `
    -SubscriptionIds "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Scan only APIM resources in a specific resource group
.\StopDS-CSV-LIST.ps1 `
    -TargetWorkspaceResourceId "<workspace-customer-id-guid>" `
    -SubscriptionIds "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ResourceGroupName "my-resource-group" `
    -ResourceType "Microsoft.ApiManagement/service"

# Scan multiple subscriptions
.\StopDS-CSV-LIST.ps1 `
    -TargetWorkspaceResourceId "<workspace-customer-id-guid>" `
    -SubscriptionIds @("xxxxxxxx-xxxx-xxxx-xxxx-000000000001", "xxxxxxxx-xxxx-xxxx-xxxx-000000000002", "xxxxxxxx-xxxx-xxxx-xxxx-000000000003")
```

### Output

```
DiagSettings_Inventory_20260515-140622/
├── diagnostic_settings_resources_20260515-140622.csv   # Resource inventory
└── execution_log_20260515-140622.log                   # Detailed execution log
```

**CSV Columns:**

| Column | Description |
|--------|-------------|
| Resource Name | Friendly name of the Azure resource |
| Resource ID | Full ARM resource ID |
| Resource Type | Azure resource provider type |
| Resource Group | Resource group name |
| Subscription ID | Subscription GUID |
| Subscription Name | Subscription display name |

---

## Script 2: StopDS-Execute-from-CSV.ps1 (Removal)

### What It Does

1. Reads the inventory CSV produced by Script 1
2. For each resource in the CSV:
   - Backs up all diagnostic settings (full JSON) to a backup file
   - Discovers and backs up any resource-level locks (CanNotDelete / ReadOnly)
   - Optionally filters to only diagnostic settings targeting a specific workspace
   - Temporarily removes locks that would block deletion
   - Removes the target diagnostic settings
   - Restores all temporarily removed locks (with retry logic)
3. Produces a detailed removal report CSV and JSON backup files

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-CsvFilePath` | Yes | Path to the inventory CSV file (from Script 1) |
| `-TargetWorkspaceResourceId` | No | If specified, only removes diagnostic settings pointing to this workspace. If omitted, removes **ALL** diagnostic settings on each resource |
| `-DryRun` | No | Default `$true`. Set to `$false` to actually execute removals |
| `-OutputFolder` | No | Output directory. Defaults to `./DiagSettingsRemoval_<timestamp>/` |
| `-SkipLockRestore` | No | Switch. If set, locks are NOT restored after removal. **Use with caution** |

### Usage Examples

```powershell
# Dry run - see what would be removed (safe, no changes)
.\StopDS-Execute-from-CSV.ps1 -CsvFilePath ".\DiagSettings_Inventory_20260515-140622\diagnostic_settings_resources_20260515-140622.csv"

# Dry run with workspace filter
.\StopDS-Execute-from-CSV.ps1 `
    -CsvFilePath ".\diagnostic_settings_resources.csv" `
    -TargetWorkspaceResourceId "<workspace-customer-id-guid>"

# Execute removal (will prompt for confirmation)
.\StopDS-Execute-from-CSV.ps1 `
    -CsvFilePath ".\diagnostic_settings_resources.csv" `
    -TargetWorkspaceResourceId "<workspace-customer-id-guid>" `
    -DryRun $false
```

### Safety Mechanisms

| Mechanism | Description |
|-----------|-------------|
| **Dry Run by Default** | No changes are made unless you explicitly pass `-DryRun $false` |
| **Interactive Confirmation** | When executing, requires typing `YES-PROCEED` before any changes |
| **Full Backup** | All diagnostic settings and locks are saved as JSON before any modification |
| **Lock Handling** | Locks are temporarily removed and automatically restored with retry logic (3 attempts) |
| **Detailed Logging** | Every action is logged to both console and file |
| **Per-resource Tracking** | A report CSV captures the result of every operation (REMOVED / FAILED / DRY_RUN) |

### Output

```
DiagSettingsRemoval_20260515-150000/
├── backup_diagnostic_settings_20260515-150000.json   # Full backup of all diag settings
├── backup_locks_20260515-150000.json                 # Full backup of all removed locks
├── removal_report_20260515-150000.csv                # Per-action result report
└── execution_log_20260515-150000.log                 # Detailed execution log
```

---

## End-to-End Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: INVENTORY                                              │
│  .\StopDS-CSV-LIST.ps1 -TargetWorkspaceResourceId "<id/guid>"  │
│  → Produces CSV of affected resources                           │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 2: REVIEW                                                 │
│  Open the CSV and verify the list of resources.                 │
│  Remove any rows you do NOT want to process.                    │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 3: DRY RUN                                                │
│  .\StopDS-Execute-from-CSV.ps1 -CsvFilePath ".\output.csv"     │
│  → See exactly what would happen (no changes made)              │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 4: EXECUTE                                                │
│  .\StopDS-Execute-from-CSV.ps1 -CsvFilePath ".\output.csv" \   │
│      -DryRun $false                                             │
│  → Type "YES-PROCEED" when prompted                             │
│  → Diagnostic settings are removed, locks are restored          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Features

- **Workspace GUID Auto-Resolution** — Pass either a full ARM resource ID or the workspace `customerId` GUID; the script resolves it automatically
- **Multi-Subscription Support** — Scan and execute across multiple subscriptions in a single run
- **Resource Filtering** — Narrow scope by resource group and/or resource type for targeted operations
- **Lock-Aware** — Automatically handles `CanNotDelete` and `ReadOnly` locks with backup and restore
- **Case-Insensitive Matching** — Workspace ID comparison is normalized to lowercase
- **Idempotent Dry Run** — Run as many times as needed without side effects
- **Full Audit Trail** — Every action is logged with timestamps for compliance and troubleshooting

---

## Disclaimer

> **MICROSOFT DISCLAIMER — PROOF OF CONCEPT (POC)**
>
> These scripts are provided "AS IS" without warranty of any kind. They are NOT a supported Microsoft product or service. You MUST test and validate in a non-production environment before executing against production resources. Microsoft is not responsible for any data loss, service disruption, or other issues resulting from execution of these scripts.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| "Not logged in to Azure CLI" | `az` session expired | Run `az login` |
| Workspace GUID resolution fails | Workspace not in current subscription scope | Pass `-SubscriptionIds` explicitly or use the full ARM resource ID |
| 0 diagnostic settings found | Workspace ID mismatch (GUID vs ARM path) | Use full ARM resource ID for `TargetWorkspaceResourceId` |
| CSV not saved (0 resources in CSV) | No diagnostic settings on scanned resources point to target | Verify with `az monitor diagnostic-settings list --resource <id>` |
| Lock restore fails after 3 retries | Transient ARM API issue | Manually recreate the lock using info from `backup_locks_*.json` |
