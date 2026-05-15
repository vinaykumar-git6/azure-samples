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
    Deploy Azure Automation Runbook to Start/Stop an AKS cluster on a daily schedule.

.PARAMETER ResourceGroupName
    Resource group for the Automation Account and AKS cluster.

.PARAMETER AutomationAccountName
    Name of the Azure Automation Account to create.

.PARAMETER Location
    Azure region for the Automation Account.

.PARAMETER AksClusterName
    Name of the AKS cluster to schedule start/stop.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER StopTimeUTC
    UTC time for the daily stop schedule (HH:mm format). Default: 17:00 (9 PM GST).

.PARAMETER StartTimeUTC
    UTC time for the daily start schedule (HH:mm format). Default: 03:00 (7 AM GST).

.NOTES
    GST (Gulf Standard Time) = UTC+4
    9 PM GST = 17:00 UTC
    7 AM GST = 03:00 UTC
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$AksClusterName,

    [Parameter(Mandatory = $false)]
    [string]$AutomationAccountName = "aa-aks-scheduler",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $false)]
    [string]$StopTimeUTC = "17:00",

    [Parameter(Mandatory = $false)]
    [string]$StartTimeUTC = "03:00"
)

# Derived Variables
$runbookName = "AKS-StartStop-$AksClusterName"
$runbookFile = "$PSScriptRoot\AKS-StartStop-Runbook.ps1"
$tomorrow = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
$stopStartTime = "${tomorrow}T${StopTimeUTC}:00Z"
$startStartTime = "${tomorrow}T${StartTimeUTC}:00Z"

Write-Host "=== Step 1: Create Automation Account ===" -ForegroundColor Cyan
az automation account create `
    --name $AutomationAccountName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --sku Free

Write-Host "=== Step 2: Enable System Managed Identity ===" -ForegroundColor Cyan
$identityBodyFile = Join-Path $env:TEMP "aa-identity.json"
'{"identity":{"type":"SystemAssigned"}}' | Out-File -FilePath $identityBodyFile -Encoding utf8 -NoNewline
az rest --method PATCH `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$identityBodyFile"

Write-Host "=== Step 3: Get Managed Identity Principal ID ===" -ForegroundColor Cyan
$principalId = az rest --method GET `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName`?api-version=2023-11-01" `
    --query identity.principalId -o tsv

Write-Host "Principal ID: $principalId"

if (-not $principalId) {
    Write-Host "ERROR: Failed to get principal ID. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "=== Step 4: Assign Contributor role on AKS cluster ===" -ForegroundColor Cyan
az role assignment create `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --role "Contributor" `
    --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ContainerService/managedClusters/$AksClusterName"

Write-Host "=== Step 5: Import Az.Accounts module ===" -ForegroundColor Cyan
$moduleBodyFile = Join-Path $env:TEMP "aa-module.json"
'{"properties":{"contentLink":{"uri":"https://www.powershellgallery.com/api/v2/package/Az.Accounts"}}}' | Out-File -FilePath $moduleBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/modules/Az.Accounts`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$moduleBodyFile"

Write-Host "Waiting 90s for Az.Accounts to import..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host "=== Step 6: Import Az.Aks module ===" -ForegroundColor Cyan
'{"properties":{"contentLink":{"uri":"https://www.powershellgallery.com/api/v2/package/Az.Aks"}}}' | Out-File -FilePath $moduleBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/modules/Az.Aks`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$moduleBodyFile"

Write-Host "Waiting 90s for Az.Aks to import..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host "=== Step 7: Create Runbook ===" -ForegroundColor Cyan
az automation runbook create `
    --automation-account-name $AutomationAccountName `
    --resource-group $ResourceGroupName `
    --name $runbookName `
    --type PowerShell `
    --location $Location

Write-Host "=== Step 8: Upload Runbook Content ===" -ForegroundColor Cyan
az automation runbook replace-content `
    --automation-account-name $AutomationAccountName `
    --resource-group $ResourceGroupName `
    --name $runbookName `
    --content @$runbookFile

Write-Host "=== Step 9: Publish Runbook ===" -ForegroundColor Cyan
az automation runbook publish `
    --automation-account-name $AutomationAccountName `
    --resource-group $ResourceGroupName `
    --name $runbookName

Write-Host "=== Step 10: Create Stop Schedule ($StopTimeUTC UTC daily) ===" -ForegroundColor Cyan
az automation schedule create `
    --automation-account-name $AutomationAccountName `
    --resource-group $ResourceGroupName `
    --name "AKS-Stop-Schedule" `
    --frequency Day `
    --interval 1 `
    --start-time $stopStartTime `
    --time-zone "UTC" `
    --description "Stop AKS cluster $AksClusterName at $StopTimeUTC UTC daily"

Write-Host "=== Step 11: Create Start Schedule ($StartTimeUTC UTC daily) ===" -ForegroundColor Cyan
az automation schedule create `
    --automation-account-name $AutomationAccountName `
    --resource-group $ResourceGroupName `
    --name "AKS-Start-Schedule" `
    --frequency Day `
    --interval 1 `
    --start-time $startStartTime `
    --time-zone "UTC" `
    --description "Start AKS cluster $AksClusterName at $StartTimeUTC UTC daily"

Write-Host "=== Step 12: Link Stop Schedule to Runbook ===" -ForegroundColor Cyan
$stopJobScheduleId = [guid]::NewGuid().ToString()
$stopLinkBodyFile = Join-Path $env:TEMP "aa-stop-link.json"
@"
{"properties":{"schedule":{"name":"AKS-Stop-Schedule"},"runbook":{"name":"$runbookName"},"parameters":{"Action":"Stop","ClusterName":"$AksClusterName","ResourceGroupName":"$ResourceGroupName","SubscriptionId":"$SubscriptionId"}}}
"@ | Out-File -FilePath $stopLinkBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/jobSchedules/$stopJobScheduleId`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$stopLinkBodyFile"

Write-Host "=== Step 13: Link Start Schedule to Runbook ===" -ForegroundColor Cyan
$startJobScheduleId = [guid]::NewGuid().ToString()
$startLinkBodyFile = Join-Path $env:TEMP "aa-start-link.json"
@"
{"properties":{"schedule":{"name":"AKS-Start-Schedule"},"runbook":{"name":"$runbookName"},"parameters":{"Action":"Start","ClusterName":"$AksClusterName","ResourceGroupName":"$ResourceGroupName","SubscriptionId":"$SubscriptionId"}}}
"@ | Out-File -FilePath $startLinkBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AutomationAccountName/jobSchedules/$startJobScheduleId`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$startLinkBodyFile"

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "  Cluster: $AksClusterName" -ForegroundColor Green
Write-Host "  Stop:    $StopTimeUTC UTC daily" -ForegroundColor Green
Write-Host "  Start:   $StartTimeUTC UTC daily" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
