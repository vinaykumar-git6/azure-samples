# =============================================================================
# Import All Banking APIs to Azure API Management
# =============================================================================
# APIM Instance : apim-dev-0603
# Resource Group: azure-vk-rg
# Base Path     : /banking/*
# =============================================================================

param(
    [string]$ResourceGroup = "azure-vk-rg",
    [string]$ServiceName   = "apim-dev-0603",
    [string]$SwaggerFolder = $PSScriptRoot
)

# Define API configurations: file name -> (api-id, display-name, path)
$apis = @(
    @{ File = "01-accounts-api.yaml";         ApiId = "accounts-api";         DisplayName = "Accounts API";         Path = "banking/accounts" },
    @{ File = "02-account-activity-api.yaml"; ApiId = "account-activity-api"; DisplayName = "Account Activity API"; Path = "banking/account-activity" },
    @{ File = "03-payments-api.yaml";         ApiId = "payments-api";         DisplayName = "Payments API";         Path = "banking/payments" },
    @{ File = "04-cards-api.yaml";            ApiId = "cards-api";            DisplayName = "Cards Management API"; Path = "banking/cards" },
    @{ File = "05-loans-api.yaml";            ApiId = "loans-api";            DisplayName = "Loans API";            Path = "banking/loans" },
    @{ File = "06-client-profile-api.yaml";   ApiId = "client-profile-api";   DisplayName = "Client Profile API";   Path = "banking/clients" },
    @{ File = "07-beneficiaries-api.yaml";    ApiId = "beneficiaries-api";    DisplayName = "Beneficiaries API";    Path = "banking/beneficiaries" },
    @{ File = "08-fx-rates-api.yaml";         ApiId = "fx-rates-api";         DisplayName = "FX Rates API";         Path = "banking/fx-rates" },
    @{ File = "09-notifications-api.yaml";    ApiId = "notifications-api";    DisplayName = "Notifications API";    Path = "banking/notifications" },
    @{ File = "10-kyc-compliance-api.yaml";   ApiId = "kyc-compliance-api";   DisplayName = "KYC & Compliance API"; Path = "banking/kyc-compliance" }
)

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Importing Banking APIs to APIM" -ForegroundColor Cyan
Write-Host " Instance : $ServiceName" -ForegroundColor Cyan
Write-Host " RG       : $ResourceGroup" -ForegroundColor Cyan
Write-Host " Folder   : $SwaggerFolder" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$total    = $apis.Count
$success  = 0
$failed   = 0
$skipped  = 0

foreach ($api in $apis) {
    $filePath = Join-Path $SwaggerFolder $api.File
    $index    = $apis.IndexOf($api) + 1

    Write-Host "[$index/$total] Importing: $($api.DisplayName)" -ForegroundColor Yellow

    # Check if file exists
    if (-not (Test-Path $filePath)) {
        Write-Host "  SKIPPED - File not found: $($api.File)" -ForegroundColor DarkYellow
        $skipped++
        continue
    }

    try {
        az apim api import `
            --path $api.Path `
            --resource-group $ResourceGroup `
            --service-name $ServiceName `
            --api-id $api.ApiId `
            --specification-format OpenApi `
            --specification-path $filePath `
            --display-name $api.DisplayName `
            --api-type http `
            --protocols https `
            --output none

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  SUCCESS" -ForegroundColor Green
            $success++
        } else {
            Write-Host "  FAILED (exit code: $LASTEXITCODE)" -ForegroundColor Red
            $failed++
        }
    }
    catch {
        Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Import Summary" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Total   : $total" -ForegroundColor White
Write-Host " Success : $success" -ForegroundColor Green
Write-Host " Failed  : $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host " Skipped : $skipped" -ForegroundColor $(if ($skipped -gt 0) { "DarkYellow" } else { "Green" })
Write-Host "=============================================" -ForegroundColor Cyan
