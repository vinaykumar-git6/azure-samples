################################################################################
# register-to-apic.ps1
#
# Register (or update) ONE MCP server into Azure API Center.
# Called by the ADO pipeline as:
#   pwsh register-to-apic.ps1 `
#       -ApiId           "my-weather-mcp" `
#       -ApiTitle        "My Weather MCP" `
#       -SpecFile        "openapi.json" `
#       -VersionId       "v1" `
#       -ApicService     "vinayorg-apic" `
#       -ApicRg          "azure-vk-rg" `
#       -LifecycleStage  "production"
################################################################################

param (
    [Parameter(Mandatory)][string] $ApiId,           # URL-safe ID, e.g. weather-mcp
    [Parameter(Mandatory)][string] $ApiTitle,         # Display name
    [Parameter(Mandatory)][string] $SpecFile,         # Path to OpenAPI / MCP spec file
    [Parameter(Mandatory)][string] $ApicService,      # APIC service name
    [Parameter(Mandatory)][string] $ApicRg,           # Resource group
    [string] $VersionId       = "v1",
    [string] $DefinitionId    = "openapi",
    [string] $LifecycleStage  = "production",         # design | development | testing | preview | production
    [string] $SpecFormat      = "openapi",            # openapi | asyncapi | graphql | wsdl | wadl | other
    [string] $SpecVersion     = "3.0.0",
    [string] $ApiKind         = "rest",               # rest | graphql | grpc | soap | webhook | websocket
    [string] $CustomProperties = ""                   # JSON string of custom properties, e.g. '{"kind":"mcp"}'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ────────────────────────────────────────────────────────────────────
function Info  { param($msg) Write-Host "  [INFO]  $msg" -ForegroundColor Cyan }
function OK    { param($msg) Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Warn  { param($msg) Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
function Fail  { param($msg) Write-Error "  [FAIL]  $msg" }

function Az {
    param([string[]]$Args)
    $result = az @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az $($Args -join ' ') failed: $result"
    }
    return $result
}

function AzJson {
    param([string[]]$Args)
    $json = az @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null   # resource doesn't exist yet — caller decides
    }
    return ($json | ConvertFrom-Json)
}

# ── Shared options ─────────────────────────────────────────────────────────────
$shared = @(
    "--service-name", $ApicService,
    "--resource-group", $ApicRg
)

# ── 1. Ensure APIC extension is installed ─────────────────────────────────────
Info "Checking Azure CLI apic extension..."
az extension add --name apic-extension --upgrade --only-show-errors 2>&1 | Out-Null
OK "Extension ready"

# ── 2. Create or update the API ────────────────────────────────────────────────
Info "Registering API: $ApiId ($ApiTitle)"

$existing = AzJson @("apic", "api", "show", "--api-id", $ApiId) + $shared

if ($null -eq $existing) {
    Info "API '$ApiId' not found — creating..."
    $createArgs = @(
        "apic", "api", "create",
        "--api-id", $ApiId,
        "--title", $ApiTitle,
        "--type", $ApiKind
    ) + $shared

    if ($CustomProperties -ne "") {
        $createArgs += @("--custom-properties", $CustomProperties)
    }

    Az $createArgs | Out-Null
    OK "API created"
} else {
    Info "API '$ApiId' exists — updating title/kind..."
    $updateArgs = @(
        "apic", "api", "update",
        "--api-id", $ApiId,
        "--title", $ApiTitle
    ) + $shared

    if ($CustomProperties -ne "") {
        $updateArgs += @("--custom-properties", $CustomProperties)
    }

    Az $updateArgs | Out-Null
    OK "API updated"
}

# ── 3. Create or update the API version ───────────────────────────────────────
Info "Ensuring version '$VersionId' (lifecycle: $LifecycleStage)..."

$existingVer = AzJson @(
    "apic", "api", "version", "show",
    "--api-id", $ApiId,
    "--version-id", $VersionId
) + $shared

if ($null -eq $existingVer) {
    Az @(
        "apic", "api", "version", "create",
        "--api-id", $ApiId,
        "--version-id", $VersionId,
        "--title", $VersionId,
        "--lifecycle-stage", $LifecycleStage
    ) + $shared | Out-Null
    OK "Version '$VersionId' created"
} else {
    Az @(
        "apic", "api", "version", "update",
        "--api-id", $ApiId,
        "--version-id", $VersionId,
        "--lifecycle-stage", $LifecycleStage
    ) + $shared | Out-Null
    OK "Version '$VersionId' updated"
}

# ── 4. Create or update the API definition ────────────────────────────────────
Info "Ensuring definition '$DefinitionId'..."

$existingDef = AzJson @(
    "apic", "api", "definition", "show",
    "--api-id", $ApiId,
    "--version-id", $VersionId,
    "--definition-id", $DefinitionId
) + $shared

if ($null -eq $existingDef) {
    Az @(
        "apic", "api", "definition", "create",
        "--api-id", $ApiId,
        "--version-id", $VersionId,
        "--definition-id", $DefinitionId,
        "--title", $DefinitionId.ToUpper()
    ) + $shared | Out-Null
    OK "Definition '$DefinitionId' created"
}

# ── 5. Import the specification ────────────────────────────────────────────────
Info "Importing spec from '$SpecFile'..."

if (-not (Test-Path $SpecFile)) {
    Fail "Spec file not found: $SpecFile"
}

$specContent = Get-Content $SpecFile -Raw

Az @(
    "apic", "api", "definition", "import-specification",
    "--api-id", $ApiId,
    "--version-id", $VersionId,
    "--definition-id", $DefinitionId,
    "--format", "inline",
    "--value", $specContent,
    "--specification", "{`"name`":`"$SpecFormat`",`"version`":`"$SpecVersion`"}"
) + $shared | Out-Null

OK "Spec imported successfully"

# ── Done ───────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  DONE: '$ApiTitle' registered in APIC as '$ApiId'" -ForegroundColor Green
Write-Host "  Service : $ApicService  |  RG: $ApicRg" -ForegroundColor Green
Write-Host "  Version : $VersionId   |  Stage: $LifecycleStage" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
