// SPDX-License-Identifier: MIT
//
// VNet Flow Logs with Traffic Analytics
// Enables network traffic visibility for SFI compliance and troubleshooting
//
// VNet flow logs replace the deprecated NSG flow logs (blocked since June 2025).
// A single VNet flow log captures traffic across all subnets, providing better
// coverage for APIM ↔ Logic App communication troubleshooting.

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('VNet resource ID to enable flow logs on')
param vnetId string

@description('Log Analytics workspace resource ID for Traffic Analytics')
param workspaceId string

@description('Flow log retention in days')
param retentionDays int = 30

@description('Traffic Analytics processing interval in minutes')
param trafficAnalyticsInterval int = 10

// Storage account for flow log data (separate from app storage)
var storageAccountName = take('${replace(baseName, '-', '')}flow', 24)

resource flowLogStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// User-assigned managed identity for flow log writes to storage (SFI: no shared key access)
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-flowlog-identity'
  location: location
  tags: tags
}

// Grant the managed identity Storage Blob Data Contributor on the flow log storage account
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(flowLogStorage.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: flowLogStorage
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

// Deploy VNet flow logs into NetworkWatcherRG (where the Network Watcher lives)
module flowLogResources 'flow-logs-nw.bicep' = {
  name: 'deploy-flow-log-resources'
  scope: resourceGroup('NetworkWatcherRG')
  params: {
    location: location
    baseName: baseName
    tags: tags
    vnetId: vnetId
    storageId: flowLogStorage.id
    workspaceId: workspaceId
    retentionDays: retentionDays
    trafficAnalyticsInterval: trafficAnalyticsInterval
    identityId: managedIdentity.id
  }
}

@description('Flow log storage account name')
output storageAccountName string = flowLogStorage.name

@description('VNet flow log name')
output flowLogName string = flowLogResources.outputs.flowLogName

@description('Flow log managed identity resource ID')
output managedIdentityId string = managedIdentity.id
