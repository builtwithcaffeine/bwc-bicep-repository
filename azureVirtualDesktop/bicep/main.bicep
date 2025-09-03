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

param resourceGroupName string = 'rg-x-${customerName}-avd-${environmentType}-${locationShortCode}'

//
// Entra Domain Services
// Entra Id Domain Services
@description('The name of the domain to be created.')
param domainName string = 'ad.builtwithcaffeine.cloud'

@description('The name of the resource to be created.')
// NOTE: Character Limit is: 19
param resourceName string = 'builtwithcaffeine'

@description('Domain Services Sku')
@allowed([
  'Standard'
  'Premium'
])
param domainServicesSku string = 'Standard'

@description('Additional recipients for notifications.')
param additionalRecipients array = [
  'alerts@builtwithcaffeine.cloud'
]

var domainServicesConfig = {
  resourceName: resourceName
  domainName: domainName
  sku: domainServicesSku
  additionalRecipients: additionalRecipients
}

//
//
param storageAccountName string = 'st${customerName}fxlogix${environmentType}${locationShortCode}'

//
//

param virtualNetworkName string = 'vnet-${customerName}-avd-${environmentType}-${locationShortCode}'

var privateDnsZones = [
  'privatelink.file.core.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.table.core.windows.net'
  'privatelink.queue.core.windows.net'
]

//
// Bicep Variables - Virtual Machine
param vmHostName string = 'vm-${customerName}-avd'
param vmUserName string = 'ladm_bwcadmin'

@secure()
param vmUserPassword string = 'P@ssw0rd123!'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createLogAnalytics 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'create-log-analytics'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'log-${customerName}-avd-${environmentType}-${locationShortCode}'
    skuName: 'PerGB2018'
    dataRetention: 30
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createEntraDomainNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
  name: 'create-entra-domain-network-security-group'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'nsg-${customerName}-entra-${environmentType}-${locationShortCode}'
    location: location
    securityRules: [
      {
        name: 'AllowRD'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: 'CorpNetSaw'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          priority: 201
        }
      }
      {
        name: 'AllowPSRemoting'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5986'
          sourceAddressPrefix: 'AzureActiveDirectoryDomainServices'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          priority: 301
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createAvdNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
 name: 'create-avd-network-security-group'
 scope: resourceGroup(resourceGroupName)
 params:{
  name: 'nsg-${customerName}-avd-${environmentType}-${locationShortCode}'
 }
dependsOn: [
    createResourceGroup
  ]
}

module createPrivateEndPointNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.1' = {
 name: 'create-private-endpoint-network-security-group'
 scope: resourceGroup(resourceGroupName)
 params:{
  name: 'nsg-${customerName}-pe-${environmentType}-${locationShortCode}'
 }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'subnet-aads-${environmentType}'
        addressPrefix: '10.0.1.0/24'
        networkSecurityGroupResourceId: createEntraDomainNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: 'subnet-avd-${environmentType}'
        addressPrefix: '10.0.2.0/24'
        networkSecurityGroupResourceId: createAvdNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: 'subnet-pe-${environmentType}'
        addressPrefix: '10.0.3.0/24'
        networkSecurityGroupResourceId: createAvdNetworkSecurityGroup.outputs.resourceId
      }
    ]
    dnsServers: [
      '10.0.1.4'
      '10.0.1.5'
    ]
    tags: tags
  }
  dependsOn: [
    createEntraDomainNetworkSecurityGroup
    createAvdNetworkSecurityGroup
    createPrivateEndPointNetworkSecurityGroup
  ]
}


module createPrivateDnsZones 'br/public:avm/res/network/private-dns-zone:0.8.0' = [for zone in privateDnsZones: {
  name: 'create-zone-${zone}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: zone
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'link-${zone}-${customerName}-${environmentType}-${locationShortCode}'
        registrationEnabled: false
        virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}]


module createEntraDomainServices 'br/public:avm/res/aad/domain-service:0.4.1' = {
  name: 'create-entra-domain-services'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: domainServicesConfig.resourceName
    sku: domainServicesConfig.sku
    location: location
    domainName: domainServicesConfig.domainName
    additionalRecipients: domainServicesConfig.additionalRecipients
    externalAccess: 'Disabled'
    ldaps: 'Disabled'
    ntlmV1: 'Disabled'
    tlsV1: 'Disabled'
    replicaSets: [
      {
        location: location
        subnetId: createVirtualNetwork.outputs.subnetResourceIds[0]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}


module createStorageAccountFxLogix 'br/public:avm/res/storage/storage-account:0.26.2' = {
  name: 'create-storage-account-fxlogix'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: storageAccountName
    skuName: 'Standard_LRS'
    publicNetworkAccess: 'Enabled'
    kind: 'StorageV2'
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    privateEndpoints: [
    {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createPrivateDnsZones[0].outputs.resourceId
            }
          ]
        }
        name: 'pep-${storageAccountName}-file'
        service: 'file'
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[2]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createAVDHostPool 'br/public:avm/res/desktop-virtualization/host-pool:0.8.1' = {
  name: 'create-avd-host-pool'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'vdpool-${customerName}-avd-${environmentType}-${locationShortCode}'
    friendlyName: '${customerName} AVD Host Pool'
    description: 'Host pool for ${customerName} in ${environmentType} environment'
    location: location
    loadBalancerType: 'DepthFirst'
    hostPoolType: 'Pooled'
    maxSessionLimit: 20
    managementType: 'Standard'
    tokenValidityLength: 'PT4H'
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createAVDWorkspace 'br/public:avm/res/desktop-virtualization/workspace:0.9.1' = {
  name: 'create-avd-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'vdws-${customerName}-avd-${environmentType}-${locationShortCode}'
    friendlyName: '${customerName} AVD Workspace'
    description: 'Workspace for ${customerName} in ${environmentType} environment'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.18.0' = {
    name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmHostName
    adminUsername: vmUserName
    adminPassword: vmUserPassword
    location: location
    osType: 'Windows'
    vmSize: 'Standard_D2ls_v6'
    availabilityZone: -1
    bootDiagnostics: true
    secureBootEnabled: true
    encryptionAtHost: true
    vTpmEnabled: true
    securityType: 'TrustedLaunch'
    imageReference: {
      publisher: 'microsoftwindowsdesktop'
      offer: 'office-365'
      sku: 'win11-24h2-avd-m365'
      version: 'latest'
    }
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            pipConfiguration: {
              publicIPAddressVersion: 'IPv4'
              publicIPAllocationMethod: 'Static'
              name: '${vmHostName}-pip-01'
            }
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[1]
          }
        ]
        nicSuffix: '-nic-01'
      }
    ]
    extensionAadJoinConfig: {
      enabled: true
    }
    extensionHostPoolRegistration: {
      enabled: true
      modulesUrl: 'https://raw.githubusercontent.com/Azure/RDS-Templates/master/ARM-wvd-templates/DSC/Configuration.zip'
      configurationFunction: 'Configuration.ps1\\AddSessionHost'
      hostPoolName: createAVDHostPool.outputs.name
      registrationInfoToken: createAVDHostPool.outputs.registrationToken
      // https://docs.azure.cn/en-us/virtual-desktop/add-session-hosts-host-pool?tabs=portal%2Ccmd#register-session-hosts-to-a-host-pool
      // https://github.com/Azure/RDS-Templates/tree/master/ARM-wvd-templates/DSC
    }
  }
  dependsOn: [
    createVirtualNetwork
    createEntraDomainServices
    createAVDHostPool
  ]
}
