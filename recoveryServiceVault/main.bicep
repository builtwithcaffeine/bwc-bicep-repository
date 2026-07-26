targetScope = 'subscription'

//
// Imported Parameters

@description('Customer Name')
param customerName string

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Environment Type')
param environmentType string

@description('User Deployment Name')
param deployedBy string

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

//
// Bicep Deployment Variables


@description('Recovery Service Vault Name')
var resourceGroupName = 'rg-${customerName}-rsv-${environmentType}-${locationShortCode}'
var recoveryServiceVaultName string = 'rsv-${customerName}-${environmentType}-${locationShortCode}'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group-${locationShortCode}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createRecoveryServiceVault 'br/public:avm/res/recovery-services/vault:0.13.0' = {
  name: 'create-rsv-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: recoveryServiceVaultName
    location: location
    backupConfig: {
      storageType:  'GeoRedundant'
    }
    backupPolicies: [
      {
        name: 'pol-vm-daily-14day'
        properties: {
          backupManagementType: 'AzureIaasVM'
          policyType: 'V2'
          instantRPDetails: {
            azureBackupRGNamePrefix: 'rg-${customerName}-rsv-restore-${environmentType}-${locationShortCode}'
          }
          schedulePolicy: {
            schedulePolicyType: 'SimpleSchedulePolicyV2'
            scheduleRunFrequency: 'Daily'
            dailySchedule: {
              scheduleRunTimes: [
                '2000-01-01T22:00:00Z'
              ]
            }
          }
          retentionPolicy: {
            retentionPolicyType: 'LongTermRetentionPolicy'
            dailySchedule: {
              retentionTimes: [
                '2000-01-01T22:00:00Z'
              ]
              retentionDuration: {
                count: 14
                durationType: 'Days'
              }
            }
          }
          instantRpRetentionRangeInDays: 2
          timeZone: 'UTC'
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}
