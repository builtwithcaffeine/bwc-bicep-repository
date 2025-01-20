@description('The name of the Dev Center resource.')
param devCenterName string

@description('The location of the Dev Center resource.')
param location string = 'westeurope'

@description('Enable or disable system-assigned or user-assigned identity.')
@allowed([
  'None'
  'SystemAssigned'
  'UserAssigned'
])
param identityType string = 'None' // Default is None, can be 'SystemAssigned' or 'UserAssigned'

param userAssignedIdentityId string = ''

@description('Enable or disable catalog item synchronization.')
@allowed([
  'Enabled'
  'Disabled'
])
param catalogItemSyncEnableStatus string = 'Enabled'

@description('Enable or disable Microsoft-hosted network.')
@allowed([
  'Enabled'
  'Disabled'
])
param microsoftHostedNetworkEnableStatus string = 'Enabled'

@description('Enable or disable installation of Azure Monitor agent.')
@allowed([
  'Enabled'
  'Disabled'
])
param installAzureMonitorAgentEnableStatus string = 'Enabled'

@description('The environment name(s) to create (e.g., dev or an array like [dev, acc, prod]).')
param environmentName array = ['dev'] // Default to ['dev'], can be a single string or an array

@description('Tags to apply to each environment. This is an array where each element is a tag object for each environment.')
param environmentTags array = [] // Default to no environment-specific tags

@description('Tags to apply to resources.')
param tags object = {} // Default to no tags

resource devCenter 'Microsoft.DevCenter/devcenters@2024-08-01-preview' = {
  name: devCenterName
  location: location
  identity: identityType == 'UserAssigned' ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  } : identityType == 'SystemAssigned' ? {
    type: 'SystemAssigned'
  } : null // Default to no identity
  properties: {
    projectCatalogSettings: {
      catalogItemSyncEnableStatus: catalogItemSyncEnableStatus
    }
    networkSettings: {
      microsoftHostedNetworkEnableStatus: microsoftHostedNetworkEnableStatus
    }
    devBoxProvisioningSettings: {
      installAzureMonitorAgentEnableStatus: installAzureMonitorAgentEnableStatus
    }
  }
  tags: tags // Apply tags to devCenter resource
}

// Create a devCenterEnvironment resource for each environment name in the array
resource devCenterEnvironments 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = [for envName in environmentName: {
  parent: devCenter
  name: envName
  properties: {}
  //tags: environmentTags[idx] != null ? environmentTags[idx] : {}
}]

// Outputs
@description('The name of the Dev Center.')
output name string = devCenter.name

@description('The ID of the Dev Center.')
output resourceId string = devCenter.id

@description('The principal ID of the Dev Center.')
output principalId string = devCenter.identity.principalId
