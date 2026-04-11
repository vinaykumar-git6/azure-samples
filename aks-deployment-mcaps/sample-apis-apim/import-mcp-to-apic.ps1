################################################################################
# Import MCP Servers from a registry into Azure API Center
# Usage: .\import-mcp-to-apic.ps1
################################################################################

# ── Configuration ──────────────────────────────────────────────────────────────
$MCP_REGISTRY_URL  = "https://your-mcp-registry.example.com/servers"  # <-- change this
$APIC_SERVICE      = "vinayorg-apic"
$APIC_RG           = "azure-vk-rg"
$APIC_SUBSCRIPTION = "<YOUR-SUBSCRIPTION-ID>"
$LIFECYCLE_STAGE   = "production"   # design | development | testing | preview | production
# ───────────────────────────────────────────────────────────────────────────────

function Slugify($text) {
    # Convert a display name to a safe API ID (lowercase, hyphens, no special chars)
    $text.ToLower() -replace '[^a-z0-9]+', '-' -replace '^-|-$', ''
}

function Parse-Servers($raw) {
    # Handle different registry response shapes:
    #   [ { name, description, url, ... }, ... ]      plain array
    #   { servers: [ ... ] }                           keyed as "servers"
    #   { items: [ ... ] }                             keyed as "items"
    #   { data: [ ... ] }                              keyed as "data"
    #   { value: [ ... ] }                             keyed as "value"
    if ($raw -is [Array]) { return $raw }
    foreach ($key in @('servers','items','data','value','results','tools')) {
        if ($null -ne $raw.$key) { return $raw.$key }
    }
    # Single object — wrap it
    return @($raw)
}

# ── Fetch registry ──────────────────────────────────────────────────────────────
Write-Host "`n🔍 Fetching MCP servers from: $MCP_REGISTRY_URL" -ForegroundColor Cyan

$raw = $null
if (Test-Path $MCP_REGISTRY_URL -ErrorAction SilentlyContinue) {
    # Local JSON file
    $raw = Get-Content $MCP_REGISTRY_URL -Raw | ConvertFrom-Json
} else {
    # Remote URL
    try {
        $raw = Invoke-RestMethod -Uri $MCP_REGISTRY_URL -Method GET -Headers @{ Accept = "application/json" }
    } catch {
        Write-Error "Failed to fetch registry: $_"
        exit 1
    }
}

$servers = Parse-Servers $raw
Write-Host "✅ Found $($servers.Count) MCP server(s)" -ForegroundColor Green

# ── Import each server ──────────────────────────────────────────────────────────
$success = 0
$failed  = 0

foreach ($server in $servers) {
    # Normalise field names across different registry formats
    $name        = $server.name        ?? $server.title       ?? $server.id     ?? "unknown"
    $description = $server.description ?? $server.summary     ?? ""
    $serverUrl   = $server.url         ?? $server.serverUrl   ?? $server.endpoint ?? "https://unknown"
    $version     = $server.version     ?? $server.apiVersion  ?? "1.0"
    $specUrl     = $server.specUrl     ?? $server.openApiUrl  ?? $server.spec    ?? $null

    $apiId      = Slugify $name
    $versionId  = Slugify $version
    if (-not $versionId) { $versionId = "v1" }

    Write-Host "`n━━━ $name ($apiId) ━━━" -ForegroundColor Yellow

    # 1. Create API
    Write-Host "  → Creating API..." -NoNewline
    $result = az apic api create `
        --service-name $APIC_SERVICE `
        --resource-group $APIC_RG `
        --subscription $APIC_SUBSCRIPTION `
        --api-id $apiId `
        --title $name `
        --kind "mcp" `
        --type "rest" `
        $(if ($description) { "--description `"$description`"" }) `
        2>&1

    if ($LASTEXITCODE -ne 0) {
        # API may already exist — try updating instead
        az apic api update `
            --service-name $APIC_SERVICE `
            --resource-group $APIC_RG `
            --subscription $APIC_SUBSCRIPTION `
            --api-id $apiId `
            --title $name `
            $(if ($description) { "--description `"$description`"" }) `
            2>&1 | Out-Null
    }
    Write-Host " done" -ForegroundColor Green

    # 2. Create version
    Write-Host "  → Creating version $versionId..." -NoNewline
    az apic api version create `
        --service-name $APIC_SERVICE `
        --resource-group $APIC_RG `
        --subscription $APIC_SUBSCRIPTION `
        --api-id $apiId `
        --version-id $versionId `
        --title $version `
        --lifecycle-stage $LIFECYCLE_STAGE `
        2>&1 | Out-Null
    Write-Host " done" -ForegroundColor Green

    # 3. Create definition
    Write-Host "  → Creating definition..." -NoNewline
    az apic api definition create `
        --service-name $APIC_SERVICE `
        --resource-group $APIC_RG `
        --subscription $APIC_SUBSCRIPTION `
        --api-id $apiId `
        --version-id $versionId `
        --definition-id "openapi" `
        --title "OpenAPI" `
        2>&1 | Out-Null
    Write-Host " done" -ForegroundColor Green

    # 4. Import spec (if available)
    if ($specUrl) {
        Write-Host "  → Importing spec from $specUrl..." -NoNewline
        try {
            $specContent = Invoke-RestMethod -Uri $specUrl -ErrorAction Stop | ConvertTo-Json -Depth 20
            az apic api definition import-specification `
                --service-name $APIC_SERVICE `
                --resource-group $APIC_RG `
                --subscription $APIC_SUBSCRIPTION `
                --api-id $apiId `
                --version-id $versionId `
                --definition-id "openapi" `
                --format "inline" `
                --specification '{"name":"openapi","version":"3.0.0"}' `
                --value $specContent `
                2>&1 | Out-Null
            Write-Host " done" -ForegroundColor Green
        } catch {
            Write-Host " skipped (could not fetch spec)" -ForegroundColor DarkYellow
        }
    } else {
        # Build a minimal OpenAPI spec from available metadata
        $minimalSpec = @{
            openapi = "3.0.0"
            info = @{ title = $name; description = $description; version = $version }
            servers = @(@{ url = $serverUrl })
            paths = @{}
        } | ConvertTo-Json -Depth 10 -Compress

        az apic api definition import-specification `
            --service-name $APIC_SERVICE `
            --resource-group $APIC_RG `
            --subscription $APIC_SUBSCRIPTION `
            --api-id $apiId `
            --version-id $versionId `
            --definition-id "openapi" `
            --format "inline" `
            --specification '{"name":"openapi","version":"3.0.0"}' `
            --value $minimalSpec `
            2>&1 | Out-Null
        Write-Host "  → Minimal spec generated from metadata" -ForegroundColor DarkCyan
    }

    $success++
}

# ── Summary ─────────────────────────────────────────────────────────────────────
Write-Host "`n✅ Import complete: $success succeeded, $failed failed" -ForegroundColor Cyan
Write-Host "🔗 Portal: https://green-pond-06da1db0f.1.azurestaticapps.net" -ForegroundColor Cyan
