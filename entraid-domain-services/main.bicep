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

//
// Bicep Deployment Variables

var resourceGroupName = 'rg-domainservices-${environmentType}-${locationShortCode}'
var logAnalyticsWorkspaceName = 'log-domainservices-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-domainservices-${environmentType}-${locationShortCode}'
var virtualNetworkConfig = {
  addressSpace: [
    '192.168.0.0/24'
  ]
  subnets: [
    {
      name: 'snet-domainservices'
      addressPrefix: '192.168.0.0/24'
      networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
    }
  ]
}

var domainServicesConfig = {
  resourceName:'onmicrosoft.com'
  domainName: 'onmicrosoft.com'
  sku: 'Standard'
  additionalRecipients: [
    'alerts@builtwithcaffeine.cloud'
  ]
}

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

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  name: 'createLogAnalyticsWorkspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'nsg-domainservices'
    location: location
    securityRules: [
      {
        name: 'AllowSyncWithAzureAD'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureActiveDirectoryDomainServices'
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
        }
      }
      {
        name: 'AllowPSRemoting'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5986'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'AzureActiveDirectoryDomainServices'
          access: 'Allow'
          direction: 'Inbound'
          priority: 200
        }
      }
      {
        name: 'AllowLDAPs'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5986'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          direction: 'Inbound'
          priority: 300
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'createVirtualNetwork'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkConfig.addressSpace
    subnets: virtualNetworkConfig.subnets
    tags: tags
  }
  dependsOn: [
    createResourceGroup
    createNetworkSecurityGroup
  ]
}

module domainService 'br/public:avm/res/aad/domain-service:0.3.0' = {
  name: 'createDomainServiceDeployment'
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
    diagnosticSettings: [
      {
        logCategoriesAndGroups: [
          {
            categoryGroup: 'allLogs'
          }
        ]
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
        name: 'customSetting'
        workspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
    createLogAnalyticsWorkspace
    createNetworkSecurityGroup
    createVirtualNetwork
  ]
}
