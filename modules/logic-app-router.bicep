// Licensed under the Apache License, Version 2.0

@description('Azure region for resources')
param location string

@description('Base name for resources')
param baseName string

@description('Resource tags')
param tags object

@description('Service Bus API connection resource ID')
param serviceBusConnectionId string

@description('Service Bus API connection name')
param serviceBusConnectionName string

var logicAppName = '${baseName}-router'

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        When_a_message_is_received_in_a_queue: {
          type: 'ApiConnection'
          recurrence: {
            frequency: 'Second'
            interval: 30
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/@{encodeURIComponent(encodeURIComponent(\'incoming-referrals\'))}/messages/head'
            queries: {
              queueType: 'Main'
            }
          }
        }
      }
      actions: {
        Parse_Message: {
          type: 'ParseJson'
          runAfter: {}
          inputs: {
            content: '@base64ToString(triggerBody()?[\'ContentData\'])'
            schema: {
              type: 'object'
              properties: {
                correlationId: { type: 'string' }
                receivedAt: { type: 'string' }
                patientId: { type: 'string' }
                patientName: { type: 'string' }
                referralType: { type: 'string' }
                priority: { type: 'string' }
                diagnosis: {
                  type: 'object'
                  properties: {
                    code: { type: 'string' }
                    description: { type: 'string' }
                  }
                }
                referringProvider: { type: 'string' }
                notes: { type: 'string' }
                status: { type: 'string' }
              }
            }
          }
        }
        Check_Priority: {
          type: 'If'
          runAfter: {
            Parse_Message: [
              'Succeeded'
            ]
          }
          expression: {
            or: [
              {
                equals: [
                  '@body(\'Parse_Message\')?[\'priority\']'
                  'urgent'
                ]
              }
              {
                equals: [
                  '@body(\'Parse_Message\')?[\'priority\']'
                  'high'
                ]
              }
            ]
          }
          actions: {
            Send_to_Urgent_Queue: {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/@{encodeURIComponent(encodeURIComponent(\'urgent-referrals\'))}/messages'
                body: {
                  ContentData: '@{base64(string(body(\'Parse_Message\')))}'
                  ContentType: 'application/json'
                  Properties: {
                    priority: '@body(\'Parse_Message\')?[\'priority\']'
                    correlationId: '@body(\'Parse_Message\')?[\'correlationId\']'
                    routedAt: '@{utcNow()}'
                  }
                }
                retryPolicy: {
                  count: 3
                  interval: 'PT10S'
                  type: 'exponential'
                  minimumInterval: 'PT10S'
                  maximumInterval: 'PT1H'
                }
              }
            }
          }
          else: {
            actions: {
              Send_to_Standard_Queue: {
                type: 'ApiConnection'
                inputs: {
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
                    }
                  }
                  method: 'post'
                  path: '/@{encodeURIComponent(encodeURIComponent(\'standard-referrals\'))}/messages'
                  body: {
                    ContentData: '@{base64(string(body(\'Parse_Message\')))}'
                    ContentType: 'application/json'
                    Properties: {
                      priority: '@body(\'Parse_Message\')?[\'priority\']'
                      correlationId: '@body(\'Parse_Message\')?[\'correlationId\']'
                      routedAt: '@{utcNow()}'
                    }
                  }
                  retryPolicy: {
                    count: 3
                    interval: 'PT10S'
                    type: 'exponential'
                    minimumInterval: 'PT10S'
                    maximumInterval: 'PT1H'
                  }
                }
              }
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            connectionId: serviceBusConnectionId
            connectionName: serviceBusConnectionName
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'servicebus')
          }
        }
      }
    }
  }
}

@description('Logic App managed identity principal ID')
output principalId string = logicApp.identity.principalId

@description('Logic App resource ID')
output resourceId string = logicApp.id

@description('Logic App name')
output name string = logicApp.name
