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

var resourceGroupName = 'rg-hub-vgw-${environmentType}-${locationShortCode}'

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

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.5.1' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'vnet-hub-vgw-${environmentType}-${locationShortCode}'
    location: location
    addressPrefixes: [
      '10.0.0.0/27'
    ]
    subnets: [
      {
        name: 'GatewaySubnet'
        addressPrefix: '10.0.0.0/27'
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetworkGateway 'br/public:avm/res/network/virtual-network-gateway:0.5.0' = {
  name: 'create-virtual-network-gateway'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'vgw-hub-${environmentType}-${locationShortCode}'
    location: location
    gatewayType: 'Vpn'
    skuName: 'VpnGw1AZ'
    clusterSettings: {
      clusterMode: 'activePassiveNoBgp'
    }
    vNetResourceId: createVirtualNetwork.outputs.resourceId
    publicIpZones: [
      1
      2
      3
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
