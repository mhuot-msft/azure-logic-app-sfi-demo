// Copyright 2025 HACS Group
// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('Subnet resource ID for VNet integration (outbound traffic)')
param vnetIntegrationSubnetId string

@description('Service Bus namespace FQDN (e.g., myns.servicebus.windows.net)')
param serviceBusNamespaceFqdn string

var logicAppName = '${baseName}-logicapp'
var appServicePlanName = '${baseName}-asp'
var storageName = replace('${baseName}st', '-', '')
var storageNameTruncated = length(storageName) > 24 ? substring(storageName, 0, 24) : storageName

// ──────────────────────────────────────────────
// App Service Plan — Workflow Standard WS1
// ──────────────────────────────────────────────
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    reserved: false
  }
}

// ──────────────────────────────────────────────
// Storage Account — workflow state and artifacts
// ──────────────────────────────────────────────
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageNameTruncated
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// ──────────────────────────────────────────────
// Logic App Standard — single site hosting both workflows
// ──────────────────────────────────────────────
resource logicApp 'Microsoft.Web/sites@2024-04-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    virtualNetworkSubnetId: vnetIntegrationSubnetId
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      functionsRuntimeScaleMonitoringEnabled: true
      minimumElasticInstanceCount: 1
      vnetRouteAllEnabled: true
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: logicAppName
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'APP_KIND'
          value: 'workflowapp'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
          name: 'serviceBus_fullyQualifiedNamespace'
          value: serviceBusNamespaceFqdn
        }
      ]
    }
  }
}

@description('Logic App Standard managed identity principal ID')
output principalId string = logicApp.identity.principalId

@description('Logic App Standard resource ID')
output resourceId string = logicApp.id

@description('Logic App Standard name')
output name string = logicApp.name

@description('Logic App Standard default hostname')
output defaultHostname string = logicApp.properties.defaultHostName

@description('Storage account name')
output storageAccountName string = storage.name
