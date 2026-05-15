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
    Identifies Azure resources with diagnostic settings forwarding to a specified Log Analytics / Sentinel workspace
    and exports the inventory to a CSV file.

.DESCRIPTION
    This script:
    1. Enumerates all resources in the subscription(s) that have diagnostic settings pointing to the target workspace.
    2. Exports a CSV file with: Resource Name, Resource ID, Resource Type, Resource Group, Subscription ID, Subscription Name.

.PARAMETER TargetWorkspaceResourceId
    The full ARM resource ID OR the workspace ID (GUID) of the Log Analytics workspace to identify resources for.

.PARAMETER SubscriptionIds
    One or more subscription IDs to process. If omitted, uses the current az CLI subscription.

.PARAMETER OutputFolder
    Folder to store the CSV output. Defaults to a timestamped folder in the current directory.

.EXAMPLE
    .\StopDS-CSV-CLI.ps1 -TargetWorkspaceResourceId "69adeda3-d13f-4a90-9ef9-c9faca022a3a" -SubscriptionIds "7d1e8453-2920-4f6d-9a6e-bc7005c10a22"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetWorkspaceResourceId,

    [Parameter(Mandatory = $false)]
    [string[]]$SubscriptionIds,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$ResourceType,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder
)

# ============================================================================
# INITIALIZATION
# ============================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$scriptVersion = "2.0.0"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not $OutputFolder) {
    $OutputFolder = Join-Path $PSScriptRoot "DiagSettings_Inventory_$timestamp"
}
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

$logFile = Join-Path $OutputFolder "execution_log_$timestamp.log"
$csvFile = Join-Path $OutputFolder "diagnostic_settings_resources_$timestamp.csv"

# ============================================================================
# LOGGING
# ============================================================================
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    switch ($Level) {
        "ERROR"   { Write-Host $entry -ForegroundColor Red }
        "WARN"    { Write-Host $entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        default   { Write-Host $entry }
    }

    $entry | Out-File -FilePath $logFile -Append -Encoding UTF8
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Get-ResourceGroupFromId {
    param([string]$ResourceId)
    if ($ResourceId -match '/resourceGroups/([^/]+)') {
        return $Matches[1]
    }
    return ""
}

function Get-AllResources {
    param([string]$SubId)

    $cmdArgs = @("resource", "list", "--subscription", $SubId)
    $filterDesc = ""
    if ($ResourceGroupName) {
        $cmdArgs += @("--resource-group", $ResourceGroupName)
        $filterDesc += " RG='$ResourceGroupName'"
    }
    if ($ResourceType) {
        $cmdArgs += @("--resource-type", $ResourceType)
        $filterDesc += " Type='$ResourceType'"
    }
    $cmdArgs += @("-o", "json")

    $scopeMsg = if ($filterDesc) { "(Filter:$filterDesc)" } else { "(all resources)" }
    Write-Log "Fetching resources in subscription $SubId $scopeMsg..."
    $json = az @cmdArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Write-Log "Error fetching resources in subscription $SubId (ExitCode: $LASTEXITCODE)" -Level ERROR
        return @()
    }
    $resources = $json | ConvertFrom-Json
    Write-Log "Found $($resources.Count) resources in subscription $SubId"
    return $resources
}

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

# ============================================================================
# MAIN EXECUTION
# ============================================================================
try {
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host "  AZURE DIAGNOSTIC SETTINGS INVENTORY SCRIPT v$scriptVersion" -ForegroundColor White
    Write-Host "  Target Workspace: $TargetWorkspaceResourceId" -ForegroundColor White
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

    # Determine subscriptions
    if (-not $SubscriptionIds -or $SubscriptionIds.Count -eq 0) {
        $SubscriptionIds = @($account.id)
        Write-Log "No subscription specified. Using current: $($SubscriptionIds[0])"
    }

    # Resolve workspace: if input looks like a GUID, resolve to full resource ID
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
                Write-Log "Could not resolve workspace GUID '$TargetWorkspaceResourceId'. Ensure it exists in an accessible subscription." -Level ERROR
                throw "Workspace GUID resolution failed."
            }
        } else {
            Write-Log "Failed to query Log Analytics workspaces." -Level ERROR
            throw "Workspace GUID resolution failed."
        }
    }

    # Normalize target for comparison
    $targetLower = $TargetWorkspaceResourceId.ToLower()

    # CSV output collection
    $csvEntries = @()
    $totalDiagSettingsFound = 0

    foreach ($subId in $SubscriptionIds) {
        Write-Log "========== Processing subscription: $subId =========="

        az account set --subscription $subId 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to switch to subscription $subId" -Level ERROR
            continue
        }

        # Get subscription name
        $subInfo = az account show --subscription $subId -o json 2>$null | ConvertFrom-Json
        $subName = if ($subInfo) { $subInfo.name } else { "" }
        Write-Log "Subscription Name: $subName"

        # Get all resources
        $resources = Get-AllResources -SubId $subId

        if ($resources.Count -eq 0) {
            Write-Log "No resources found in subscription $subId. Skipping." -Level WARN
            continue
        }

        $processedCount = 0
        $totalResources = $resources.Count
        $loopStartTime = Get-Date

        foreach ($resource in $resources) {
            $processedCount++
            $resourceId = $resource.id

            # Progress logging every 50 resources
            if ($processedCount % 50 -eq 0) {
                $elapsed = (Get-Date) - $loopStartTime
                $rate = [math]::Round($processedCount / $elapsed.TotalMinutes, 1)
                Write-Log "Progress: $processedCount/$totalResources ($rate resources/min) | Matched: $totalDiagSettingsFound"
            }

            # Get diagnostic settings
            $diagSettings = Get-DiagSettings -ResourceId $resourceId

            if (-not $diagSettings -or $diagSettings.Count -eq 0) {
                continue
            }

            # Filter to settings targeting our workspace
            foreach ($ds in $diagSettings) {
                $wsId = $ds.workspaceId
                Write-Log "[DEBUG] DiagSetting '$($ds.name)' workspaceId = '$wsId' | Comparing to target = '$targetLower'"
                if ($wsId -and ($wsId.ToLower() -eq $targetLower -or $wsId.ToLower().Contains($targetLower))) {
                    $totalDiagSettingsFound++
                    $resourceGroup = Get-ResourceGroupFromId -ResourceId $resourceId

                    $csvEntries += [PSCustomObject]@{
                        "Resource Name"    = $resource.name
                        "Resource ID"      = $resourceId
                        "Resource Type"    = $resource.type
                        "Resource Group"   = $resourceGroup
                        "Subscription ID"  = $subId
                        "Subscription Name" = $subName
                    }

                    Write-Log "MATCH: $($resource.name) ($($resource.type)) in RG: $resourceGroup" -Level SUCCESS
                }
            }
        }

        $loopElapsed = (Get-Date) - $loopStartTime
        Write-Log "Subscription $subId complete. Processed $processedCount resources in $([math]::Round($loopElapsed.TotalMinutes, 2)) minutes"
    }

    # ============================================================================
    # EXPORT CSV
    # ============================================================================
    if ($csvEntries.Count -gt 0) {
        # Deduplicate (a resource may have multiple diag settings pointing to same workspace)
        $uniqueEntries = $csvEntries | Sort-Object "Resource ID" -Unique
        $uniqueEntries | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
        Write-Log "CSV exported: $csvFile ($($uniqueEntries.Count) unique resources)" -Level SUCCESS
    }
    else {
        Write-Log "No resources found with diagnostic settings targeting the specified workspace." -Level WARN
    }

    # ============================================================================
    # SUMMARY
    # ============================================================================
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host "  INVENTORY SUMMARY" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host "  Subscriptions processed:   $($SubscriptionIds.Count)" -ForegroundColor White
    Write-Host "  Total diagnostic settings: $totalDiagSettingsFound" -ForegroundColor White
    Write-Host "  Unique resources in CSV:   $(if ($csvEntries.Count -gt 0) { ($csvEntries | Sort-Object 'Resource ID' -Unique).Count } else { 0 })" -ForegroundColor White
    Write-Host "  CSV File:                  $csvFile" -ForegroundColor White
    Write-Host "============================================================================" -ForegroundColor White
    Write-Host ""
}
catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
    throw
}
