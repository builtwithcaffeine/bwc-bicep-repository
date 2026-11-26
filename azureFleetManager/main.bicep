targetScope = 'subscription'

param customerName string = 'bwc'

var resourceGroupName = 'rg-x-${customerName}-aks-fleet-${locationShortCode}'

@description('Name of the Azure Kubernetes Fleet.')
param fleetName string = 'fm-${customerName}-dev-${locationShortCode}'

@description('Azure region where the Fleet is deployed.')
param location string = 'westeurope'

@description('Short code for the Azure region.')
param locationShortCode string = 'weu'

@description('Managed identity type for the Fleet.')
@allowed([
  'None'
  'SystemAssigned'
])
param identityType string = 'SystemAssigned'

@description('Tags to apply to the Fleet.')
param tags object = {}

@description('Existing AKS clusters to register as Fleet members.')
@minLength(0)
param members array = []

@description('Name of the Fleet Update Strategy.')
param updateStrategyName string = 'default'

@description('Ordered stages and groups for the Fleet Update Strategy.')
@minLength(0)
param updateStages array = []

//
// Azure Verified Modules
//

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: 'create-resource-group-${locationShortCode}'
  params: {
    name: resourceGroupName
    location: location
  }
}

module createFleetManager './modules/container-service/fleet-manager/main.bicep' = {
  name: 'create-fleet-manager-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    fleetName: fleetName
    location: location
    identityType: identityType
    tags: tags
    members: members
    updateStrategyName: updateStrategyName
    updateStages: updateStages
  }
  dependsOn: [
    createResourceGroup
  ]
}

@description('Resource ID of the Fleet.')
output fleetResourceId string = createFleetManager.outputs.fleetResourceId

@description('Resource IDs of the registered Fleet members.')
output fleetMemberResourceIds array = createFleetManager.outputs.fleetMemberResourceIds

@description('Resource ID of the Fleet Update Strategy, or null when no stages are supplied.')
output updateStrategyResourceId string? = createFleetManager.outputs.?updateStrategyResourceId
