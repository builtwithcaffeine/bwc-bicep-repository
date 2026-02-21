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

//
// Bicep Deployment Variables

param sharedResourceGroupName string = 'rg-x-${customerName}-image-shared-${environmentType}'
param virtualNetworkName string = 'vnet-${customerName}-image-build-${environmentType}'
param storageAccountName string = 'st${customerName}imagebuild${environmentType}'
param managedIdentityName string = 'id-${customerName}-image-build-${environmentType}'
param sharedImageGalleryName string = 'gal${customerName}gallery${environmentType}'
param imageTemplateName string = 'img-windows-server-2025-datacenter'
param imageVersionName string = '1.0.0' // Specify the version of the image to use as source

param resourceGroupNameArray array = [
  'rg-x-${customerName}-image-winsrv2025-${environmentType}'
  'rg-x-${customerName}-image-win11avd-m365-${environmentType}'
]

param imageSource array = [
  {
    publisher: 'MicrosoftWindowsServer'
    offer: 'WindowsServer'
    sku: '2025-datacenter-azure-edition'
    version: 'latest'
    type: 'PlatformImage'
  }
  {
    publisher: 'MicrosoftWindowsDesktop'
    offer: 'office-365'
    sku: 'win11-24h2-avd-m365'
    version: 'latest'
    type: 'PlatformImage'
  }
]

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
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = [
  for resourceGroupName in resourceGroupNameArray: {
    name: 'create-resource-group-${uniqueString(resourceGroupName)}'
    params: {
      name: resourceGroupName
      location: location
      tags: tags
    }
  }
]

@description('Create AVM Module - Virtual Machine Image Template - Base Line (Clean OS)')
module createImageTemplateImg1 'br/public:avm/res/virtual-machine-images/image-template:0.6.1' = {
  name: 'create-image-template-img1'
  scope: resourceGroup(resourceGroupNameArray[0])
  params: {
    name: '${customerName}-winsrv2025-${environmentType}'
    location: location
    distributions: [
      {
        sharedImageGalleryImageDefinitionResourceId: existingImageDefinition.id
        type: 'SharedImage'
      }
    ]
    imageSource: imageSource[0]
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
    autoRunState: 'Enabled'
    buildTimeoutInMinutes: 60
    customizationSteps: [
      {
        type: 'PowerShell'
        name: 'InstallRSATFeatures'
        inline: [
          'Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-AD-PowerShell, RSAT-DNS-Server, GPMC'
        ]
        runElevated: true
        runAsSystem: false
      }
      {
        type: 'WindowsUpdate'
        updateLimit: 20
      }
      {
        type: 'WindowsRestart'
        restartTimeout: '5m'
      }
      {
        type: 'WindowsUpdate'
        updateLimit: 20
      }
      {
        type: 'WindowsRestart'
        restartTimeout: '5m'
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// @description('Create AVM Module - Virtual Machine Image Template - Base Line (Clean OS)')
// module createImageTemplateImg2 'br/public:avm/res/virtual-machine-images/image-template:0.6.1' = {
//   name: 'create-image-template-img2'
//   scope: resourceGroup(resourceGroupNameArray[1])
//   params: {
//     name: '${customerName}-winsrv2025-${environmentType}'
//     location: location
//     distributions: [
//       {
//         sharedImageGalleryImageDefinitionResourceId: existingImageDefinition.id
//         type: 'SharedImage'
//       }
//     ]
//     imageSource: imageSource[1]
//     vmSize: 'Standard_D4s_v6' // 4vCPUs, 16GB RAM
//     managedIdentities: {
//       userAssignedResourceIds: [
//         existingManagedIdentity.id
//       ]
//     }
//     vnetConfig: {
//       containerInstanceSubnetResourceId: existingVirtualNetwork.properties.subnets[1].id
//       subnetResourceId: existingVirtualNetwork.properties.subnets[2].id
//     }
//     optimizeVmBoot: 'Enabled'
//     autoRunState: 'Enabled'
//     buildTimeoutInMinutes: 60
//     customizationSteps: []
//     tags: tags
//   }
//   dependsOn: [
//     createResourceGroup
//   ]
// }
