using './main.bicep'

param customerName = 'bwc'
param environmentType = 'dev'
param location = 'westeurope'
param locationShortCode = 'weu'

param deployedBy = 'labadmin@builtwithcaffeine.cloud' // Injected via Pwsh Script

param enableBastionHost = true
param enableMetricAlerts = false

param alertEmailAddress = 'labadmin@builtwithcaffeine.cloud'

//
param adminUsername = 'ladm_bwcadmin'

param adminPassword = ''
