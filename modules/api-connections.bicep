// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Resource tags')
param tags object

@description('Service Bus namespace fully qualified name (e.g., myns.servicebus.windows.net)')
param serviceBusNamespaceFqdn string

var connectionName = 'servicebus-connection'

resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  tags: tags
  properties: any({
    displayName: 'Service Bus (Managed Identity)'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
    }
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: {
        namespaceEndpoint: {
          value: 'sb://${serviceBusNamespaceFqdn}'
        }
      }
    }
  })
}

@description('API connection resource ID')
output connectionId string = serviceBusConnection.id

@description('API connection name')
output connectionName string = serviceBusConnection.name
