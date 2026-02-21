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

param sharedResourceGroupName string = 'rg-x-${customerName}-imgbuild-${environmentType}-${locationShortCode}'
param resourceGroupName string = 'rg-x-${customerName}-imgbuild-winsrv-golden-${environmentType}'
param virtualNetworkName string = 'vnet-${customerName}-imgbuild-${environmentType}'
param storageAccountName string = 'st${customerName}imgbuild${environmentType}'
param managedIdentityName string = 'id-${customerName}-imgbuild-${environmentType}'
param sharedImageGalleryName string = 'gal${customerName}imgbuild${environmentType}'
param imageTemplateName string = '${customerName}-vmimage-${environmentType}'
param imageVersionName string = '1.0.0' // Specify the version of the image to use as source

//
//

resource existingImageGallery 'Microsoft.Compute/galleries@2022-03-03' existing = {
  scope: resourceGroup(sharedResourceGroupName)
  name: sharedImageGalleryName
}

resource existingImageDefinition 'Microsoft.Compute/galleries/images@2024-03-03' existing = {
  parent: existingImageGallery
  name: imageTemplateName
}

resource existingImageVersion 'Microsoft.Compute/galleries/images/versions@2024-03-03' existing = {
  parent: existingImageDefinition
  name: imageVersionName
}

resource existingManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' existing = {
  scope: resourceGroup(sharedResourceGroupName)
  name: managedIdentityName
}

resource existingVirtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  scope: resourceGroup(sharedResourceGroupName)
  name: virtualNetworkName
}

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

@description('Create AVM Module - Virtual Machine Image Template - Base Line (Clean OS)')
module createImageTemplate 'br/public:avm/res/virtual-machine-images/image-template:0.6.1' = {
  name: 'create-image-template'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: '${customerName}-winsrv2025-${environmentType}'
    location: location
    distributions: [
      {
        sharedImageGalleryImageDefinitionResourceId: existingImageDefinition.id
        type: 'SharedImage'
      }
    ]
    imageSource: {
      imageVersionId: existingImageVersion.id
      type: 'SharedImageVersion'
    }
    vmSize: 'Standard_D4s_v6' // 4vCPUs, 16GB RAM
    managedIdentities: {
      userAssignedResourceIds: [
        existingManagedIdentity.id
      ]
    }
    vnetConfig: {
      containerInstanceSubnetResourceId: existingVirtualNetwork.properties.subnets[1].id
      subnetResourceId: existingVirtualNetwork.properties.subnets[2].id
    }
    optimizeVmBoot: 'Enabled'
    autoRunState: 'Disabled'
    buildTimeoutInMinutes: 60
    customizationSteps: []

    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}
