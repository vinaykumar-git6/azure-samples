# =============================================================================
# Enable Mock Response Policies on All Banking APIs in APIM
# =============================================================================
# This adds a mock-response policy to each API so APIM returns the example
# data from the swagger instead of forwarding to a (non-existent) backend.
# =============================================================================

param(
    [string]$ResourceGroup = "azure-vk-rg",
    [string]$ServiceName   = "apim-dev-0603"
)

$apis = @(
    "accounts-api",
    "account-activity-api",
    "payments-api",
    "cards-api",
    "loans-api",
    "client-profile-api",
    "beneficiaries-api",
    "fx-rates-api",
    "notifications-api",
    "kyc-compliance-api"
)

# Mock response policy XML
# ---------------------------------------------------------------
# Uses a custom header "X-Mock-Status" to control which response code
# is returned. If not provided, defaults to the first success response.
#
# Usage:
#   No header       → returns the default success response (200/201)
#   X-Mock-Status: 400 → returns 400 Bad Request mock
#   X-Mock-Status: 401 → returns 401 Unauthorized mock
#   X-Mock-Status: 403 → returns 403 Forbidden mock
#   X-Mock-Status: 404 → returns 404 Not Found mock
#   X-Mock-Status: 409 → returns 409 Conflict mock
#   X-Mock-Status: 422 → returns 422 Unprocessable Entity mock
#   X-Mock-Status: 429 → returns 429 Too Many Requests mock
#   X-Mock-Status: 500 → returns 500 Internal Server Error mock
# ---------------------------------------------------------------
$policyXml = @'
<policies>
    <inbound>
        <base />
        <choose>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "400")">
                <mock-response status-code="400" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "401")">
                <mock-response status-code="401" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "403")">
                <mock-response status-code="403" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "404")">
                <mock-response status-code="404" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "409")">
                <mock-response status-code="409" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "422")">
                <mock-response status-code="422" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "429")">
                <mock-response status-code="429" content-type="application/json" />
            </when>
            <when condition="@(context.Request.Headers.ContainsKey("X-Mock-Status") && context.Request.Headers["X-Mock-Status"].First() == "500")">
                <mock-response status-code="500" content-type="application/json" />
            </when>
            <otherwise>
                <mock-response status-code="@(context.Request.Method == "POST" ? "201" : "200")" content-type="application/json" />
            </otherwise>
        </choose>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
'@

# Write policy to temp file
$policyFile = Join-Path $env:TEMP "apim-mock-policy.xml"
$policyXml | Out-File -FilePath $policyFile -Encoding utf8 -Force

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Applying Mock Response Policies" -ForegroundColor Cyan
Write-Host " Instance : $ServiceName" -ForegroundColor Cyan
Write-Host " RG       : $ResourceGroup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$total   = $apis.Count
$success = 0
$failed  = 0

foreach ($apiId in $apis) {
    $index = $apis.IndexOf($apiId) + 1
    Write-Host "[$index/$total] Applying mock policy to: $apiId" -ForegroundColor Yellow

    try {
        # Get all operations for this API (use JSON for reliable parsing)
        $operationsJson = az apim api operation list `
            --resource-group $ResourceGroup `
            --service-name $ServiceName `
            --api-id $apiId `
            -o json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAILED - Could not list operations: $operationsJson" -ForegroundColor Red
            $failed++
            continue
        }

        $operations = $operationsJson | ConvertFrom-Json
        $opCount = 0

        foreach ($op in $operations) {
            $opName = $op.name
            if ([string]::IsNullOrWhiteSpace($opName)) { continue }

            Write-Host "    -> $($op.method.ToUpper()) $($op.urlTemplate) [$opName]" -ForegroundColor Gray

            az apim api operation policy create `
                --resource-group $ResourceGroup `
                --service-name $ServiceName `
                --api-id $apiId `
                --operation-id $opName `
                --xml-file $policyFile `
                --output none 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                $opCount++
            } else {
                Write-Host "      WARN - policy failed for $opName" -ForegroundColor DarkYellow
            }
        }

        Write-Host "  SUCCESS - $opCount operations configured" -ForegroundColor Green
        $success++
    }
    catch {
        Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

# Clean up temp file
Remove-Item $policyFile -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Mock Policy Summary" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Total APIs : $total" -ForegroundColor White
Write-Host " Success    : $success" -ForegroundColor Green
Write-Host " Failed     : $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "=============================================" -ForegroundColor Cyan
