targetScope = 'subscription' // Please Update this based on deploymentScope Variable

//
// Imported Parameters

@description('Customer Name')
param customerName string

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
// Virtual Network
@description('Virtual Network Address Space(s)')
param vnetAddressSpace array

@description('The Subnet Address Space.')
param subnetAddressPrefix string

//
// Entra Domain Services Parameters
@description('Active Directory Domain Name')
param domainName string

@description('Entra Id Resource Name')
param resourceName string

@description('Domain Services Sku')
@allowed([
  'Standard'
  'Premium'
])
param domainServicesSku string

@description('Additional recipients for notifications.')
param additionalRecipients array

//
// Bicep Deployment Variables

var resourceGroupName = 'rg-${customerName}-domainservices-${environmentType}-${locationShortCode}'
var logAnalyticsWorkspaceName = 'log-${customerName}-domainservices-${environmentType}-${locationShortCode}'
var networkSecurityGroupName = 'nsg-${customerName}-domainservices-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-${customerName}-domainservices-${environmentType}-${locationShortCode}'

var virtualNetworkConfig = {
  addressSpace: vnetAddressSpace
  subnets: [
    {
      name: 'snet-domainservices'
      addressPrefix: subnetAddressPrefix
      networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
    }
  ]
}

var domainServicesConfig = {
  resourceName: resourceName
  domainName: domainName
  sku: domainServicesSku
  additionalRecipients: additionalRecipients
}

//
// Azure Verified Modules

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'createLogAnalyticsWorkspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 90
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
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

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.1' = {
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
    createNetworkSecurityGroup
  ]
}

module createEntraDomainService 'br/public:avm/res/aad/domain-service:0.5.0' = {
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
    createVirtualNetwork
  ]
}
