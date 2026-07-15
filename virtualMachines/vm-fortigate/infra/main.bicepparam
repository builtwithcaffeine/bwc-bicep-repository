using 'main.bicep'

param customerName = 'bwc'
param environment = 'dev'
param location = 'uksouth'
param locationShortCode = 'uks'

// Virtual Machine - Local User Account
param adminUser = 'bwccloudops'

// Virtual Machine - Local User Password
param adminPassword = ''
