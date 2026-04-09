using 'main.bicep'

param customerName = 'bwc'
param location = 'westeurope'
param locationShortCode = 'weu'
param environmentType = 'dev'
param deployedBy = ''

// Azure Bastion - SKU Name
param bastionSkuName = 'Developer'

// Virtual Network - Address Space
param addressPrefixes = [
  '10.0.0.0/24'
]

// Virtual Network - Subnets
param subnets = [
  {
    name: 'AzureFirewallSubnet'
    addressPrefix: '10.0.0.0/26'
  }
  {
    name: 'GatewaySubnet'
    addressPrefix: '10.0.0.64/26'
  }
  {
    name: 'AzureBastionSubnet'
    addressPrefix: '10.0.0.128/26'
  }
  {
    name: 'snet-shared'
    addressPrefix: '10.0.0.192/27'
  }
]
