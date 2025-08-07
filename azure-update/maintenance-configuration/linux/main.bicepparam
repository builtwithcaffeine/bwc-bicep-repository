using 'main.bicep'

// Required parameters
param customerName = 'example'
param environmentType = 'dev'
param location = 'westeurope'
param locationShortCode = 'weu'
param deployedBy = ''
param publicIp = ''

param resourceGroupName = 'rg-x-lin-${customerName}-${environmentType}-${locationShortCode}'
param networkSecurityGroupName = 'nsg-${customerName}-${environmentType}-${locationShortCode}'
param virtualNetworkName = 'vnet-${customerName}-${environmentType}-${locationShortCode}'
param subnetName = 'snet-${customerName}-${environmentType}-${locationShortCode}'
param logAnalyticsWorkspaceName = 'log-${customerName}-${environmentType}-${locationShortCode}'
param linuxDataCollectionRuleName = 'MSVMI-dcr-linux'

param vmHostName = 'vm-${customerName}-lin-${environmentType}'
param vmUserName = 'ladm_bwcadmin'
param vmUserPassword = 'P@ssw0rd123!'

// Maintenance configuration for Linux VMs
param maintenanceConfiguration = [
  {
    name: 'mc-${customerName}-${environmentType}-linux'
    location: location
    maintenanceScope: 'InGuestPatch'
    extensionProperties: {
      InGuestPatchMode: 'User'
    }
    maintenanceWindow: {
      timeZone: 'W. Europe Standard Time'
      expirationDateTime: '9999-12-31 23:59:59'
      startDateTime: '2025-08-07 17:00'   // Custom maintenance window
      duration: '04:00'                   // Extended duration
      recurEvery: 'Day'                   // Daily
    }
    installPatches: {
      rebootSetting: 'IfRequired'
      linuxParameters: {
        classificationsToInclude: [
          'Security'
          'Critical'
        ]
      }
    }
  }
]
