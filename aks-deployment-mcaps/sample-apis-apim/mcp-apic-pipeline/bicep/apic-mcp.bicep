// ============================================================
//  apic-mcp.bicep
//
//  Registers ONE MCP server into an existing Azure API Center.
//  Declaratively manages: API → Version → Definition
//
//  Spec import (import-specification) is a POST action and
//  cannot be expressed in Bicep — handled by the pipeline
//  as a separate `az apic` step after this deployment.
// ============================================================

@description('Name of the existing API Center service')
param apicServiceName string

@description('Workspace ID — use "default" unless you created a custom one')
param workspaceId string = 'default'

@description('URL-safe unique ID for this API in APIC, e.g. weather-mcp')
param apiId string

@description('Display title shown in the API Center portal')
param apiTitle string

@description('API kind: rest | graphql | grpc | soap | webhook | websocket')
@allowed(['rest', 'graphql', 'grpc', 'soap', 'webhook', 'websocket'])
param apiKind string = 'rest'

@description('Version identifier, e.g. v1')
param versionId string = 'v1'

@description('Lifecycle stage for the version')
@allowed(['design', 'development', 'testing', 'preview', 'production', 'deprecated', 'retired'])
param lifecycleStage string = 'development'

@description('Definition identifier, e.g. openapi')
param definitionId string = 'openapi'

@description('Definition display title')
param definitionTitle string = 'OpenAPI'

@description('Custom properties — set kind=mcp to mark as an MCP server')
param customProperties object = {
  kind: 'mcp'
}

// ── Reference existing APIC service (no re-creation) ─────────────────────────
resource apicService 'Microsoft.ApiCenter/services@2024-03-01' existing = {
  name: apicServiceName
}

resource workspace 'Microsoft.ApiCenter/services/workspaces@2024-03-01' existing = {
  parent: apicService
  name: workspaceId
}

// ── API ───────────────────────────────────────────────────────────────────────
resource api 'Microsoft.ApiCenter/services/workspaces/apis@2024-03-01' = {
  parent: workspace
  name: apiId
  properties: {
    title: apiTitle
    kind: apiKind
    customProperties: customProperties
  }
}

// ── Version ───────────────────────────────────────────────────────────────────
resource apiVersion 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-03-01' = {
  parent: api
  name: versionId
  properties: {
    title: versionId
    lifecycleStage: lifecycleStage
  }
}

// ── Definition ────────────────────────────────────────────────────────────────
resource definition 'Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-03-01' = {
  parent: apiVersion
  name: definitionId
  properties: {
    title: definitionTitle
  }
}

// ── Outputs (used by the pipeline's spec-import step) ─────────────────────────
output apiResourceId string = api.id
output versionResourceId string = apiVersion.id
output definitionResourceId string = definition.id

@description('Fully-qualified definition path for az apic import-specification')
output definitionPath string = '${apicServiceName}/workspaces/${workspaceId}/apis/${apiId}/versions/${versionId}/definitions/${definitionId}'
