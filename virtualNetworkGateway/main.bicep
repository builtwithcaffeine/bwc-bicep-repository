targetScope = 'subscription'

// Pwsh Input Parameters
@description('Customer Name')
param customerName string = 'bwc'

@description('Azure - Environment Types')
@allowed(['dev', 'acc', 'prod'])
param environmentType string = 'dev'

@description('Azure Location')
param location string = 'westeurope'

@description('Azure Location - Short Code')
param locationShortCode string = 'weu'

@description('Deployment Date, used for tagging')
param deployedOn string = utcNow('yyyy-MM-dd')

@description('User Deployment Name, used for tagging')
param deployedBy string

@description('Azure Metadata Tags')
param tags object = {
  Environment: environmentType
  DeployedOn: deployedOn
  DeployedBy: deployedBy
}

//
// Hub Virtual Network
//

@description('Address prefix(es) for the hub Virtual Network')
param virtualNetworkAddressPrefixes array

@description('Address prefix for the required GatewaySubnet')
param gatewaySubnetAddressPrefix string

//
// VPN Gateway
//

@description('SKU for the VPN Gateway')
@allowed([
  'Basic'
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
  'VpnGw4AZ'
  'VpnGw5AZ'
])
param vpnGatewaySkuName string = 'VpnGw1AZ'

@description('Generation for the VPN Gateway. VpnGw1AZ only supports Generation1; Generation2 requires VpnGw2AZ or higher')
@allowed([
  'Generation1'
  'Generation2'
])
param vpnGatewayGeneration string = 'Generation1'

@description('Cluster mode for the VPN Gateway')
@allowed([
  'activePassiveNoBgp'
  'activePassiveBgp'
  'activeActiveNoBgp'
  'activeActiveBgp'
])
param vpnGatewayClusterMode string = 'activePassiveNoBgp'

@description('Availability zones for the VPN Gateway public IP(s). Not applicable for the Basic SKU')
param publicIpAvailabilityZones array = [
  1
  2
  3
]

//
// Point-to-Site VPN Client (Entra ID SSO)
//

@description('Enable Entra ID (AAD) authentication single sign-on for Point-to-Site VPN clients')
param enableVirtualNetworkGatewayEntraSSO bool

@description('Address pool prefix VPN clients receive an IP from when connected (P2S). Must not overlap with the virtual network or on-premises ranges')
param vpnClientAddressPoolPrefix string

@description('Entra ID (AAD) audience value for the Azure VPN Client. Must match an Enterprise Application consented in the tenant - defaults to the legacy "Azure VPN" app; Microsoft\'s newer app (c632b3df-fb67-4d84-bdcf-b95ad541b5c8) requires its own consent before it can be used')
param vpnClientAadAudience string

//
// Log Analytics
//

@description('Log Analytics workspace data retention in days')
param logAnalyticsWorkspaceRetentionDays int = 30

var tenantId = subscription().tenantId

//
// Azure Resource Names
//

var resourceGroupName = 'rg-x-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var logAnalyticsWorkspaceName = 'log-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var virtualNetworkGatewayName = 'vng-${customerName}-shared-hub-${environmentType}-${locationShortCode}'

// Azure Resource Configuration Values

var virtualNetworkSettings = {
  addressPrefix: virtualNetworkAddressPrefixes
  subnets: [
    {
      name: 'GatewaySubnet'
      addressPrefix: gatewaySubnetAddressPrefix
    }
  ]
}

//
// Azure Verified Modules
//

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group-${locationShortCode}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.10.1' = {
  name: 'create-virtual-network-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkSettings.addressPrefix
    subnets: virtualNetworkSettings.subnets
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.16.0' = {
  name: 'create-log-analytics-workspace-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: logAnalyticsWorkspaceRetentionDays
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetworkGateway 'br/public:avm/res/network/virtual-network-gateway:0.12.0' = {
  name: 'create-virtual-network-gateway-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkGatewayName
    location: location
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    skuName: vpnGatewaySkuName
    vpnGatewayGeneration: vpnGatewayGeneration
    clusterSettings: {
      clusterMode: vpnGatewayClusterMode
    }
    virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
    publicIpAvailabilityZones: publicIpAvailabilityZones
    vpnClientAddressPoolPrefix: enableVirtualNetworkGatewayEntraSSO
      ? vpnClientAddressPoolPrefix
      : null
    vpnClientAadConfiguration: enableVirtualNetworkGatewayEntraSSO
      ? {
          aadAudience: vpnClientAadAudience
          aadIssuer: 'https://sts.windows.net/${tenantId}/'
          aadTenant: '${environment().authentication.loginEndpoint}${tenantId}/'
          vpnAuthenticationTypes: [
            'AAD'
          ]
          vpnClientProtocols: [
            'OpenVPN'
          ]
        }
      : null
    diagnosticSettings: [
      {
        name: 'DiagnosticSettings'
        workspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
        metricCategories: [
          {
            category: 'AllMetrics'
          }
        ]
      }
    ]
    tags: tags
  }
}

//
// Outputs
//

output resourceGroupName string = resourceGroupName
output virtualNetworkResourceId string = createVirtualNetwork.outputs.resourceId
output virtualNetworkGatewayResourceId string = createVirtualNetworkGateway.outputs.resourceId
output virtualNetworkGatewayName string = createVirtualNetworkGateway.outputs.name
