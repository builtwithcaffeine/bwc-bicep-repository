using 'main.bicep'

param customerName = ''
param projectName = ''
param environmentType = ''
param location = ''
param locationShortCode = ''
param deployedBy = ''

// Networking Mode: true = standalone (create new VNet+DNS), false = use existing spoke VNet + shared hub DNS
param enableCreateVirtualNetwork = false

//
// Existing Spoke VNet (subnets used for PE + outbound VNet integration)
// In production this lives in the customer spoke subscription.
// For sandbox emulation, point at a VNet you control in the same sub.
param existingVirtualNetworkSubscriptionId = ''
param existingVirtualNetworkResourceGroupName = ''
param existingVirtualNetworkName = ''
param existingSubnetShared = ''
param existingSubnetOutbound = ''

//
// Shared Hub Private DNS Zones (typically a separate central subscription)
// In production this is the customer hub sub. For sandbox emulation, set to the
// same sub + RG that holds your fake hub DNS zones.
param sharedHubSubscriptionId = ''
param sharedHubPrivateDnsZoneResourceGroupName = ''
