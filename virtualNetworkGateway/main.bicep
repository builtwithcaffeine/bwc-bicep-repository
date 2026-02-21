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

@description('Resource Group Name')
param resourceGroupName string = 'rg-x-${customerName}-hub-${environmentType}-${locationShortCode}'

param logAnalyticsWorkspaceName string = 'log-${customerName}-vgwdiags-${environmentType}-${locationShortCode}'

@description('Virtual Network Name')
param virtualNetworkName string = 'vnet-${customerName}-hub-${environmentType}-${locationShortCode}'

@description('Virtual Network Gateway Name')
param virtualNetworkGatewayName string = 'vgw-${customerName}-hub-${environmentType}-${locationShortCode}'

@description('Virtual Network Settings')
param virtualNetworkSettings object = {
  addressPrefixes: [
    '10.0.0.0/24'
  ]
  subnets: [
    {
      name: 'GatewaySubnet'
      addressPrefix: '10.0.0.0/27'
    }
  ]
}

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    dataRetention: 14
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
    addressPrefixes: virtualNetworkSettings.addressPrefixes
    subnets: virtualNetworkSettings.subnets
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetworkGateway 'br/public:avm/res/network/virtual-network-gateway:0.10.1' = {
  name: 'create-virtual-network-gateway'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkGatewayName
    location: location
    gatewayType: 'Vpn'
    skuName: 'VpnGw1AZ'
    clusterSettings: {
      clusterMode: 'activePassiveNoBgp'
    }
    virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
    publicIpAvailabilityZones: [1, 2, 3]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
