#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Apply MCP tools/call policy to the "Customer REST API" APIM API.

.DESCRIPTION
    Reads mcp-getcustomer-policy.xml and sets it as the API-level policy
    on the APIM API named "customer-rest-api". The policy intercepts
    MCP tools/call requests, extracts customerId, calls the real backend
    GET /api/customers/{customerId}, and returns an MCP-formatted response.

.USAGE
    .\apply-mcp-policy.ps1

.NOTES
    Requires: Az PowerShell module (Az.ApiManagement)
    Run:      Connect-AzAccount  before executing this script
#>

# ─── Configuration ────────────────────────────────────────────────────────────
$ResourceGroup  = "azure-vk-rg"
$ApimName       = "apim-dev-0603"
$ApiId          = "customer-rest-api"   # APIM API name/ID (display name: "Customer REST API")
$PolicyFile     = "$PSScriptRoot\mcp-getcustomer-policy.xml"
# ──────────────────────────────────────────────────────────────────────────────

# Verify the policy file exists
if (-not (Test-Path $PolicyFile)) {
    Write-Error "Policy file not found: $PolicyFile"
    exit 1
}

Write-Host "Reading policy from: $PolicyFile" -ForegroundColor Cyan
$policyXml = Get-Content -Path $PolicyFile -Raw

# Get the APIM context
Write-Host "Fetching APIM context for '$ApimName'..." -ForegroundColor Cyan
$apimContext = New-AzApiManagementContext -ResourceGroupName $ResourceGroup `
                                          -ServiceName $ApimName

# Apply the policy at API level (applies to ALL operations under the API,
# including the MCP /mcp endpoint)
Write-Host "Applying policy to API: '$ApiId'..." -ForegroundColor Cyan
Set-AzApiManagementPolicy -Context $apimContext `
                          -ApiId    $ApiId `
                          -Policy   $policyXml `
                          -Format   "rawxml"

if ($LASTEXITCODE -eq 0 -or $?) {
    Write-Host "Policy applied successfully!" -ForegroundColor Green
} else {
    Write-Error "Failed to apply policy. Check the APIM portal for errors."
    exit 1
}

# ─── Verify ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Verifying applied policy..." -ForegroundColor Cyan
$applied = Get-AzApiManagementPolicy -Context $apimContext -ApiId $ApiId
Write-Host $applied -ForegroundColor DarkGray

Write-Host ""
Write-Host "Done. Test the MCP tool call from Azure AI Foundry agent." -ForegroundColor Green
Write-Host ""
Write-Host "Manual test (PowerShell):" -ForegroundColor Yellow
Write-Host @"
`$body = @{
    jsonrpc = "2.0"
    id      = 1
    method  = "tools/call"
    params  = @{
        name      = "getCustomerById"
        arguments = @{ customerId = "C001" }
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod ``
    -Uri     "https://apim-dev-0603.azure-api.net/customer/mcp" ``
    -Method  POST ``
    -Headers @{ "Ocp-Apim-Subscription-Key" = "5eee5cf6d89c49d69716cfa36b156669"; "Content-Type" = "application/json" } ``
    -Body    `$body | ConvertTo-Json -Depth 10
"@ -ForegroundColor DarkYellow
