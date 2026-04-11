// ============================================================
//  apic-mcp.bicepparam
//
//  Developer: fill in API_ID, API_TITLE, and (optionally)
//  versionId / lifecycleStage for each MCP server.
//  Everything else is org-wide and shared.
// ============================================================

using './apic-mcp.bicep'

// ── Org-wide (same for every MCP server in this org) ─────────
param apicServiceName = 'vinayorg-apic'
param workspaceId     = 'default'

// ── Per-server — developer customises these ──────────────────
param apiId           = 'weather-mcp'          // unique URL-safe ID
param apiTitle        = 'Weather MCP Server'   // display name in portal
param apiKind         = 'rest'

param versionId       = 'v1'
param lifecycleStage  = 'development'          // change to 'production' when ready

param definitionId    = 'openapi'
param definitionTitle = 'OpenAPI'

param customProperties = {
  kind: 'mcp'   // marks this API as an MCP server in APIC
}
