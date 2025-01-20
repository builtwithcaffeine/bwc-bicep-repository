@description('The name of the Dev Center resource.')
param devCenterName string

@description('The location of the Dev Center resource.')
param location string = 'westeurope'

@description('The identity type for the Dev Center resource. Supports None, SystemAssigned, or UserAssigned.')
@allowed([
  'None'
  'SystemAssigned'
  'UserAssigned'
])
param identityType string = 'None'

@description('The resource ID of the user-assigned identity. Required if identityType is UserAssigned.')
param userAssignedIdentityId string = ''

@description('Enable or disable catalog item synchronization.')
@allowed([
  'Enabled'
  'Disabled'
])
param catalogItemSyncEnableStatus string = 'Enabled'

@description('Enable or disable the Microsoft-hosted network.')
@allowed([
  'Enabled'
  'Disabled'
])
param microsoftHostedNetworkEnableStatus string = 'Enabled'

@description('Enable or disable the installation of the Azure Monitor agent.')
@allowed([
  'Enabled'
  'Disabled'
])
param installAzureMonitorAgentEnableStatus string = 'Enabled'

@description('The names of the environments to create. Can be a single name or an array, e.g., [dev, acc, prod].')
param environmentName array = ['dev']

@description('Tags to apply to the Dev Center resource.')
param tags object = {}

@description('The name of the image gallery to associate with the Dev Center resource.')
param imageGalleryName string = ''

@description('The resource ID of the image gallery to associate with the Dev Center resource.')
param imageGalleryResourceId string = ''

@description('An array of Dev Box configurations.')
@allowed([
  'Enabled'
  'Disabled'
])
param hibernateSupport string = 'Disabled'

@description('An array of Dev Box configurations.')
param devBoxDefinitions array = [
  {
    name: ''
    imageReference: ''
    skuName: ''
    hibernateSupport: hibernateSupport
  }
]

// Define the Dev Center resource
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
  } : {}
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
  tags: tags // Apply tags as an object
}

// Define the image gallery resource associated with the Dev Center
resource devCenterGallery 'Microsoft.DevCenter/devcenters/galleries@2024-10-01-preview' = {
  parent: devCenter
  name: imageGalleryName
  properties: {
    galleryResourceId: imageGalleryResourceId
  }
}

// Define the Dev Box resources based on the array of Dev Box definitions
resource devBoxDefinitionsResources 'Microsoft.DevCenter/devcenters/devboxdefinitions@2024-10-01-preview' = [for devBox in devBoxDefinitions: {
  parent: devCenter
  name: devBox.name
  location: location
  properties: {
    imageReference: {
      id: devBox.imageReference
    }
    sku: {
      name: devBox.skuName
    }
    hibernateSupport: devBox.hibernateSupport
  }
}]

// Create environments for each environment name in the array
resource devCenterEnvironments 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = [for envName in environmentName: {
  parent: devCenter
  name: envName
  properties: {}
}]

// Output the name and ID of the Dev Center resource
@description('The name of the Dev Center resource.')
output name string = devCenter.name

@description('The ID of the Dev Center resource.')
output resourceId string = devCenter.id
