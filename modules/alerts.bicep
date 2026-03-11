// Copyright 2025 HACS Group
// Licensed under the Apache License, Version 2.0

@description('Base name for resources')
param baseName string

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Service Bus namespace name')
param serviceBusNamespaceName string

@description('Key Vault name (used in KQL query)')
param keyVaultName string

@description('Intake Logic App name')
param intakeLogicAppName string

@description('Router Logic App name')
param routerLogicAppName string

@description('Email address for alert notifications')
param alertEmailAddress string

// ──────────────────────────────────────────────
// Action Group
// ──────────────────────────────────────────────
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${baseName}-ag-ops'
  location: 'global'
  properties: {
    groupShortName: 'OpsAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'ops-email'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Existing resources for scoping
// ──────────────────────────────────────────────
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' existing = {
  name: serviceBusNamespaceName
}

resource intakeLogicApp 'Microsoft.Logic/workflows@2019-05-01' existing = {
  name: intakeLogicAppName
}

resource routerLogicApp 'Microsoft.Logic/workflows@2019-05-01' existing = {
  name: routerLogicAppName
}

// ──────────────────────────────────────────────
// Service Bus — Dead-letter queue depth alert
// ──────────────────────────────────────────────
resource sbDeadLetterAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-alert-sb-deadletter'
  location: 'global'
  properties: {
    description: 'Dead-lettered messages detected in Service Bus queues'
    severity: 2
    enabled: true
    scopes: [
      serviceBusNamespace.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'DeadLetteredMessages'
          metricName: 'DeadletteredMessages'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Service Bus — Queue depth threshold
// ──────────────────────────────────────────────
resource sbQueueDepthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-alert-sb-queue-depth'
  location: 'global'
  properties: {
    description: 'Service Bus queue depth exceeds threshold — potential processing backlog'
    severity: 3
    enabled: true
    scopes: [
      serviceBusNamespace.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ActiveMessages'
          metricName: 'ActiveMessages'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Key Vault — Unauthorized access attempts
// ──────────────────────────────────────────────
resource kvUnauthorizedAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${baseName}-alert-kv-unauthorized'
  location: resourceGroup().location
  properties: {
    description: 'Unauthorized access attempts detected on Key Vault'
    displayName: 'Key Vault Unauthorized Access'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: 'AzureDiagnostics | where ResourceType == "VAULTS" and ResultType == "Unauthorized" | where ResourceId contains "${keyVaultName}" | summarize count() by bin(TimeGenerated, 5m)'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 3
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ──────────────────────────────────────────────
// Logic App Intake — Failed runs
// ──────────────────────────────────────────────
resource intakeFailedAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-alert-intake-failures'
  location: 'global'
  properties: {
    description: 'Intake Logic App workflow run failures detected'
    severity: 2
    enabled: true
    scopes: [
      intakeLogicApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RunsFailed'
          metricName: 'RunsFailed'
          metricNamespace: 'Microsoft.Logic/workflows'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Maximum'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ──────────────────────────────────────────────
// Logic App Router — Failed runs
// ──────────────────────────────────────────────
resource routerFailedAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-alert-router-failures'
  location: 'global'
  properties: {
    description: 'Router Logic App workflow run failures detected'
    severity: 2
    enabled: true
    scopes: [
      routerLogicApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RunsFailed'
          metricName: 'RunsFailed'
          metricNamespace: 'Microsoft.Logic/workflows'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Maximum'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

@description('Action group resource ID')
output actionGroupId string = actionGroup.id

@description('Action group name')
output actionGroupName string = actionGroup.name
