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
// Resource Variables
//


param kvSoftDeleteRetentionInDays int = 7
param kvNetworkAcls object = {
  bypass: 'AzureServices'
  defaultAction: 'Allow'
}
param kvSecretArray array = [
]

//
// Bicep Deployment Variables
//

var resourceGroupName = 'rg-hub-vgw-${environmentType}-${locationShortCode}'

//
// Azure Verified Modules - No Hard Coded Values below this line!
//

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

module createUserManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'create-user-managed-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-hub-vgw-${environmentType}-${locationShortCode}'
    location: location
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createKeyVault 'br/public:avm/res/key-vault/vault:0.12.1' = {
  name: 'create-key-vault'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'kv-hub-vgw-${environmentType}-${locationShortCode}'
    sku: 'standard'
    location: location
    tags: tags
    enableRbacAuthorization: false
    enablePurgeProtection: false
    softDeleteRetentionInDays: kvSoftDeleteRetentionInDays
    networkAcls: kvNetworkAcls
    secrets: kvSecretArray
    accessPolicies: [
    {
      objectId: createUserManagedIdentity.outputs.principalId
      permissions: {
        keys: [
          'get'
          'list'
        ]
        secrets: [
          'get'
          'list'
        ]
        certificates: [
          'get'
          'list'
        ]
      }
    }
  ]
  }
  dependsOn: [
    createUserManagedIdentity
  ]
}

module createVirtualNetworkGateway 'modules/network/virtual-network-gateway/main.bicep' = {
  name: 'create-virtual-network-gateway'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'vgw-hub-${environmentType}-${locationShortCode}'
    location: location
    ManagedServiceIdentityUserAssignedIdentities: {
      '${createUserManagedIdentity.outputs.resourceId}': {}
    }
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

// module createVirtualNetworkGateway 'br/public:avm/res/network/virtual-network-gateway:0.5.0' = {
//   name: 'create-virtual-network-gateway'
//   scope: resourceGroup(resourceGroupName)
//   params: {
//     name: 'vgw-hub-${environmentType}-${locationShortCode}'
//     location: location
//     gatewayType: 'Vpn'
//     skuName: 'VpnGw1AZ'
//     clusterSettings: {
//       clusterMode: 'activePassiveNoBgp'
//     }
//     vNetResourceId: createVirtualNetwork.outputs.resourceId
//     publicIpZones: [
//       1
//       2
//       3
//     ]
//     tags: tags
//   }
//   dependsOn: [
//     createVirtualNetwork
//   ]
// }
