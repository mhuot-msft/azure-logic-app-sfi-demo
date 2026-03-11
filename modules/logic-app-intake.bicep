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

var logicAppName = '${baseName}-intake'

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
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              required: [
                'patientId'
                'patientName'
                'referralType'
                'priority'
                'diagnosis'
                'referringProvider'
              ]
              properties: {
                patientId: {
                  type: 'string'
                  description: 'Patient identifier'
                }
                patientName: {
                  type: 'string'
                  description: 'Patient full name'
                }
                referralType: {
                  type: 'string'
                  description: 'Type of referral (e.g., Cardiology, Physical Therapy)'
                }
                priority: {
                  type: 'string'
                  enum: [
                    'urgent'
                    'high'
                    'normal'
                    'low'
                  ]
                  description: 'Referral priority level'
                }
                diagnosis: {
                  type: 'object'
                  properties: {
                    code: {
                      type: 'string'
                      description: 'ICD-10 diagnosis code'
                    }
                    description: {
                      type: 'string'
                      description: 'Diagnosis description'
                    }
                  }
                }
                referringProvider: {
                  type: 'string'
                  description: 'Name of referring provider'
                }
                notes: {
                  type: 'string'
                  description: 'Additional clinical notes'
                }
              }
            }
          }
        }
      }
      actions: {
        Validate_Required_Fields: {
          type: 'If'
          runAfter: {}
          expression: {
            and: [
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'patientId\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'patientId\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'patientName\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'patientName\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'referralType\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'referralType\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'priority\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'priority\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'diagnosis\']?[\'code\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'diagnosis\']?[\'code\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'diagnosis\']?[\'description\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'diagnosis\']?[\'description\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                not: {
                  or: [
                    {
                      equals: [
                        '@triggerBody()?[\'referringProvider\']'
                        null
                      ]
                    }
                    {
                      equals: [
                        '@triggerBody()?[\'referringProvider\']'
                        ''
                      ]
                    }
                  ]
                }
              }
              {
                or: [
                  {
                    equals: [
                      '@triggerBody()?[\'priority\']'
                      'urgent'
                    ]
                  }
                  {
                    equals: [
                      '@triggerBody()?[\'priority\']'
                      'high'
                    ]
                  }
                  {
                    equals: [
                      '@triggerBody()?[\'priority\']'
                      'normal'
                    ]
                  }
                  {
                    equals: [
                      '@triggerBody()?[\'priority\']'
                      'low'
                    ]
                  }
                ]
              }
            ]
          }
          actions: {
            Process_Referral: {
              type: 'Scope'
              runAfter: {}
              actions: {
                Enrich_Metadata: {
                  type: 'Compose'
                  runAfter: {}
                  inputs: {
                    correlationId: '@{guid()}'
                    receivedAt: '@{utcNow()}'
                    status: 'received'
                  }
                }
                Assemble_Clinical_Data: {
                  type: 'Compose'
                  runAfter: {}
                  inputs: {
                    patientId: '@triggerBody()?[\'patientId\']'
                    patientName: '@triggerBody()?[\'patientName\']'
                    referralType: '@triggerBody()?[\'referralType\']'
                    priority: '@triggerBody()?[\'priority\']'
                    diagnosis: '@triggerBody()?[\'diagnosis\']'
                    referringProvider: '@triggerBody()?[\'referringProvider\']'
                    notes: '@triggerBody()?[\'notes\']'
                  }
                }
                Compose_Enriched_Referral: {
                  type: 'Compose'
                  runAfter: {
                    Enrich_Metadata: [
                      'Succeeded'
                    ]
                    Assemble_Clinical_Data: [
                      'Succeeded'
                    ]
                  }
                  inputs: '@union(outputs(\'Enrich_Metadata\'), outputs(\'Assemble_Clinical_Data\'))'
                }
                Send_to_Incoming_Queue: {
                  type: 'ApiConnection'
                  runAfter: {
                    Compose_Enriched_Referral: [
                      'Succeeded'
                    ]
                  }
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
                      }
                    }
                    method: 'post'
                    path: '/@{encodeURIComponent(encodeURIComponent(\'incoming-referrals\'))}/messages'
                    body: {
                      ContentData: '@{base64(string(outputs(\'Compose_Enriched_Referral\')))}'
                      ContentType: 'application/json'
                      Properties: {
                        priority: '@triggerBody()?[\'priority\']'
                        referralType: '@triggerBody()?[\'referralType\']'
                        correlationId: '@outputs(\'Compose_Enriched_Referral\')?[\'correlationId\']'
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
                Response_Success: {
                  type: 'Response'
                  runAfter: {
                    Send_to_Incoming_Queue: [
                      'Succeeded'
                    ]
                  }
                  inputs: {
                    statusCode: 202
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      status: 'accepted'
                      correlationId: '@outputs(\'Compose_Enriched_Referral\')?[\'correlationId\']'
                      message: 'Referral received and queued for processing'
                    }
                  }
                }
              }
            }
            Handle_Processing_Error: {
              type: 'Scope'
              runAfter: {
                Process_Referral: [
                  'Failed'
                  'TimedOut'
                ]
              }
              actions: {
                Response_Processing_Error: {
                  type: 'Response'
                  runAfter: {}
                  inputs: {
                    statusCode: 500
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      status: 'error'
                      message: 'An error occurred while processing the referral. Please retry.'
                    }
                  }
                }
              }
            }
          }
          else: {
            actions: {
              Response_Invalid_Request: {
                type: 'Response'
                runAfter: {}
                inputs: {
                  statusCode: 400
                  headers: {
                    'Content-Type': 'application/json'
                  }
                  body: {
                    status: 'error'
                    message: 'Invalid referral payload. Required fields are missing or priority is invalid.'
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
