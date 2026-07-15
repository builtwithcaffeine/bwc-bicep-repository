// ============ //
// Parameters   //
// ============ //

@description('Required. Location for guest OS metric alerts. Must match the Azure Monitor Workspace location.')
param location string

@description('Required. The resource ID of the Virtual Machine to monitor.')
param virtualMachineResourceId string

@description('Required. The name of the Virtual Machine (used in alert names).')
param virtualMachineName string

@description('Required. The resource ID of the User Assigned Identity used for PromQL alert queries.')
param userAssignedIdentityResourceId string

@description('Required. The resource ID of the Action Group for alert notifications.')
param actionGroupResourceId string

@description('Optional. Tags of the resource.')
param tags object = {}

// ========= //
// Resources //
// ========= //

// ---- Host Metric Alerts ----

resource alertVmAvailability 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'VM Availability - ${virtualMachineName}'
  location: 'global'
  tags: tags
  properties: {
    description: 'VM is unavailable or not responding'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Metric1'
          metricName: 'VmAvailabilityMetric'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

// ---- Guest OS Metric Alerts (PromQL - requires 2024-03-01-preview API) ----

resource alertCpuUsage 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS CPU Usage - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'CPU usage has exceeded 80% threshold over the last 5 minutes'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'avg_over_time(((sum (irate({"system.cpu.time","state" !~ "idle|iowait|steal"}[2m]))) / (sum (irate({"system.cpu.time"}[2m]))))[5m:]) * 100 > 80'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

resource alertMemoryUsage 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS Memory Usage - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'Available memory has dropped below 1 GB over the last 5 minutes'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'min_over_time((sum ({"system.memory.usage", state=~"free|cached|buffered|slab_reclaimable"}))[5m:]) < (1 * 1024 * 1024 * 1024)'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

resource alertDiskIops 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS Disk IOPS - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'Disk IOPS has exceeded 5000 operations per second over the last 5 minutes'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'max_over_time((sum (irate({"system.disk.operations"}[2m])))[5m:]) > 5000'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

resource alertNetworkIn 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS Network In - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'Total network inbound traffic has exceeded 100 GB over the last day'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'sum_over_time((sum (irate({"system.network.io", direction="receive"}[2m])))[1d:]) > (100 * 1024 * 1024 * 1024)'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

resource alertNetworkOut 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS Network Out - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'Total network outbound traffic has exceeded 50 GB over the last day'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'sum_over_time((sum (irate({"system.network.io", direction="transmit"}[2m])))[1d:]) > (50 * 1024 * 1024 * 1024)'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

resource alertNetworkErrors 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS Network Errors - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'Network errors have exceeded 10 total errors over the last 5 minutes'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'sum_over_time((sum (irate({"system.network.errors"}[2m])))[5m:]) > 10'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

resource alertDiskOperationTime 'Microsoft.Insights/metricAlerts@2024-03-01-preview' = {
  name: 'Guest OS Disk Operation Time - ${virtualMachineName}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  properties: {
    description: 'Average disk operation time has exceeded 100ms over the last 5 minutes'
    severity: 3
    enabled: true
    scopes: [virtualMachineResourceId]
    evaluationFrequency: 'PT1M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.PromQLCriteria'
      allOf: [
        {
          name: 'Metric1'
          query: 'avg_over_time(((sum (irate({"system.disk.operation_time"}[2m]))) / (sum (irate({"system.disk.operations"}[2m]))))[5m:]) * 1000 > 100'
          criterionType: 'StaticThresholdCriterion'
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    resolveConfiguration: {
      autoResolved: true
      timeToResolve: 'PT2M'
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
      }
    ]
  }
}

// ========= //
// Outputs   //
// ========= //

@description('The resource IDs of the deployed metric alerts.')
output alertResourceIds array = [
  alertVmAvailability.id
  alertCpuUsage.id
  alertMemoryUsage.id
  alertDiskIops.id
  alertNetworkIn.id
  alertNetworkOut.id
  alertNetworkErrors.id
  alertDiskOperationTime.id
]
