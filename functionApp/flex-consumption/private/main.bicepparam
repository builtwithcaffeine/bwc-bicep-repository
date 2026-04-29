using 'main.bicep'

param customerName = ''
param environmentType = 'dev'
param location = ''
param locationShortCode = ''
param deployedBy = ''

// Networking Mode: Set to true for standalone (new VNet), false to use existing hub environment
param enableCreateVirtualNetwork = true

// Existing Hub Environment Parameters (required when enableCreateVirtualNetwork = false)
param sharedHubSubscriptionId = ''
param sharedHubResourceGroupName = ''
param sharedHubVirtualNetworkName = ''
param sharedHubSubnetShared = ''
param sharedHubSubnetOutbound = ''
param sharedHubPrivateDnsZoneResourceGroupName = ''
