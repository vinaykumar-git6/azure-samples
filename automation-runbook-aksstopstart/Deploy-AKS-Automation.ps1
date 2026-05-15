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
    Deploy Azure Automation Runbook to Start/Stop AKS cluster aks-vk-with-cilium
    Schedule: Stop at 9 PM GST, Start at 7 AM GST daily

.NOTES
    GST (Gulf Standard Time) = UTC+4
    9 PM GST = 17:00 UTC
    7 AM GST = 03:00 UTC
#>

# Variables
$rgName = "azure-vk-rg"
$automationAccountName = "aa-aks-scheduler"
$location = "eastus"
$aksClusterName = "aks-vk-with-cilium"
$aksResourceGroup = "azure-vk-rg"
$subscriptionId = "7d1e8453-2920-4f6d-9a6e-bc7005c10a22"
$runbookName = "AKS-StartStop-Cilium"
$runbookFile = "$PSScriptRoot\AKS-StartStop-Runbook.ps1"

Write-Host "=== Step 1: Create Automation Account ===" -ForegroundColor Cyan
az automation account create `
    --name $automationAccountName `
    --resource-group $rgName `
    --location $location `
    --sku Free

Write-Host "=== Step 2: Enable System Managed Identity ===" -ForegroundColor Cyan
$identityBodyFile = Join-Path $env:TEMP "aa-identity.json"
'{"identity":{"type":"SystemAssigned"}}' | Out-File -FilePath $identityBodyFile -Encoding utf8 -NoNewline
az rest --method PATCH `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Automation/automationAccounts/$automationAccountName`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$identityBodyFile"

Write-Host "=== Step 3: Get Managed Identity Principal ID ===" -ForegroundColor Cyan
$principalId = az rest --method GET `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Automation/automationAccounts/$automationAccountName`?api-version=2023-11-01" `
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
    --scope "/subscriptions/$subscriptionId/resourceGroups/$aksResourceGroup/providers/Microsoft.ContainerService/managedClusters/$aksClusterName"

Write-Host "=== Step 5: Import Az.Accounts module ===" -ForegroundColor Cyan
$moduleBodyFile = Join-Path $env:TEMP "aa-module.json"
'{"properties":{"contentLink":{"uri":"https://www.powershellgallery.com/api/v2/package/Az.Accounts"}}}' | Out-File -FilePath $moduleBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/modules/Az.Accounts`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$moduleBodyFile"

Write-Host "Waiting 90s for Az.Accounts to import..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host "=== Step 6: Import Az.Aks module ===" -ForegroundColor Cyan
'{"properties":{"contentLink":{"uri":"https://www.powershellgallery.com/api/v2/package/Az.Aks"}}}' | Out-File -FilePath $moduleBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/modules/Az.Aks`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$moduleBodyFile"

Write-Host "Waiting 90s for Az.Aks to import..." -ForegroundColor Yellow
Start-Sleep -Seconds 90

Write-Host "=== Step 7: Create Runbook ===" -ForegroundColor Cyan
az automation runbook create `
    --automation-account-name $automationAccountName `
    --resource-group $rgName `
    --name $runbookName `
    --type PowerShell `
    --location $location

Write-Host "=== Step 8: Upload Runbook Content ===" -ForegroundColor Cyan
az automation runbook replace-content `
    --automation-account-name $automationAccountName `
    --resource-group $rgName `
    --name $runbookName `
    --content @$runbookFile

Write-Host "=== Step 9: Publish Runbook ===" -ForegroundColor Cyan
az automation runbook publish `
    --automation-account-name $automationAccountName `
    --resource-group $rgName `
    --name $runbookName

Write-Host "=== Step 10: Create Stop Schedule (9 PM GST = 17:00 UTC) ===" -ForegroundColor Cyan
az automation schedule create `
    --automation-account-name $automationAccountName `
    --resource-group $rgName `
    --name "AKS-Stop-9PM-GST" `
    --frequency Day `
    --interval 1 `
    --start-time "2026-05-16T17:00:00Z" `
    --time-zone "UTC" `
    --description "Stop AKS cluster at 9 PM GST daily"

Write-Host "=== Step 11: Create Start Schedule (7 AM GST = 03:00 UTC) ===" -ForegroundColor Cyan
az automation schedule create `
    --automation-account-name $automationAccountName `
    --resource-group $rgName `
    --name "AKS-Start-7AM-GST" `
    --frequency Day `
    --interval 1 `
    --start-time "2026-05-16T03:00:00Z" `
    --time-zone "UTC" `
    --description "Start AKS cluster at 7 AM GST daily"

Write-Host "=== Step 12: Link Stop Schedule to Runbook ===" -ForegroundColor Cyan
$stopJobScheduleId = [guid]::NewGuid().ToString()
$stopLinkBodyFile = Join-Path $env:TEMP "aa-stop-link.json"
@"
{"properties":{"schedule":{"name":"AKS-Stop-9PM-GST"},"runbook":{"name":"$runbookName"},"parameters":{"Action":"Stop"}}}
"@ | Out-File -FilePath $stopLinkBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/jobSchedules/$stopJobScheduleId`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$stopLinkBodyFile"

Write-Host "=== Step 13: Link Start Schedule to Runbook ===" -ForegroundColor Cyan
$startJobScheduleId = [guid]::NewGuid().ToString()
$startLinkBodyFile = Join-Path $env:TEMP "aa-start-link.json"
@"
{"properties":{"schedule":{"name":"AKS-Start-7AM-GST"},"runbook":{"name":"$runbookName"},"parameters":{"Action":"Start"}}}
"@ | Out-File -FilePath $startLinkBodyFile -Encoding utf8 -NoNewline
az rest --method PUT `
    --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName/providers/Microsoft.Automation/automationAccounts/$automationAccountName/jobSchedules/$startJobScheduleId`?api-version=2023-11-01" `
    --headers "Content-Type=application/json" `
    --body "@$startLinkBodyFile"

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "  Cluster: $aksClusterName" -ForegroundColor Green
Write-Host "  Stop:    9 PM GST (17:00 UTC) daily" -ForegroundColor Green
Write-Host "  Start:   7 AM GST (03:00 UTC) daily" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
