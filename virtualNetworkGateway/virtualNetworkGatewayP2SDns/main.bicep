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

@description('Enable - Create Azure Private DNS Resolver')
param enableCreateAzurePrivateDnsResolver bool = false

@description('Azure Private DNS Resolver Name')
param azurePrivateDnsResolverName string = 'dnspr-${customerName}-hub-${environmentType}-${locationShortCode}'

@description('Enable - Create Azure Container Instance')
param enableCreateAzureContainerInstance bool = true

@description('Azure Container Instance Name')
param containerInstanceName string = 'aci-${customerName}-dns-forwarder-${environmentType}-${locationShortCode}'

@description('Container Instance Image')
param containerInstanceImage string = 'ghcr.io/smoonlee/az-dns-forwarder:3.23.3'

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
    {
      name: 'snet-dnsresolver-inbound'
      addressPrefix: '10.0.0.32/28'
      delegation: 'Microsoft.Network/dnsResolvers'

    }
    {
      name: 'snet-dnsresolver-outbound'
      addressPrefix: '10.0.0.48/28'
      delegation: 'Microsoft.Network/dnsResolvers'
    }
    {
      name: 'snet-aci-dns-forwarder'
      addressPrefix: '10.0.0.64/28'
      delegation: 'Microsoft.ContainerInstance/containerGroups'
    }
    {
      name: 'snet-resource'
      addressPrefix: '10.0.0.80/28'
    }
  ]
}

param virtualNetworkGatewaySettings object = {
  vpnClientAadConfiguration: {
    vpnAuthenticationTypes: [
      'AAD'
    ]
    vpnClientProtocols: [
      'OpenVPN'
    ]
    // Entra Azure VPN Configuration
    // https://learn.microsoft.com/en-gb/azure/vpn-gateway/point-to-site-entra-gateway
    aadTenant: 'https://login.microsoftonline.com/${tenant().tenantId}/'
    aadAudience: '41b23e61-6c1e-4545-b367-cd054e0ed4b4'
    aadIssuer: 'https://sts.windows.net/${tenant().tenantId}/'
  }
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
    skuName: 'PerGB2018'
    dataRetention: 30
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

// module createVirtualNetworkGateway 'br/public:avm/res/network/virtual-network-gateway:0.10.1' = {
//   name: 'create-virtual-network-gateway'
//   scope: resourceGroup(resourceGroupName)
//   params: {
//     name: virtualNetworkGatewayName
//     location: location
//     gatewayType: 'Vpn'
//     skuName: 'VpnGw1AZ'
//     clusterSettings: {
//       clusterMode: 'activePassiveNoBgp'
//     }
//     virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
//     publicIpAvailabilityZones: [1, 2, 3]
//     vpnClientAadConfiguration: virtualNetworkGatewaySettings.vpnClientAadConfiguration
//     tags: tags
//   }
//   dependsOn: [
//     createVirtualNetwork
//   ]
// }

module createAzurePrivateDnsResolver 'br/public:avm/res/network/dns-resolver:0.5.6' = if (enableCreateAzurePrivateDnsResolver) {
  name: 'create-azure-dns-resolver'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: azurePrivateDnsResolverName
    location: location
    virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
    inboundEndpoints: [
      {
        name: 'dnsresolver-inbound'
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[1] // snet-dnsresolver-inbound
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createAzureContainerInstance 'br/public:avm/res/container-instance/container-group:0.7.0' = if (enableCreateAzureContainerInstance) {
  name: 'create-azure-container-instance'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: containerInstanceName
    location: location
    availabilityZone: -1
    osType: 'Linux'
    sku: 'Standard'
    subnets: [
      {
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[3] // snet-aci-dns-forwarder
      }
    ]
    containers: [
      {
        name: 'azure-dns-forwarder'
        properties: {
          image: containerInstanceImage
          resources: {
            requests: {
              cpu: 1
              memoryInGB: '0.5'
            }
          }
          ports: [
            {
              port: 53
              protocol: 'UDP'
            }
          ]
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
