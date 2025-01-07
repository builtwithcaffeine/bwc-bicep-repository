using './main.bicep'

// Default Values
@description('Default Parameter Values')
param location = ''
param locationShortCode = ''
param environmentType = ''
param deployedBy = ''


// Virtual Network
@description('The name of the virtual network to be created.')
param vnetAddressSpace = [
  '192.168.0.0/24'
]

@description('The name of the subnet to be created.')
param subnetAddressPrefix = '192.168.0.0/24'

// Entra Id Domain Services
@description('The name of the domain to be created.')
param domainName = 'ad.builtwithcaffeine.cloud'

@description('The name of the resource to be created.')
// NOTE: Character Limit is: 19
param resourceName = 'builtwithcaffeine'

@description('Domain Services Sku')
@allowed([
  'Standard'
  'Premium'
])
param domainServicesSku = 'Standard'

@description('Additional recipients for notifications.')
param additionalRecipients = [
  'alerts@builtwithcaffeine.cloud'
]
