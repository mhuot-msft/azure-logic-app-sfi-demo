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

@description('Deploy Azure Bastion + jumpbox VM for demo access to private resources')
param deployBastion bool = true

@secure()
@description('Admin password for the jumpbox VM (required when deployBastion is true)')
param jumpboxAdminPassword string = ''

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
    grafanaId: grafana.outputs.resourceId
    logicAppId: logicAppStandard.outputs.resourceId
  }
}

// ──────────────────────────────────────────────
// 4. Logic App Standard (replaces Consumption intake + router + API connections)
//    VNet-integrated — connects to Service Bus via private endpoint
// ──────────────────────────────────────────────
module logicAppStandard 'modules/logic-app-standard.bicep' = {
  name: 'deploy-logic-app-standard'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vnetIntegrationSubnetId: vnet.outputs.logicAppsSubnetId
    serviceBusNamespaceFqdn: '${serviceBus.outputs.namespaceName}.servicebus.windows.net'
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
    intakePrincipalId: logicAppStandard.outputs.principalId
    routerPrincipalId: logicAppStandard.outputs.principalId
  }
}

// ──────────────────────────────────────────────
// 8. API Management (depends on Intake Logic App)
// ──────────────────────────────────────────────
module apim 'modules/apim.bicep' = {
  name: 'deploy-apim'
  dependsOn: [privateEndpoints]
  params: {
    location: location
    baseName: baseName
    tags: tags
    intakeCallbackUrl: 'https://${logicAppStandard.outputs.defaultHostname}/api/intake/triggers/manual/invoke?api-version=2022-05-01'
    publisherEmail: publisherEmail
    publisherName: publisherName
    tenantId: apimTenantId
    subnetId: vnet.outputs.apimSubnetId
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
    intakeLogicAppName: logicAppStandard.outputs.name
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
    intakeLogicAppName: logicAppStandard.outputs.name
    alertEmailAddress: alertEmailAddress
  }
}

// ──────────────────────────────────────────────
// 12. NSG Flow Logs + Traffic Analytics (SFI — network visibility)
// ──────────────────────────────────────────────
module flowLogs 'modules/flow-logs.bicep' = {
  name: 'deploy-flow-logs'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vnetId: vnet.outputs.vnetId
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

// ──────────────────────────────────────────────
// 13. Azure Bastion + Jumpbox VM (demo access to private resources)
// ──────────────────────────────────────────────
module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'deploy-bastion'
  params: {
    location: location
    baseName: baseName
    tags: tags
    vnetId: vnet.outputs.vnetId
    jumpboxSubnetId: vnet.outputs.jumpboxSubnetId
    adminPassword: jumpboxAdminPassword
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
output logicAppStandardName string = logicAppStandard.outputs.name

@description('Logic App Standard hostname')
output logicAppHostname string = logicAppStandard.outputs.defaultHostname

@description('Grafana dashboard URL')
output grafanaEndpoint string = grafana.outputs.endpoint

@description('Grafana resource name')
output grafanaName string = grafana.outputs.name

@description('Jumpbox VM name (empty if bastion not deployed)')
output jumpboxVmName string = deployBastion ? bastion.outputs.vmName : 'not-deployed'
