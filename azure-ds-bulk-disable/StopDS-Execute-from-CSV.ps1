<#
.DISCLAIMER
    MICROSOFT DISCLAIMER - PROOF OF CONCEPT (POC)

    THIS SCRIPT IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
    PARTICULAR PURPOSE, AND NONINFRINGEMENT. IN NO EVENT SHALL MICROSOFT CORPORATION
    BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF
    CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THIS
    SCRIPT OR THE USE OR OTHER DEALINGS IN THIS SCRIPT.

    This script is a Proof of Concept (POC) and is NOT a supported Microsoft product
    or service. It is provided for demonstration and reference purposes only.

    IMPORTANT:
    - You MUST test and validate this script in a non-production/test environment
      before executing it against any production subscription or resources.
    - The customer assumes full responsibility for reviewing, testing, and validating
      this script prior to production use.
    - Microsoft is not responsible for any data loss, service disruption, or other
      issues that may result from the execution of this script.

.SYNOPSIS
    Removes ALL diagnostic settings from resources listed in a CSV file.
    Handles resource locks (backup, remove, restore) and creates full backups before changes.

.DESCRIPTION
    This script:
    1. Reads a CSV file containing resources (Resource Name, Resource ID, Resource Type, Resource Group, Subscription ID, Subscription Name).
    2. For each resource, backs up all diagnostic settings and locks BEFORE making changes.
    3. Temporarily removes resource-level locks (CanNotDelete / ReadOnly) that block diagnostic setting removal.
    4. Removes ALL diagnostic settings on the resource.
    5. Restores all locks that were temporarily removed.
    6. Produces a detailed log and report of every action taken.

.PARAMETER CsvFilePath
    Path to the input CSV file. Must contain a "Resource ID" column.

.PARAMETER TargetWorkspaceResourceId
    Optional. If specified, only diagnostic settings pointing to this workspace will be removed.
    If omitted, ALL diagnostic settings on each resource will be removed.

.PARAMETER DryRun
    When set (default=$true), the script only reports what it would do. Set to $false to execute changes.

.PARAMETER OutputFolder
    Folder to store backup files and logs. Defaults to a timestamped folder in the current directory.

.PARAMETER SkipLockRestore
    If set, locks will NOT be restored after diagnostic setting removal. USE WITH CAUTION.

.EXAMPLE
    .\StopDS-Execute-from-CSV.ps1 -CsvFilePath ".\diagnostic_settings_resources.csv"

.EXAMPLE
    .\StopDS-Execute-from-CSV.ps1 -CsvFilePath ".\diagnostic_settings_resources.csv" -TargetWorkspaceResourceId "69adeda3-d13f-4a90-9ef9-c9faca022a3a" -DryRun $false
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvFilePath,

    [Parameter(Mandatory = $false)]
    [string]$TargetWorkspaceResourceId,

    [Parameter(Mandatory = $false)]
    [bool]$DryRun = $true,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLockRestore
)

# ============================================================================
# INITIALIZATION
# ============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$scriptVersion = "2.0.0"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not $OutputFolder) {
    $OutputFolder = Join-Path $PSScriptRoot "DiagSettingsRemoval_$timestamp"
}
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

$logFile = Join-Path $OutputFolder "execution_log_$timestamp.log"
$backupDiagFile = Join-Path $OutputFolder "backup_diagnostic_settings_$timestamp.json"
$backupLocksFile = Join-Path $OutputFolder "backup_locks_$timestamp.json"
$reportFile = Join-Path $OutputFolder "removal_report_$timestamp.csv"

# ============================================================================
# LOGGING
# ============================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DRYRUN")]
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARN"    { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        "DRYRUN"  { Write-Host $entry -ForegroundColor Cyan }
        default   { Write-Host $entry }
    }

    $entry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

function Get-DiagSettings {
    param([string]$ResourceId)

    $json = az monitor diagnostic-settings list --resource $ResourceId -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        return @()
    }
    $result = $json | ConvertFrom-Json
    if ($result -is [array]) {
        return $result
    }
    if ($null -ne $result -and ($result.PSObject.Properties.Name -contains 'value')) {
        return $result.value
    }
    return @($result)
}

function Get-ResourceLocks {
    param([string]$ResourceId)

    $json = az lock list --resource $ResourceId -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        return @()
    }
    return ($json | ConvertFrom-Json)
}

function Remove-LockTemporarily {
    param([object]$Lock)

    if ($DryRun) {
        Write-Log "[DRY RUN] Would temporarily remove lock '$($Lock.name)' (Level: $($Lock.level))" -Level DRYRUN
        return $true
    }
    else {
        Write-Log "Removing lock '$($Lock.name)' (Level: $($Lock.level))..."
        az lock delete --ids $Lock.id 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Lock '$($Lock.name)' removed successfully" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Failed to remove lock '$($Lock.name)'" -Level ERROR
            return $false
        }
    }
}

function Restore-Lock {
    param(
        [object]$Lock,
        [string]$ResourceId
    )

    if ($DryRun) {
        Write-Log "[DRY RUN] Would restore lock '$($Lock.name)' (Level: $($Lock.level))" -Level DRYRUN
        return
    }

    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        Write-Log "Restoring lock '$($Lock.name)' (Attempt $attempt/$maxRetries)..."

        $lockArgs = @("lock", "create", "--name", $Lock.name, "--lock-type", $Lock.level, "--resource", $ResourceId)
        if ($Lock.notes) {
            $lockArgs += @("--notes", $Lock.notes)
        }

        az @lockArgs 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Lock '$($Lock.name)' restored successfully" -Level SUCCESS
            return
        }

        Write-Log "Attempt $attempt to restore lock '$($Lock.name)' failed" -Level WARN
        if ($attempt -lt $maxRetries) {
            Start-Sleep -Seconds (2 * $attempt)
        }
        else {
            Write-Log "CRITICAL: Failed to restore lock '$($Lock.name)' after $maxRetries attempts. MANUAL INTERVENTION REQUIRED." -Level ERROR
        }
    }
}

function Remove-DiagSetting {
    param(
        [string]$ResourceId,
        [string]$Name
    )

    if ($DryRun) {
        Write-Log "[DRY RUN] Would remove diagnostic setting '$Name' from $ResourceId" -Level DRYRUN
        return $true
    }
    else {
        az monitor diagnostic-settings delete --resource $ResourceId --name $Name 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Removed diagnostic setting '$Name' from $ResourceId" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "Failed to remove diagnostic setting '$Name' from $ResourceId" -Level ERROR
            return $false
        }
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
try {
    # Validate CSV file
    if (-not (Test-Path $CsvFilePath)) {
        throw "CSV file not found: $CsvFilePath"
    }

    $csvData = Import-Csv -Path $CsvFilePath
    if (-not $csvData -or $csvData.Count -eq 0) {
        throw "CSV file is empty: $CsvFilePath"
    }

    # Validate CSV has required column
    $firstRow = $csvData[0]
    $colNames = $firstRow.PSObject.Properties.Name

    # Find exact column names using precise regex
    $resourceIdColumn = $colNames | Where-Object { $_ -match "^Resource\s*ID$" } | Select-Object -First 1
    $resourceNameColumn = $colNames | Where-Object { $_ -match "^Resource\s*Name$" } | Select-Object -First 1
    $resourceTypeColumn = $colNames | Where-Object { $_ -match "^Resource\s*Type$" } | Select-Object -First 1
    $resourceGroupColumn = $colNames | Where-Object { $_ -match "^Resource\s*Group$" } | Select-Object -First 1
    $subIdColumn = $colNames | Where-Object { $_ -match "^Subscription\s*ID$" } | Select-Object -First 1
    $subNameColumn = $colNames | Where-Object { $_ -match "^Subscription\s*Name$" } | Select-Object -First 1

    if (-not $resourceIdColumn) {
        throw "CSV file must contain a 'Resource ID' column."
    }

    # Banner
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host "  AZURE DIAGNOSTIC SETTINGS REMOVAL (CSV-DRIVEN) v$scriptVersion" -ForegroundColor White
    Write-Host "  Input CSV: $CsvFilePath" -ForegroundColor White
    Write-Host "  Resources to process: $($csvData.Count)" -ForegroundColor White
    if ($TargetWorkspaceResourceId) {
        Write-Host "  Target Workspace: $TargetWorkspaceResourceId (filter active)" -ForegroundColor White
    } else {
        Write-Host "  Target Workspace: ALL diagnostic settings will be removed" -ForegroundColor Yellow
    }
    if ($DryRun) {
        Write-Host "  MODE: DRY RUN (no changes will be made)" -ForegroundColor Cyan
    } else {
        Write-Host "  MODE: EXECUTE (changes WILL be made)" -ForegroundColor Red
    }
    Write-Host "  Output Folder: $OutputFolder" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host ""

    # Verify az CLI is available and logged in
    $account = az account show -o json 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Log "Not logged in to Azure CLI. Please run 'az login' first." -Level ERROR
        throw "Not logged in to Azure CLI."
    }
    Write-Log "Connected as: $($account.user.name)"

    # Resolve workspace: if input looks like a GUID, resolve to full resource ID
    if ($TargetWorkspaceResourceId) {
        $guidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        if ($TargetWorkspaceResourceId -match $guidPattern) {
            Write-Log "Input looks like a workspace GUID (customerId). Resolving to ARM resource ID..."
            $wsJson = az monitor log-analytics workspace list --query "[?customerId=='$TargetWorkspaceResourceId']" -o json 2>$null
            if ($wsJson) {
                $wsResult = $wsJson | ConvertFrom-Json
                if ($wsResult -and $wsResult.Count -gt 0) {
                    $TargetWorkspaceResourceId = $wsResult[0].id
                    Write-Log "Resolved workspace to: $TargetWorkspaceResourceId" -Level SUCCESS
                } else {
                    Write-Log "Could not resolve workspace GUID." -Level ERROR
                    throw "Workspace GUID resolution failed."
                }
            } else {
                throw "Failed to query Log Analytics workspaces."
            }
        }
    }

    # Normalize target workspace for comparison
    $targetLower = if ($TargetWorkspaceResourceId) { $TargetWorkspaceResourceId.ToLower() } else { $null }

    # Tracking
    $allDiagSettingsBackup = @()
    $allLocksBackup = @()
    $reportEntries = @()
    $totalDiagSettingsFound = 0
    $totalDiagSettingsRemoved = 0
    $totalLocksHandled = 0
    $confirmedExecution = $false
    $currentSubId = ""

    $processedCount = 0
    $totalResources = $csvData.Count

    foreach ($row in $csvData) {
        $processedCount++
        $resourceId = $row.$resourceIdColumn
        $resourceName = if ($resourceNameColumn) { $row.$resourceNameColumn } else { "" }
        $resourceType = if ($resourceTypeColumn) { $row.$resourceTypeColumn } else { "" }
        $resourceGroup = if ($resourceGroupColumn) { $row.$resourceGroupColumn } else { "" }
        $subId = if ($subIdColumn) { $row.$subIdColumn } else { "" }
        $subName = if ($subNameColumn) { $row.$subNameColumn } else { "" }

        if (-not $resourceId) {
            Write-Log "[$processedCount/$totalResources] SKIP - Empty Resource ID in row" -Level WARN
            continue
        }

        Write-Log "[$processedCount/$totalResources] Processing: $resourceName ($resourceType)"

        # Switch subscription if needed
        if ($subId -and $subId -ne $currentSubId) {
            az account set --subscription $subId 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Log "[$processedCount/$totalResources] Failed to switch to subscription $subId" -Level ERROR
                continue
            }
            $currentSubId = $subId
            Write-Log "Switched to subscription: $subId ($subName)"
        }

        # Get diagnostic settings
        $diagSettings = Get-DiagSettings -ResourceId $resourceId

        if (-not $diagSettings -or $diagSettings.Count -eq 0) {
            # For storage accounts, still check child resources even if parent has no diag settings
            if ($resourceType -ne "Microsoft.Storage/storageAccounts") {
                Write-Log "[$processedCount/$totalResources] No diagnostic settings found on: $resourceName" -Level WARN
                continue
            } else {
                Write-Log "[$processedCount/$totalResources] No diagnostic settings on parent storage account: $resourceName. Checking child services..." -Level WARN
                $targetDiagSettings = @()
            }
        }

        # Filter by target workspace if specified
        if ($targetLower) {
            $targetDiagSettings = @()
            foreach ($ds in $diagSettings) {
                if (-not ($ds.PSObject.Properties.Name -contains 'workspaceId')) { continue }
                $wsId = $ds.workspaceId
                if ($wsId -and ($wsId.ToLower() -eq $targetLower -or $wsId.ToLower().Contains($targetLower))) {
                    $targetDiagSettings += $ds
                }
            }
        } else {
            $targetDiagSettings = $diagSettings
        }

        if ($targetDiagSettings.Count -eq 0) {
            # For storage accounts, skip parent but still check child resources below
            if ($resourceType -ne "Microsoft.Storage/storageAccounts") {
                Write-Log "[$processedCount/$totalResources] No matching diagnostic settings on: $resourceName" -Level WARN
                continue
            } else {
                Write-Log "[$processedCount/$totalResources] No matching diagnostic settings on parent: $resourceName. Checking child services..."
            }
        }

        $totalDiagSettingsFound += $targetDiagSettings.Count
        Write-Log "[$processedCount/$totalResources] Found $($targetDiagSettings.Count) diagnostic setting(s) to remove on: $resourceName"

        if ($targetDiagSettings.Count -gt 0) {
            # Backup diagnostic settings
            foreach ($ds in $targetDiagSettings) {
                $allDiagSettingsBackup += [PSCustomObject]@{
                    SubscriptionId   = $subId
                    SubscriptionName = $subName
                    ResourceId       = $resourceId
                    ResourceName     = $resourceName
                    ResourceType     = $resourceType
                    ResourceGroup    = $resourceGroup
                    DiagSettingName  = $ds.name
                    WorkspaceId      = $ds.workspaceId
                    FullSettingJson   = ($ds | ConvertTo-Json -Depth 10 -Compress)
                }
            }

            # Check for locks
            $locks = Get-ResourceLocks -ResourceId $resourceId
            $hasLocks = ($locks -and $locks.Count -gt 0)

            if ($hasLocks) {
                Write-Log "[$processedCount/$totalResources] Resource has $($locks.Count) lock(s): $($locks | ForEach-Object { "$($_.name)($($_.level))" } | Join-String -Separator ', ')"
                $totalLocksHandled += $locks.Count

                foreach ($lock in $locks) {
                    $allLocksBackup += [PSCustomObject]@{
                        SubscriptionId   = $subId
                        SubscriptionName = $subName
                        ResourceId       = $resourceId
                        ResourceName     = $resourceName
                        LockId           = $lock.id
                        LockName         = $lock.name
                        LockLevel        = $lock.level
                        LockNotes        = $lock.notes
                    }
                }
            }

            # Confirmation prompt (once, only in execute mode)
            if (-not $DryRun -and -not $confirmedExecution) {
                # Save backups first
                $allDiagSettingsBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupDiagFile -Encoding UTF8
                if ($allLocksBackup.Count -gt 0) {
                    $allLocksBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupLocksFile -Encoding UTF8
                }
                Write-Log "Backups saved to: $OutputFolder" -Level SUCCESS

                Write-Host ""
                Write-Host "================================================================" -ForegroundColor Red
                Write-Host "  WARNING: You are about to modify resources in production!" -ForegroundColor Red
                Write-Host "  Diagnostic settings will be REMOVED." -ForegroundColor Red
                Write-Host "  Resource locks will be temporarily removed and restored." -ForegroundColor Red
                Write-Host "  Backup files saved to: $OutputFolder" -ForegroundColor Red
                Write-Host "================================================================" -ForegroundColor Red
                Write-Host ""

                $confirm = Read-Host "Type YES-PROCEED to continue, or anything else to abort"
                if ($confirm -ne "YES-PROCEED") {
                    Write-Log "User aborted execution." -Level WARN
                    throw "Execution aborted by user."
                }
                Write-Log "User confirmed execution."
                $confirmedExecution = $true
            }

            # Step 1: Remove locks if present
            $removedLocks = @()
            if ($hasLocks) {
                foreach ($lock in $locks) {
                    $removed = Remove-LockTemporarily -Lock $lock
                    if ($removed) { $removedLocks += $lock }
                }
            }

            # Step 2: Remove diagnostic settings
            foreach ($ds in $targetDiagSettings) {
                $success = Remove-DiagSetting -ResourceId $resourceId -Name $ds.name

                if ($success) { $totalDiagSettingsRemoved++ }

                $reportEntries += [PSCustomObject]@{
                    Timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                    SubscriptionId   = $subId
                    SubscriptionName = $subName
                    ResourceId       = $resourceId
                    ResourceName     = $resourceName
                    ResourceType     = $resourceType
                    ResourceGroup    = $resourceGroup
                    DiagSettingName  = $ds.name
                    HadLocks         = $hasLocks
                    LocksRemoved     = $removedLocks.Count
                    Action           = if ($DryRun) { "DRY_RUN" } else { if ($success) { "REMOVED" } else { "FAILED" } }
                }
            }

            # Step 3: Restore locks
            if ($removedLocks.Count -gt 0 -and -not $SkipLockRestore) {
                foreach ($lock in $removedLocks) {
                    Restore-Lock -Lock $lock -ResourceId $resourceId
                }
            }
        }

        Write-Log "[$processedCount/$totalResources] DONE: $resourceName"

        # Step 4: For Storage Accounts, also process child services (blob, file, queue, table)
        if ($resourceType -eq "Microsoft.Storage/storageAccounts") {
            $childServices = @("blobServices/default", "fileServices/default", "queueServices/default", "tableServices/default")
            foreach ($childSvc in $childServices) {
                $childResourceId = "$resourceId/$childSvc"
                $childTypeName = ($childSvc -split '/')[0]

                $childDiagSettings = Get-DiagSettings -ResourceId $childResourceId
                if (-not $childDiagSettings -or $childDiagSettings.Count -eq 0) { continue }

                # Filter by target workspace if specified
                if ($targetLower) {
                    $childTargetSettings = @()
                    foreach ($ds in $childDiagSettings) {
                        if (-not ($ds.PSObject.Properties.Name -contains 'workspaceId')) { continue }
                        $wsId = $ds.workspaceId
                        if ($wsId -and ($wsId.ToLower() -eq $targetLower -or $wsId.ToLower().Contains($targetLower))) {
                            $childTargetSettings += $ds
                        }
                    }
                } else {
                    $childTargetSettings = $childDiagSettings
                }

                if ($childTargetSettings.Count -eq 0) { continue }

                $totalDiagSettingsFound += $childTargetSettings.Count
                Write-Log "[$processedCount/$totalResources] Found $($childTargetSettings.Count) diagnostic setting(s) on child: $resourceName/$childTypeName"

                # Backup child diagnostic settings
                foreach ($ds in $childTargetSettings) {
                    $allDiagSettingsBackup += [PSCustomObject]@{
                        SubscriptionId   = $subId
                        SubscriptionName = $subName
                        ResourceId       = $childResourceId
                        ResourceName     = "$resourceName/$childTypeName"
                        ResourceType     = "Microsoft.Storage/storageAccounts/$childSvc"
                        ResourceGroup    = $resourceGroup
                        DiagSettingName  = $ds.name
                        WorkspaceId      = $ds.workspaceId
                        FullSettingJson   = ($ds | ConvertTo-Json -Depth 10 -Compress)
                    }
                }

                # Remove child diagnostic settings
                foreach ($ds in $childTargetSettings) {
                    $success = Remove-DiagSetting -ResourceId $childResourceId -Name $ds.name

                    if ($success) { $totalDiagSettingsRemoved++ }

                    $reportEntries += [PSCustomObject]@{
                        Timestamp        = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        SubscriptionId   = $subId
                        SubscriptionName = $subName
                        ResourceId       = $childResourceId
                        ResourceName     = "$resourceName/$childTypeName"
                        ResourceType     = "Microsoft.Storage/storageAccounts/$childSvc"
                        ResourceGroup    = $resourceGroup
                        DiagSettingName  = $ds.name
                        HadLocks         = $false
                        LocksRemoved     = 0
                        Action           = if ($DryRun) { "DRY_RUN" } else { if ($success) { "REMOVED" } else { "FAILED" } }
                    }
                }

                Write-Log "[$processedCount/$totalResources] DONE child: $resourceName/$childTypeName" -Level SUCCESS
            }
        }
    }

    # ============================================================================
    # SAVE OUTPUTS
    # ============================================================================
    $allDiagSettingsBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupDiagFile -Encoding UTF8
    Write-Log "Diagnostic settings backup saved: $backupDiagFile"

    if ($allLocksBackup.Count -gt 0) {
        $allLocksBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupLocksFile -Encoding UTF8
        Write-Log "Locks backup saved: $backupLocksFile"
    }

    if ($reportEntries.Count -gt 0) {
        $reportEntries | Export-Csv -Path $reportFile -NoTypeInformation -Encoding UTF8
        Write-Log "Report saved: $reportFile"
    }

    # ============================================================================
    # SUMMARY
    # ============================================================================
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host "  EXECUTION SUMMARY" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor White
    $modeLabel = if ($DryRun) { "DRY RUN" } else { "EXECUTE" }
    $modeColor = if ($DryRun) { "Cyan" } else { "Green" }
    $actionLabel = if ($DryRun) { "to remove" } else { "removed" }
    Write-Host "  Mode:                      $modeLabel" -ForegroundColor $modeColor
    Write-Host "  Resources in CSV:          $totalResources" -ForegroundColor White
    Write-Host "  Diagnostic settings found: $totalDiagSettingsFound" -ForegroundColor White
    Write-Host "  Diagnostic settings ${actionLabel}:  $totalDiagSettingsRemoved" -ForegroundColor White
    Write-Host "  Resource locks handled:    $totalLocksHandled" -ForegroundColor White
    Write-Host "  Backup folder:             $OutputFolder" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host ""

    if ($DryRun) {
        Write-Log "DRY RUN complete. No changes were made. Review the report at: $reportFile" -Level DRYRUN
        Write-Log "To execute, re-run with: -DryRun `$false" -Level DRYRUN
    }
    else {
        Write-Log "Execution complete. All backups saved to: $OutputFolder" -Level SUCCESS
    }
}
catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    throw
}
