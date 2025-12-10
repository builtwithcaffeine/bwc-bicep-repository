targetScope = 'subscription'

//
// Imported Parameters

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Customer Name')
param customerName string

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

//
// Bicep Deployment Variables

param resourceGroupName string = 'rg-x-${customerName}--image-shared-${environmentType}'
param virtualNetworkName string = 'vnet-${customerName}-image-build-${environmentType}'
param storageAccountName string = 'st${customerName}imagebuild${environmentType}'
param managedIdentityName string = 'id-${customerName}-image-build-${environmentType}'
param sharedImageGalleryName string = 'gal${customerName}gallery${environmentType}'

var imageTemplates = [
      {
        name: 'img-windows-server-2025-datacenter'
        identifier: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2025-datacenter-azure-edition'
        }
        osState: 'Generalized'
        osType: 'Windows'
        hyperVGeneration: 'V2'
        securityType: 'TrustedLaunch'
      }
      {
        name: 'img-windows-server-2025-datacenter'
        identifier: {
          publisher: 'MicrosoftWindowsDesktop'
          offer: 'office-365'
          sku: 'win11-24h2-avd-m365'
        }
        osState: 'Generalized'
        osType: 'Windows'
        hyperVGeneration: 'V2'
        securityType: 'TrustedLaunch'
      }
]

//
// Azure Verified Modules - No Hard Coded Values below this line!

@description('Create AVM Module - Resource Group')
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

@description('Create AVM Module - User Assigned Managed Identity')
module createManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.3' = {
  name: 'create-managed-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: managedIdentityName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: [
      '10.0.0.0/24'
    ]
    subnets: [
      {
        name: 'snet-imgbuild-shared'
        addressPrefix: '10.0.0.0/28'
      }
      {
        name: 'snet-imgbuild-container'
        addressPrefix: '10.0.0.16/28'
        delegation: 'Microsoft.ContainerInstance/containerGroups'
      }
      {
        name: 'snet-imgbuild-compute'
        addressPrefix: '10.0.0.32/27'
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createPrivateDnsZoneFile 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  name: 'create-private-dns-zone-file'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'privatelink.file.core.windows.net'
    location: 'global'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
        registrationEnabled: false
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createStorageAccount 'br/public:avm/res/storage/storage-account:0.30.0' = {
  name: 'create-storage-account'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: storageAccountName
    location: location
    fileServices: {
      shares: [
        {
          name: 'imgbuild-scripts'
          shareQuota: 10
        }
        {
          name: 'imgbuild-applications'
          shareQuota: 10
        }
      ]
    }
    privateEndpoints: [
      {
        service: 'file'
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createPrivateDnsZoneFile.outputs.resourceId
            }
          ]
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createPrivateDnsZoneFile
  ]
}



@description('Assign Contributor Role to Managed Identity on Resource Group')
module assignContributorRole 'br/public:avm/res/authorization/role-assignment/rg-scope:0.1.1' = {
  name: 'assign-rbac-contributor-role'
  scope: resourceGroup(resourceGroupName)
  params: {
    principalId: createManagedIdentity.outputs.principalId
    roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor Role
  }
  dependsOn: [
    createStorageAccount
  ]
}

@description('Create AVM Module - Shared Compute Image Gallery')
module createSharedComputeImageGallery 'br/public:avm/res/compute/gallery:0.9.4' = {
  name: 'create-shared-compute-image-gallery'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: sharedImageGalleryName
    location: location
    description: 'Shared Compute Gallery for ${customerName} ${environmentType} VM Image Builds'
    images: imageTemplates
    tags: tags
  }
  dependsOn: [
    createManagedIdentity
  ]
}
