using './main.bicep'

// Default Values
param customerName = ''
param location = ''
param locationShortCode = ''
param environmentType = ''
param deployedBy = ''


// Virtual Network - Address Space
param vnetAddressSpace = [
  '192.168.0.0/24'
]

// Virtual Network - Subnet Address Space
param subnetAddressPrefix = '192.168.0.0/24'

// Entra Id Domain Services
param domainName = 'ad.builtwithcaffeine.cloud'

// Entra Domain Services Resource Name
// NOTE: Character Limit is: 19
param resourceName = 'builtwithcaffeine'

// Entra Domain Services Skus
// Standard
// Premium
param domainServicesSku = 'Standard'

// Entra Domain Services - Additional Recipients for Alerts
param additionalRecipients = [
  'alerts@builtwithcaffeine.cloud'
]
