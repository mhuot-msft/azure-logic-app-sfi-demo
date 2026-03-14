// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('Optional Entra object ID for a user that should receive Grafana Admin role on this Grafana workspace')
param grafanaAdminPrincipalId string = ''

// Grafana workspace names: 2-23 chars, alphanumeric + dashes, must start with letter, end with alphanumeric.
// baseName is ~22 chars so we cannot append a suffix. Build a shorter unique name instead.
var grafanaName = 'grf-${uniqueString(baseName)}'

resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    grafanaMajorVersion: '11'
    publicNetworkAccess: 'Enabled'
    apiKey: 'Enabled'
    deterministicOutboundIP: 'Disabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: []
    }
  }
}

// Grafana needs Monitoring Reader on the resource group to query Azure Monitor metrics
var monitoringReaderRole = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

resource grafanaMonitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, grafana.id, monitoringReaderRole)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRole)
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grafana needs Log Analytics Reader to query workspace logs
var logAnalyticsReaderRole = '73c42c96-874c-492b-b04d-ab87d138a893'

// Built-in role: Grafana Admin
var grafanaAdminRole = '22926164-76b3-42b3-bc55-97df8dab3e41'

resource grafanaLogAnalyticsReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, grafana.id, logAnalyticsReaderRole)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', logAnalyticsReaderRole)
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource grafanaAdminAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(grafanaAdminPrincipalId)) {
  name: guid(grafana.id, grafanaAdminPrincipalId, grafanaAdminRole)
  scope: grafana
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', grafanaAdminRole)
    principalId: grafanaAdminPrincipalId
    principalType: 'User'
  }
}

@description('Grafana dashboard endpoint URL')
output endpoint string = grafana.properties.endpoint

@description('Grafana resource ID')
output resourceId string = grafana.id

@description('Grafana name')
output name string = grafana.name
