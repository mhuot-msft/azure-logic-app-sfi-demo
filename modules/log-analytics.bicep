// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

var workspaceName = '${baseName}-law'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-appi'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    RetentionInDays: 30
  }
}

@description('Log Analytics workspace resource ID')
output workspaceId string = workspace.id

@description('Log Analytics workspace name')
output workspaceName string = workspace.name

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights resource ID')
output appInsightsId string = appInsights.id

@description('Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString
