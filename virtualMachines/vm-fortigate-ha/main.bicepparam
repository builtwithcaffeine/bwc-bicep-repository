using 'main.bicep'

param customerName = 'bwc'
param environmentType = 'dev'
param location = 'uksouth'
param locationShortCode = 'uks'
param deployedBy = 'bwccloudops'

// Virtual Machine - Local User Account
param adminUser = 'bwccloudops'

// Virtual Machine - Local User Password
param adminPassword = 'P@ssw0rd123!'
