targetScope = 'subscription' // Please Update this based on deploymentScope Variable

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

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

@description('Recovery Service Vault Name')
param rsvName string = 'rsv-builtwithcaffeine-${environmentType}-${locationShortCode}'

//
// Bicep Deployment Variables

var resourceGroupName = 'rg-recovery-service-vault-${environmentType}-${locationShortCode}'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createRecoveryServiceVault 'br/public:avm/res/recovery-services/vault:0.5.1' = {
  name: 'vaultDeployment'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: rsvName
    location: location
    replicationAlertSettings: {
      customEmailAddresses: [
        'test.user@testcompany.com'
      ]
      locale: 'en-US'
      sendToOwners: 'Send'
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
    }
  }
  dependsOn: [
    createResourceGroup
  ]
}
