targetScope = 'subscription'

//
// Imported Parameters

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Environment Type')
param environmentType string

@description('User Deployment Name')
param deployedBy string

@description('Deployment Date')
param deployDate string = utcNow('yyyy-MM-dd')

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

// Module Variables
var number = 8
var resourceGroupName = 'rg${number}-bicep-devcenter-${environmentType}-${locationShortCode}'
var userAssignedIdentityName = 'id${number}-bicep-devcenter-${environmentType}'
var keyvaultName = 'kv${number}-bicep-devcenter-${environmentType}'
var devCenterName = 'dc${number}-bicep-devcenter-${environmentType}'


// [Module] - Resource Group
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// [Module] - Managed Identity
module createManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'createManagedIdentity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: userAssignedIdentityName
    location: location
  }
    dependsOn: [
      createResourceGroup
    ]
}

// [Module] - Key Vaukt
module createKeyVault 'br/public:avm/res/key-vault/vault:0.11.2' = {
  name: 'createKeyVault'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: keyvaultName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [Module] - Dev Center
module createDevCenter 'modules/dev-center/main.bicep' = {
  name: 'createDevCenter'
  scope: resourceGroup(resourceGroupName)
  params: {
    devCenterName: devCenterName
    location: location
    identityType: 'UserAssigned'
    userAssignedIdentityId: createManagedIdentity.outputs.resourceId
    installAzureMonitorAgentEnableStatus: 'Disabled'
    catalogItemSyncEnableStatus: 'Disabled'
    microsoftHostedNetworkEnableStatus: 'Disabled'
    environmentName: ['dev', 'acc', 'prod']
    environmentTags: [
      {
        environment: 'dev'
        tags: {
          environmentType: 'dev'
          deployedBy: deployedBy
          deployedDate: deployDate
        }
      }
      {
        environment: 'acc'
        tags: {
          environmentType: 'acc'
          deployedBy: deployedBy
          deployedDate: deployDate
        }
      }
      {
        environment: 'prod'
        tags: {
          environmentType: 'prod'
          deployedBy: deployedBy
          deployedDate: deployDate
        }
      }
    ]
    tags: tags
  }
    dependsOn: [
      createManagedIdentity
    ]
}

// [Module] - Dev Center Project
module devCenterProject 'modules/dev-center-project/main.bicep' = {
  name: 'createDevCenterProject'
  scope: resourceGroup(resourceGroupName)
  params: {
    devCenterId: createDevCenter.outputs.resourceId
    projectName: 'project${number}-bicep-devcenter-${environmentType}'
    projectDescription: 'bicep-test-code'
    catalogItemSyncTypes: []
    maxDevBoxesPerUser: 0
    location: location
  }
  dependsOn: [
    createDevCenter
  ]
}
