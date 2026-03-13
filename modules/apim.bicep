// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('Logic App Intake trigger callback URL')
param intakeCallbackUrl string

@description('Publisher email for APIM')
param publisherEmail string

@description('Publisher name for APIM')
param publisherName string

@description('Azure AD tenant ID for JWT validation (leave empty to skip OAuth)')
param tenantId string = ''

@description('Subnet resource ID for APIM VNet integration')
param subnetId string

var apimName = '${baseName}-apim'

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: subnetId
    }
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: 'referral-api'
  properties: {
    displayName: 'Patient Referral API'
    description: 'API for submitting patient referrals for routing'
    subscriptionRequired: true
    path: 'referrals'
    protocols: [
      'https'
    ]
  }
}

resource postOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'submit-referral'
  properties: {
    displayName: 'Submit Referral'
    method: 'POST'
    urlTemplate: '/submit'
    description: 'Submit a new patient referral for processing and routing'
  }
}

// Store the Logic App callback URL as an APIM Named Value to avoid XML encoding issues
// with SAS query parameters containing & and = characters
resource backendUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'logic-app-callback-url'
  properties: {
    displayName: 'logic-app-callback-url'
    value: intakeCallbackUrl
    secret: true
  }
}

// JWT validation policy fragment — injected when tenantId is provided
var jwtPolicyFragment = !empty(tenantId) ? '<validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized"><openid-config url="${environment().authentication.loginEndpoint}${tenantId}/v2.0/.well-known/openid-configuration" /></validate-jwt>' : ''

resource operationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: postOperation
  name: 'policy'
  dependsOn: [backendUrlNamedValue]
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><rate-limit calls="10" renewal-period="60" />${jwtPolicyFragment}<set-variable name="backendUrl" value="{{logic-app-callback-url}}" /><send-request mode="copy" response-variable-name="backendResponse" timeout="30" ignore-error="false"><set-url>@((string)context.Variables["backendUrl"])</set-url><set-method>POST</set-method></send-request><return-response response-variable-name="backendResponse" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = {
  parent: apim
  name: 'referral-subscription'
  properties: {
    displayName: 'Referral API Subscription'
    scope: api.id
    state: 'active'
  }
}

@description('APIM gateway URL')
output gatewayUrl string = apim.properties.gatewayUrl

@description('APIM resource ID')
output resourceId string = apim.id

@description('Full referral endpoint URL')
output referralEndpoint string = '${apim.properties.gatewayUrl}/referrals/submit'
