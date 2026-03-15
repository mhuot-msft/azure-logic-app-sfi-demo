// SPDX-License-Identifier: MIT
//
// VNet Flow Log resource — deployed into NetworkWatcherRG
// Called by flow-logs.bicep with scope: resourceGroup('NetworkWatcherRG')

@description('Azure region')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('VNet resource ID')
param vnetId string

@description('Storage account resource ID for flow log data')
param storageId string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Flow log retention in days')
param retentionDays int

@description('Traffic Analytics interval in minutes')
param trafficAnalyticsInterval int

@description('User-assigned managed identity resource ID for flow log storage access')
param identityId string

resource networkWatcher 'Microsoft.Network/networkWatchers@2023-11-01' existing = {
  name: 'NetworkWatcher_${location}'
}

resource flowLog 'Microsoft.Network/networkWatchers/flowLogs@2023-11-01' = {
  name: '${baseName}-flowlog-vnet'
  location: location
  tags: tags
  parent: networkWatcher
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    targetResourceId: vnetId
    storageId: storageId
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    retentionPolicy: {
      days: retentionDays
      enabled: true
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: workspaceId
        trafficAnalyticsInterval: trafficAnalyticsInterval
      }
    }
  }
}

@description('VNet flow log name')
output flowLogName string = flowLog.name
