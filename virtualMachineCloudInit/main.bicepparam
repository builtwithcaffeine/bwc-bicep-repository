using './main.bicep'

@description('Customer name for resource naming.')
param customerName = ''

@description('Azure region for deployment.')
param location = ''

@description('Short code for location.')
param locationShortCode = ''

@description('Environment type (e.g., dev, prod).')
param environmentType = ''

@description('Name of the person or system deploying resources.')
param deployedBy = ''

@description('Address space for the virtual network.')
param vnetAddressSpace = [
  '10.0.0.0/24'
]

@description('The name of the subnet to be created.')
param subnetAddressPrefix = '10.0.0.0/24'

@description('The local user account name for the VM.')
param vmUserName = 'ladm_bwcadmin'

@description('The local user account password for the VM.')
@secure()
param vmUserPassword = 'P@ssw0rd123!'
