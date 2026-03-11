// Licensed under the Apache License, Version 2.0
//
// Azure Logic Apps Healthcare Demo — Patient Referral Routing
// Orchestrator: deploys all modules with correct dependency chain

targetScope = 'resourceGroup'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
param environment string = 'dev'

@description('Publisher email for APIM')
param publisherEmail string

@description('Publisher name for APIM')
param publisherName string = 'Healthcare Demo'

@description('Optional Entra object ID for a user that should receive Grafana Admin access')
param grafanaAdminPrincipalId string = ''

@description('Email address for alert notifications')
param alertEmailAddress string = 'admin@healthcaredemo.com'

@description('VNet address space CIDR')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Azure AD tenant ID for APIM JWT validation (leave empty to skip)')
param apimTenantId string = ''

@description('Connector outbound IP ranges for Service Bus firewall (AzureConnectors service tag for your region)')
param connectorOutboundIpRanges array = []

var suffix = uniqueString(resourceGroup().id)
var baseName = 'hlth-${environment}-${suffix}'
var tags = {
  project: 'healthcare-referral-demo'
  environment: environment
  managedBy: 'bicep'
}

// ──────────────────────────────────────────────
// 1. Log Analytics
// ──────────────────────────────────────────────
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    location: location
    baseName: baseName
    tags: tags
  }
}

// ──────────────────────────────────────────────
// 1b. Virtual Network (SFI Zero Trust — network isolation)
// ──────────────────────────────────────────────
module vnet 'modules/virtual-network.bicep' = {
  name: 'deploy-vnet'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vnetAddressPrefix: vnetAddressPrefix
  }
}

// ──────────────────────────────────────────────
// 2. Service Bus
// ──────────────────────────────────────────────
module serviceBus 'modules/service-bus.bicep' = {
  name: 'deploy-service-bus'
  params: {
    location: location
    baseName: baseName
    tags: tags
    connectorOutboundIpRanges: connectorOutboundIpRanges
  }
}

// ──────────────────────────────────────────────
// 3. Key Vault (depends on Service Bus for connection string)
// ──────────────────────────────────────────────
module keyVault 'modules/key-vault.bicep' = {
  name: 'deploy-key-vault'
  params: {
    location: location
    baseName: baseName
    tags: tags
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    tenantId: subscription().tenantId
  }
}

// ──────────────────────────────────────────────
// 3b. Private Endpoints (SFI Zero Trust — network isolation)
// ──────────────────────────────────────────────
module privateEndpoints 'modules/private-endpoints.bicep' = {
  name: 'deploy-private-endpoints'
  params: {
    location: location
    baseName: baseName
    tags: tags
    privateEndpointSubnetId: vnet.outputs.privateEndpointSubnetId
    vnetId: vnet.outputs.vnetId
    serviceBusNamespaceId: serviceBus.outputs.namespaceId
    keyVaultId: keyVault.outputs.vaultId
  }
}

// ──────────────────────────────────────────────
// 4. API Connections (depends on Service Bus)
// ──────────────────────────────────────────────
module apiConnections 'modules/api-connections.bicep' = {
  name: 'deploy-api-connections'
  params: {
    location: location
    tags: tags
    serviceBusNamespaceFqdn: '${serviceBus.outputs.namespaceName}.servicebus.windows.net'
  }
}

// ──────────────────────────────────────────────
// 5. Logic App: Referral Intake (depends on API Connection)
// ──────────────────────────────────────────────
module intakeLogicApp 'modules/logic-app-intake.bicep' = {
  name: 'deploy-logic-app-intake'
  params: {
    location: location
    baseName: baseName
    tags: tags
    serviceBusConnectionId: apiConnections.outputs.connectionId
    serviceBusConnectionName: apiConnections.outputs.connectionName
  }
}

// ──────────────────────────────────────────────
// 6. Logic App: Referral Router (depends on API Connection)
// ──────────────────────────────────────────────
module routerLogicApp 'modules/logic-app-router.bicep' = {
  name: 'deploy-logic-app-router'
  params: {
    location: location
    baseName: baseName
    tags: tags
    serviceBusConnectionId: apiConnections.outputs.connectionId
    serviceBusConnectionName: apiConnections.outputs.connectionName
  }
}

// ──────────────────────────────────────────────
// 7. Role Assignments — Managed Identity RBAC
// ──────────────────────────────────────────────
module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'deploy-role-assignments'
  params: {
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    keyVaultName: keyVault.outputs.vaultName
    intakePrincipalId: intakeLogicApp.outputs.principalId
    routerPrincipalId: routerLogicApp.outputs.principalId
  }
}

// ──────────────────────────────────────────────
// 8. API Management (depends on Intake Logic App)
// ──────────────────────────────────────────────
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  dependsOn: [intakeLogicApp]
  params: {
    location: location
    baseName: baseName
    tags: tags
    intakeCallbackUrl: listCallbackUrl('${resourceId('Microsoft.Logic/workflows', '${baseName}-intake')}/triggers/manual', '2019-05-01').value
    publisherEmail: publisherEmail
    publisherName: publisherName
    tenantId: apimTenantId
  }
}

// ──────────────────────────────────────────────
// 9. Azure Managed Grafana (depends on Log Analytics)
// ──────────────────────────────────────────────
module grafana 'modules/grafana.bicep' = {
  name: 'deploy-grafana'
  dependsOn: [logAnalytics]
  params: {
    location: location
    baseName: baseName
    tags: tags
    grafanaAdminPrincipalId: grafanaAdminPrincipalId
  }
}

// ──────────────────────────────────────────────
// 10. Diagnostics (depends on all resources)
// ──────────────────────────────────────────────
module diagnostics 'modules/diagnostics.bicep' = {
  name: 'deploy-diagnostics'
  params: {
    workspaceId: logAnalytics.outputs.workspaceId
    intakeLogicAppName: intakeLogicApp.outputs.name
    routerLogicAppName: routerLogicApp.outputs.name
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    keyVaultName: keyVault.outputs.vaultName
    apimName: '${baseName}-apim'
  }
}

// ──────────────────────────────────────────────
// 11. Alerts & Incident Response (SFI Audit + WAF Reliability)
// ──────────────────────────────────────────────
module alerts 'modules/alerts.bicep' = {
  name: 'deploy-alerts'
  params: {
    baseName: baseName
    workspaceId: logAnalytics.outputs.workspaceId
    serviceBusNamespaceName: serviceBus.outputs.namespaceName
    keyVaultName: keyVault.outputs.vaultName
    intakeLogicAppName: intakeLogicApp.outputs.name
    routerLogicAppName: routerLogicApp.outputs.name
    alertEmailAddress: alertEmailAddress
  }
}

// ──────────────────────────────────────────────
// Outputs
// ──────────────────────────────────────────────
@description('APIM gateway URL for testing')
output apimGatewayUrl string = apim.outputs.gatewayUrl

@description('Full referral endpoint URL')
output referralEndpoint string = apim.outputs.referralEndpoint

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Intake Logic App name')
output intakeLogicAppName string = intakeLogicApp.outputs.name

@description('Router Logic App name')
output routerLogicAppName string = routerLogicApp.outputs.name

@description('Grafana dashboard URL')
output grafanaEndpoint string = grafana.outputs.endpoint

@description('Grafana resource name')
output grafanaName string = grafana.outputs.name
