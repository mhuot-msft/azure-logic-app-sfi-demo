// Copyright 2025 HACS Group
// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('API connection name to attach access policies to')
param connectionName string

@description('Intake Logic App principal ID')
param intakePrincipalId string

@description('Router Logic App principal ID')
param routerPrincipalId string

@description('Azure AD tenant ID')
param tenantId string = subscription().tenantId

resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' existing = {
  name: connectionName
}

resource intakeAccessPolicy 'Microsoft.Web/connections/accessPolicies@2016-06-01' = {
  parent: serviceBusConnection
  name: 'intake-${intakePrincipalId}'
  location: location
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        tenantId: tenantId
        objectId: intakePrincipalId
      }
    }
  }
}

resource routerAccessPolicy 'Microsoft.Web/connections/accessPolicies@2016-06-01' = {
  parent: serviceBusConnection
  name: 'router-${routerPrincipalId}'
  location: location
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        tenantId: tenantId
        objectId: routerPrincipalId
      }
    }
  }
}
