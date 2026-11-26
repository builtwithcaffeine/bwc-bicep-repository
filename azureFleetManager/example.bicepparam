using 'main.bicep'

param fleetName = 'fm-example-weu'
param location = 'westeurope'
param identityType = 'SystemAssigned'
param tags = {
  environment: 'example'
  managedBy: 'bicep'
}

// Replace the placeholder resource IDs with IDs of existing AKS clusters.
param members = [
  {
    name: 'aks-canary-weu'
    clusterResourceId: '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ContainerService/managedClusters/<canary-cluster-name>'
    group: 'canary'
  }
  {
    name: 'aks-prod-weu'
    clusterResourceId: '/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.ContainerService/managedClusters/<production-cluster-name>'
    group: 'production'
  }
]

param updateStrategyName = 'prod-rollout'
param updateStages = [
  {
    name: 'canary'
    groups: [
      {
        name: 'canary'
        maxConcurrency: '1'
      }
    ]
    afterStageWaitInSeconds: 3600
  }
  {
    name: 'production'
    groups: [
      {
        name: 'production'
        maxConcurrency: '1'
      }
    ]
  }
]
