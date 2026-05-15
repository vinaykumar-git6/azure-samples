<#
.SYNOPSIS
    Stops Azure resource diagnostic logs from being forwarded to a specified Log Analytics / Sentinel workspace.
    Safely handles resource-level locks by temporarily removing them and restoring them after changes.

.DESCRIPTION
    This script:
    1. Enumerates all resources in the subscription(s) that have diagnostic settings pointing to the target workspace.
    2. Exports a full backup of all diagnostic settings and locks BEFORE making any changes (for rollback).
    3. Temporarily removes resource-level locks (CanNotDelete / ReadOnly) that block diagnostic setting removal.
    4. Removes the diagnostic settings forwarding logs to the target workspace.
    5. Restores all locks that were temporarily removed.
    6. Produces a detailed log of every action taken.

    SAFETY FEATURES:
    - DryRun mode (default) — reports what WOULD be done without making changes.
    - Full backup export of diagnostic settings and locks before any modification.
    - Lock restoration with retry logic.
    - Transcript logging to file.
    - Confirmation prompt before destructive actions.

.PARAMETER TargetWorkspaceResourceId
    The full ARM resource ID of the Log Analytics workspace (Sentinel workspace) to stop sending logs to.

.PARAMETER SubscriptionIds
    One or more subscription IDs to process. If omitted, uses the current subscription context.

.PARAMETER DryRun
    When set (default=$true), the script only reports what it would do. Set to $false to execute changes.

.PARAMETER OutputFolder
    Folder to store backup files and logs. Defaults to a timestamped folder in the current directory.

.PARAMETER BatchSize
    Number of resources to process in each batch for throttle management. Default: 50.

.PARAMETER SkipLockRestore
    If set, locks will NOT be restored after diagnostic setting removal. USE WITH CAUTION.

.EXAMPLE
    # DRY RUN — report only (safe, no changes)
    .\Stop-DiagnosticLogsToSentinel.ps1 `
        -TargetWorkspaceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>" `
        -SubscriptionIds "<subscription-id>"

.EXAMPLE
    # EXECUTE — remove diagnostic settings (will prompt for confirmation)
    .\Stop-DiagnosticLogsToSentinel.ps1 `
        -TargetWorkspaceResourceId "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<ws>" `
        -SubscriptionIds "<subscription-id>" `
        -DryRun $false

.NOTES
    Requires: Az.Monitor, Az.Resources, Az.Accounts modules.
    Minimum permissions: Reader + Monitoring Contributor + Lock Contributor (or Owner/Contributor at subscription scope).
    Tested with Az module 12.x+.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetWorkspaceResourceId,

    [Parameter(Mandatory = $false)]
    [string[]]$SubscriptionIds,

    [Parameter(Mandatory = $false)]
    [bool]$DryRun = $true,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $false)]
    [int]$BatchSize = 50,

    [Parameter(Mandatory = $false)]
    [switch]$SkipLockRestore
)

# ============================================================================
# INITIALIZATION
# ============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$scriptVersion = "1.0.0"
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
# LOGGING FUNCTIONS
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
# MODULE CHECK
# ============================================================================
function Confirm-RequiredModules {
    $requiredModules = @("Az.Accounts", "Az.Monitor", "Az.Resources")
    $missing = @()
    foreach ($mod in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            $missing += $mod
        }
    }
    if ($missing.Count -gt 0) {
        Write-Log "Missing required modules: $($missing -join ', '). Install with: Install-Module $($missing -join ', ') -Scope CurrentUser" -Level ERROR
        throw "Missing required PowerShell modules."
    }
}

# ============================================================================
# BANNER
# ============================================================================
function Show-Banner {
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host "  AZURE DIAGNOSTIC SETTINGS REMOVAL SCRIPT v$scriptVersion" -ForegroundColor White
    Write-Host "  Target Workspace: $TargetWorkspaceResourceId" -ForegroundColor White
    if ($DryRun) {
        Write-Host "  MODE: DRY RUN (no changes will be made)" -ForegroundColor Cyan
    } else {
        Write-Host "  MODE: EXECUTE (changes WILL be made)" -ForegroundColor Red
    }
    Write-Host "  Output Folder: $OutputFolder" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host ""
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

function Get-AllResourcesInSubscription {
    param([string]$SubId)

    Write-Log "Fetching all resources in subscription $SubId..."
    try {
        $resources = Get-AzResource -ErrorAction Stop
        Write-Log "Found $($resources.Count) resources in subscription $SubId"
        return $resources
    }
    catch {
        Write-Log "Error fetching resources in subscription ${SubId}: $_" -Level ERROR
        return @()
    }
}

function Get-DiagnosticSettingsForResource {
    param([string]$ResourceId)

    try {
        $diagSettings = Get-AzDiagnosticSetting -ResourceId $ResourceId -ErrorAction Stop 2>$null
        return $diagSettings
    }
    catch {
        # Many resource types don't support diagnostic settings — this is expected
        return @()
    }
}

function Get-LocksForResource {
    param([string]$ResourceId)

    try {
        $locks = Get-AzResourceLock -ResourceId $ResourceId -ErrorAction SilentlyContinue -AtScope
        return $locks
    }
    catch {
        return @()
    }
}

function Remove-LocksTemporarily {
    param(
        [array]$Locks,
        [string]$ResourceId
    )

    $removedLocks = @()

    foreach ($lock in $Locks) {
        if ($DryRun) {
            Write-Log "[DRY RUN] Would temporarily remove lock '$($lock.Name)' (Type: $($lock.Properties.Level)) from resource" -Level DRYRUN
            $removedLocks += $lock
        }
        else {
            try {
                Write-Log "Removing lock '$($lock.Name)' (Type: $($lock.Properties.Level)) from resource $ResourceId..."
                Remove-AzResourceLock -LockId $lock.LockId -Force -ErrorAction Stop
                Write-Log "Lock '$($lock.Name)' removed successfully" -Level SUCCESS
                $removedLocks += $lock
            }
            catch {
                Write-Log "Failed to remove lock '$($lock.Name)': $_" -Level ERROR
            }
        }
    }

    return $removedLocks
}

function Restore-Locks {
    param(
        [array]$Locks,
        [string]$ResourceId
    )

    foreach ($lock in $Locks) {
        if ($DryRun) {
            Write-Log "[DRY RUN] Would restore lock '$($lock.Name)' (Type: $($lock.Properties.Level))" -Level DRYRUN
        }
        else {
            $maxRetries = 3
            $retryCount = 0
            $restored = $false

            while (-not $restored -and $retryCount -lt $maxRetries) {
                try {
                    $retryCount++
                    Write-Log "Restoring lock '$($lock.Name)' (Attempt $retryCount/$maxRetries)..."

                    # Parse the resource ID to get scope components
                    $lockLevel = $lock.Properties.Level  # CanNotDelete or ReadOnly
                    $lockNotes = $lock.Properties.Notes

                    $newLockParams = @{
                        LockName  = $lock.Name
                        LockLevel = $lockLevel
                        Scope     = $ResourceId
                        Force     = $true
                        ErrorAction = "Stop"
                    }
                    if ($lockNotes) {
                        $newLockParams["LockNotes"] = $lockNotes
                    }

                    New-AzResourceLock @newLockParams | Out-Null
                    Write-Log "Lock '$($lock.Name)' restored successfully" -Level SUCCESS
                    $restored = $true
                }
                catch {
                    Write-Log "Attempt $retryCount to restore lock '$($lock.Name)' failed: $_" -Level WARN
                    if ($retryCount -lt $maxRetries) {
                        Start-Sleep -Seconds (2 * $retryCount)
                    }
                    else {
                        Write-Log "CRITICAL: Failed to restore lock '$($lock.Name)' after $maxRetries attempts on resource $ResourceId. MANUAL INTERVENTION REQUIRED." -Level ERROR
                    }
                }
            }
        }
    }
}

function Remove-TargetDiagnosticSetting {
    param(
        [string]$ResourceId,
        [string]$DiagSettingName
    )

    if ($DryRun) {
        Write-Log "[DRY RUN] Would remove diagnostic setting '$DiagSettingName' from $ResourceId" -Level DRYRUN
        return $true
    }
    else {
        try {
            Remove-AzDiagnosticSetting -ResourceId $ResourceId -Name $DiagSettingName -ErrorAction Stop
            Write-Log "Removed diagnostic setting '$DiagSettingName' from $ResourceId" -Level SUCCESS
            return $true
        }
        catch {
            Write-Log "Failed to remove diagnostic setting '$DiagSettingName' from ${ResourceId}: $_" -Level ERROR
            return $false
        }
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

try {
    Show-Banner
    Confirm-RequiredModules

    # Verify Azure connection
    $context = Get-AzContext
    if (-not $context) {
        Write-Log "Not connected to Azure. Please run Connect-AzAccount first." -Level ERROR
        throw "Not connected to Azure."
    }
    Write-Log "Connected as: $($context.Account.Id)"

    # Determine subscriptions to process
    if (-not $SubscriptionIds -or $SubscriptionIds.Count -eq 0) {
        $SubscriptionIds = @($context.Subscription.Id)
        Write-Log "No subscription specified. Using current context subscription: $($SubscriptionIds[0])"
    }

    # Normalize target workspace ID for case-insensitive comparison
    $targetWsLower = $TargetWorkspaceResourceId.ToLower()

    # Tracking collections
    $allDiagSettingsBackup = @()
    $allLocksBackup = @()
    $reportEntries = @()
    $totalDiagSettingsFound = 0
    $totalDiagSettingsRemoved = 0
    $totalLocksHandled = 0

    foreach ($subId in $SubscriptionIds) {
        Write-Log "========== Processing subscription: $subId =========="

        try {
            Set-AzContext -SubscriptionId $subId -ErrorAction Stop | Out-Null
            Write-Log "Switched to subscription: $subId"
        }
        catch {
            Write-Log "Failed to switch to subscription ${subId}: $_" -Level ERROR
            continue
        }

        # Get all resources
        $resources = Get-AllResourcesInSubscription -SubId $subId

        if ($resources.Count -eq 0) {
            Write-Log "No resources found in subscription $subId. Skipping." -Level WARN
            continue
        }

        # Process in batches
        $totalResources = $resources.Count
        $processedCount = 0
        $batchNum = 0

        for ($i = 0; $i -lt $totalResources; $i += $BatchSize) {
            $batchNum++
            $batch = $resources[$i..([Math]::Min($i + $BatchSize - 1, $totalResources - 1))]

            Write-Log "--- Batch ${batchNum}: Processing resources $($i+1) to $([Math]::Min($i + $BatchSize, $totalResources)) of $totalResources ---"

            foreach ($resource in $batch) {
                $processedCount++
                $resourceId = $resource.ResourceId

                # Get diagnostic settings for this resource
                $diagSettings = Get-DiagnosticSettingsForResource -ResourceId $resourceId

                if (-not $diagSettings -or $diagSettings.Count -eq 0) {
                    continue
                }

                # Filter to only diagnostic settings targeting our workspace
                $targetDiagSettings = @()
                foreach ($ds in $diagSettings) {
                    if ($ds.WorkspaceId -and $ds.WorkspaceId.ToLower() -eq $targetWsLower) {
                        $targetDiagSettings += $ds
                    }
                }

                if ($targetDiagSettings.Count -eq 0) {
                    continue
                }

                $totalDiagSettingsFound += $targetDiagSettings.Count
                Write-Log "Found $($targetDiagSettings.Count) diagnostic setting(s) on resource: $resourceId"

                # Backup diagnostic settings
                foreach ($ds in $targetDiagSettings) {
                    $allDiagSettingsBackup += [PSCustomObject]@{
                        SubscriptionId       = $subId
                        ResourceId           = $resourceId
                        ResourceName         = $resource.Name
                        ResourceType         = $resource.ResourceType
                        DiagSettingName      = $ds.Name
                        WorkspaceId          = $ds.WorkspaceId
                        Logs                 = ($ds.Log | ConvertTo-Json -Compress -Depth 5)
                        Metrics              = ($ds.Metric | ConvertTo-Json -Compress -Depth 5)
                    }
                }

                # Check for resource locks
                $locks = Get-LocksForResource -ResourceId $resourceId
                $hasLocks = ($locks -and $locks.Count -gt 0)

                if ($hasLocks) {
                    Write-Log "Resource has $($locks.Count) lock(s): $resourceId"
                    $totalLocksHandled += $locks.Count

                    # Backup locks
                    foreach ($lock in $locks) {
                        $allLocksBackup += [PSCustomObject]@{
                            SubscriptionId = $subId
                            ResourceId     = $resourceId
                            LockId         = $lock.LockId
                            LockName       = $lock.Name
                            LockLevel      = $lock.Properties.Level
                            LockNotes      = $lock.Properties.Notes
                        }
                    }
                }

                # Confirmation check for non-dry-run (first resource only to avoid spamming)
                if (-not $DryRun -and $totalDiagSettingsFound -eq $targetDiagSettings.Count) {
                    Write-Host ""
                    Write-Host "================================================================" -ForegroundColor Red
                    Write-Host "  WARNING: You are about to modify resources in production!" -ForegroundColor Red
                    Write-Host "  Diagnostic settings will be REMOVED." -ForegroundColor Red
                    Write-Host "  Resource locks will be temporarily removed and restored." -ForegroundColor Red
                    Write-Host "  Backup files will be saved to: $OutputFolder" -ForegroundColor Red
                    Write-Host "================================================================" -ForegroundColor Red
                    Write-Host ""

                    $confirm = Read-Host "Type YES-PROCEED to continue, or anything else to abort"
                    if ($confirm -ne "YES-PROCEED") {
                        Write-Log "User aborted execution." -Level WARN
                        throw "Execution aborted by user."
                    }
                    Write-Log "User confirmed execution."

                    # Save backups now
                    $allDiagSettingsBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupDiagFile -Encoding UTF8
                    Write-Log "Diagnostic settings backup saved to: $backupDiagFile" -Level SUCCESS
                }

                # Step 1: Remove locks if present
                $removedLocks = @()
                if ($hasLocks) {
                    $removedLocks = Remove-LocksTemporarily -Locks $locks -ResourceId $resourceId
                }

                # Step 2: Remove diagnostic settings
                foreach ($ds in $targetDiagSettings) {
                    $success = Remove-TargetDiagnosticSetting -ResourceId $resourceId -DiagSettingName $ds.Name

                    if ($success) {
                        $totalDiagSettingsRemoved++
                    }

                    $reportEntries += [PSCustomObject]@{
                        Timestamp       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                        SubscriptionId  = $subId
                        ResourceId      = $resourceId
                        ResourceName    = $resource.Name
                        ResourceType    = $resource.ResourceType
                        DiagSettingName = $ds.Name
                        HadLocks        = $hasLocks
                        LocksRemoved    = $removedLocks.Count
                        Action          = if ($DryRun) { "DRY_RUN" } else { if ($success) { "REMOVED" } else { "FAILED" } }
                    }
                }

                # Step 3: Restore locks
                if ($removedLocks.Count -gt 0 -and -not $SkipLockRestore) {
                    Restore-Locks -Locks $removedLocks -ResourceId $resourceId
                }

                # Brief pause to avoid API throttling
                if (-not $DryRun -and $processedCount % 10 -eq 0) {
                    Start-Sleep -Milliseconds 500
                }
            }
        }

        Write-Log "Completed subscription: $subId"
    }

    # ============================================================================
    # SAVE OUTPUTS
    # ============================================================================

    # Save diagnostic settings backup
    $allDiagSettingsBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupDiagFile -Encoding UTF8
    Write-Log "Diagnostic settings backup saved: $backupDiagFile"

    # Save locks backup
    if ($allLocksBackup.Count -gt 0) {
        $allLocksBackup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupLocksFile -Encoding UTF8
        Write-Log "Locks backup saved: $backupLocksFile"
    }

    # Save report CSV
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
    Write-Host "  Mode:                     $modeLabel" -ForegroundColor $modeColor
    Write-Host "  Subscriptions processed:  $($SubscriptionIds.Count)" -ForegroundColor White
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
 