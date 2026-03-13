// Copyright 2025 HACS Group
// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('Subnet resource ID for private endpoints')
param privateEndpointSubnetId string

@description('VNet resource ID for DNS zone links')
param vnetId string

@description('Service Bus namespace resource ID')
param serviceBusNamespaceId string

@description('Key Vault resource ID')
param keyVaultId string

@description('Grafana resource ID')
param grafanaId string

@description('Logic App Standard resource ID')
param logicAppId string

// ──────────────────────────────────────────────
// Private DNS Zones
// ──────────────────────────────────────────────
resource sbPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.servicebus.windows.net'
  location: 'global'
  tags: tags
}

resource kvPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource grafanaPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.grafana.azure.com'
  location: 'global'
  tags: tags
}

resource webPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
  tags: tags
}

resource sbDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sbPrivateDnsZone
  name: '${baseName}-sb-dns-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource kvDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: kvPrivateDnsZone
  name: '${baseName}-kv-dns-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource grafanaDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: grafanaPrivateDnsZone
  name: '${baseName}-grafana-dns-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource webDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: webPrivateDnsZone
  name: '${baseName}-web-dns-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

// ──────────────────────────────────────────────
// Service Bus Private Endpoint
// ──────────────────────────────────────────────
resource sbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${baseName}-pe-sb'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${baseName}-pe-sb-conn'
        properties: {
          privateLinkServiceId: serviceBusNamespaceId
          groupIds: [
            'namespace'
          ]
        }
      }
    ]
  }
}

resource sbPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: sbPrivateEndpoint
  name: 'sb-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'servicebus-config'
        properties: {
          privateDnsZoneId: sbPrivateDnsZone.id
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Key Vault Private Endpoint
// ──────────────────────────────────────────────
resource kvPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${baseName}-pe-kv'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${baseName}-pe-kv-conn'
        properties: {
          privateLinkServiceId: keyVaultId
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource kvPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: kvPrivateEndpoint
  name: 'kv-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault-config'
        properties: {
          privateDnsZoneId: kvPrivateDnsZone.id
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Grafana Private Endpoint
// ──────────────────────────────────────────────
resource grafanaPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${baseName}-pe-grafana'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${baseName}-pe-grafana-conn'
        properties: {
          privateLinkServiceId: grafanaId
          groupIds: [
            'grafana'
          ]
        }
      }
    ]
  }
}

resource grafanaPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: grafanaPrivateEndpoint
  name: 'grafana-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'grafana-config'
        properties: {
          privateDnsZoneId: grafanaPrivateDnsZone.id
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Logic App Private Endpoint
// ──────────────────────────────────────────────
resource logicAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${baseName}-pe-logicapp'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${baseName}-pe-logicapp-conn'
        properties: {
          privateLinkServiceId: logicAppId
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource logicAppPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: logicAppPrivateEndpoint
  name: 'logicapp-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'webapp-config'
        properties: {
          privateDnsZoneId: webPrivateDnsZone.id
        }
      }
    ]
  }
}

@description('Service Bus private endpoint name')
output serviceBusPrivateEndpointName string = sbPrivateEndpoint.name

@description('Key Vault private endpoint name')
output keyVaultPrivateEndpointName string = kvPrivateEndpoint.name

@description('Grafana private endpoint name')
output grafanaPrivateEndpointName string = grafanaPrivateEndpoint.name

@description('Logic App private endpoint name')
output logicAppPrivateEndpointName string = logicAppPrivateEndpoint.name
