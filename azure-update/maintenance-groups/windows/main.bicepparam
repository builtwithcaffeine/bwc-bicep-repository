using 'main.bicep'

// Required parameters
param customerName = 'example'
param environmentType = 'dev'
param location = 'westeurope'
param locationShortCode = 'weu'
param deployedBy = ''
param publicIp = ''


param resourceGroupName = 'rg-x-win-${customerName}-${environmentType}-${locationShortCode}'
param networkSecurityGroupName = 'nsg-${customerName}-${environmentType}-${locationShortCode}'
param virtualNetworkName = 'vnet-${customerName}-${environmentType}-${locationShortCode}'
param subnetName = 'snet-${customerName}-${environmentType}-${locationShortCode}'
param logAnalyticsWorkspaceName = 'log-${customerName}-${environmentType}-${locationShortCode}'
param windowsDataCollectionRuleName = 'MSVMI-dcr-windows'

param vmHostName = 'vm-${customerName}-win-${environmentType}'
param vmUserName = 'ladm_bwcadmin'
param vmUserPassword = 'P@ssw0rd1234!'


param maintenanceConfiguration = [
  {
    name: 'mc-${customerName}-${environmentType}-windows'
    location: location
    maintenanceScope: 'InGuestPatch'
    extensionProperties: {
      InGuestPatchMode: 'User'
    }
    maintenanceWindow: {
      timeZone: 'W. Europe Standard Time'
      expirationDateTime: '9999-12-31 23:59:59'
      startDateTime: '2025-08-08 22:30'   // Custom maintenance window
      duration: '04:00'                   // Extended duration
      recurEvery: 'Day'                  // Daily
    }
    installPatches: {
      rebootSetting: 'IfRequired'
      windowsParameters: {
      classificationsToInclude: [
          'Critical'
          'Security'
          'UpdateRollup'
          'Definition'
          'Updates'
      ]
      }
    }
  }
]
