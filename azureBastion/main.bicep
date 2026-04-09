targetScope = 'subscription'

@description('Customer Name')
param customerName string

@description('Azure Location')
param location string

@description('Azure Location - Short Code')
param locationShortCode string

@description('Azure - Environment Types')
@allowed(['dev', 'acc', 'prod'])
param environmentType string

@description('User Deployment Name')
param deployedBy string

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

var resourceGroupName = 'rg-${customerName}-shared-hub-${environmentType}-${locationShortCode}'

var bastionHostName = 'bas-${customerName}-hub-${environmentType}-${locationShortCode}'
var bastionPublicIpName = 'pip-${bastionHostName}'

var virtualNetworkName = 'vnet-${customerName}-hub-${environmentType}-${locationShortCode}'

@description('Virtual Network - Address Prefixes')
param addressPrefixes array

@description('Virtual Network - Subnets')
param subnets array

@description('Azure Bastion - SKU Name')
@allowed(['Basic', 'Developer', 'Premium', 'Standard'])
param bastionSkuName string

//
// [Azure Verified Modules] - No Hard Coding!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.8.0' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: addressPrefixes
    subnets: subnets
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createAzureBastionPublicIp 'br/public:avm/res/network/public-ip-address:0.12.0' = {
  name: 'create-azure-bastion-public-ip'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: bastionPublicIpName
    location: location
    skuName: 'Standard'
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createAzureBastion 'br/public:avm/res/network/bastion-host:0.8.2' = {
  name: 'create-azure-bastion'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: bastionHostName
    location: location
    skuName: bastionSkuName
    virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
    bastionSubnetPublicIpResourceId: createAzureBastionPublicIp.outputs.resourceId
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
