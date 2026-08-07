using 'main.bicep'

// Pwsh Input Parameters
param customerName = 'bwc'
param environmentType = 'dev'
param location = 'westeurope'
param locationShortCode = 'weu'
param deployedBy = ''

// Hub Virtual Network
param virtualNetworkAddressPrefixes = [
  '10.0.0.0/24'
]
param gatewaySubnetAddressPrefix = '10.0.0.0/26'

// VPN Gateway
param vpnGatewaySkuName = 'VpnGw1AZ'
param vpnGatewayGeneration = 'Generation1'
param vpnGatewayClusterMode = 'activePassiveNoBgp'
param publicIpAvailabilityZones = [
  1
  2
  3
]

// Point-to-Site VPN Client (Entra ID SSO)
param enableVirtualNetworkGatewayEntraSSO = true
param vpnClientAddressPoolPrefix = '172.16.0.0/24'
param vpnClientAadAudience = '41b23e61-6c1e-4545-b367-cd054e0ed4b4'

// Log Analytics
param logAnalyticsWorkspaceRetentionDays = 30
