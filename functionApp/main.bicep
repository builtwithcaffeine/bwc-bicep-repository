targetScope = 'subscription'

@description('User Account GUID')
param userAccountGuid string

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Environment Type')
@allowed([
  'dev'
  'acc'
  'prod'
])
param environmentType string

@description('User Deployment Name')
param deployedBy string

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

// Resource Names
param projectName string = 'bicepbwc'

var resourceGroupName = 'rg-${projectName}-${environmentType}-${locationShortCode}'
var userManagedIdentityName = 'id-${projectName}-${environmentType}-${locationShortCode}'
var keyvaultName = 'kv-${projectName}-${environmentType}'

param kvSoftDeleteRetentionInDays int = 7
param kvNetworkAcls object = {
  bypass: 'AzureServices'
  defaultAction: 'Allow'
}
param kvSecretArray array = [
]

// Storage Account Variables
param storageAccountName string = 'st${projectName}${environmentType}${locationShortCode}'

@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
@description('Storage Account SKU Name')
param stSkuName string = 'Standard_LRS'

@allowed([
  'TLS1_2'
  'TLS1_3'
])
@description('Storage Account TLS Version')
param stTlsVersion string = 'TLS1_2'

@allowed([
  'Enabled'
  'Disabled'
])
@description('Storage Account Public Network Access')
param stPublicNetworkAccess string = 'Enabled'

@allowed([
  true
  false
])
@description('Storage Account Allowed Shared Key Access')
param stAllowedSharedKeyAccess bool = true

@description('Storage Account Network ACLs')
param stNetworkAcls object = {
  bypass: 'AzureServices'
  defaultAction: 'Allow'
}

// Log Analytics Variables
@description('Log Analytics Name')
param logAnalyticsName string = 'log-${projectName}-${environmentType}-${locationShortCode}'

@description('Log Analytics Data Retention')
param logAnalyticsDataRetention int = 30

// Application Insights Variables
@description('Application Insights Name')
param appInsightsName string = 'appi-${projectName}-${environmentType}-${locationShortCode}'

// App Service Plan Variables
@description('App Service Plan Name')
param appServicePlanName string = 'asp-${projectName}-${environmentType}-${locationShortCode}'

@description('App Service Plan Capacity')
param aspCapacity int = 1

@description('App Service Plan SKU Name')
param aspSkuName string = 'Y1'

@description('App Service Plan Kind')
param aspKind string = 'linux'

// Azure Function Variables
@description('Function App Name')
param functionAppName string = 'func-${projectName}-${environmentType}-${locationShortCode}'

@allowed([
  true
  false
])
@description('Function App System Assigned Identity')
param functionAppSystemAssignedIdentity bool = false

//
// NO HARD CODING UNDER THERE! K THANKS BYE 👋
//

// [AVM Module] - Resource Group
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createUserManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'create-userManaged-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: userManagedIdentityName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [AVM] - Key Vault
module createKeyVault 'br/public:avm/res/key-vault/vault:0.12.1' = {
  name: 'create-key-vault'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: keyvaultName
    sku: 'standard'
    location: location
    tags: tags
    enableRbacAuthorization: true
    enablePurgeProtection: false
    softDeleteRetentionInDays: kvSoftDeleteRetentionInDays
    networkAcls: kvNetworkAcls
    roleAssignments: [
      {
        principalId: createUserManagedIdentity.outputs.principalId
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: userAccountGuid
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'User'
      }
    ]
    secrets: kvSecretArray
  }
  dependsOn: [
    createUserManagedIdentity
  ]
}

// [AVM Module] - Storage Account
module createStorageAccount 'br/public:avm/res/storage/storage-account:0.18.1' = {
  name: 'create-storage-account'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: storageAccountName
    location: location
    skuName: stSkuName
    minimumTlsVersion: stTlsVersion
    publicNetworkAccess: stPublicNetworkAccess
    allowSharedKeyAccess: stAllowedSharedKeyAccess
    secretsExportConfiguration: {
      accessKey1Name: 'accessKey1'
      accessKey2Name: 'accessKey2'
      connectionString1Name: 'connectionString1'
      connectionString2Name: 'connectionString2'
      keyVaultResourceId: createKeyVault.outputs.resourceId
    }
    networkAcls: stNetworkAcls
    tags: tags
  }
  dependsOn: [
    createKeyVault
  ]
}

// [AVM Module] - Log Analytics
module createLogAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.1' = {
  name: 'create-log-analytics'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsName
    location: location
    dataRetention: logAnalyticsDataRetention
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [AVM Module] - Application Insights
module createApplicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'create-app-insights'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: appInsightsName
    workspaceResourceId: createLogAnalytics.outputs.resourceId
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [AVM Module] - App Service Plan
module createAppServicePlan 'br/public:avm/res/web/serverfarm:0.4.1' = {
  scope: resourceGroup(resourceGroupName)
  name: 'create-app-service-plan'
  params: {
    name: appServicePlanName
    skuCapacity: aspCapacity
    skuName: aspSkuName
    kind: aspKind
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [AVM Module] - Function App
module createFunctionApp 'br/public:avm/res/web/site:0.15.0' = {
  name: 'create-function-app'
  scope: resourceGroup(resourceGroupName)
  params: {
    kind: 'functionapp,linux'
    name: functionAppName
    location: location
    httpsOnly: true
    serverFarmResourceId: createAppServicePlan.outputs.resourceId
    appInsightResourceId: createApplicationInsights.outputs.resourceId
    keyVaultAccessIdentityResourceId: createUserManagedIdentity.outputs.resourceId
    storageAccountRequired: true
    storageAccountResourceId: createStorageAccount.outputs.resourceId
    managedIdentities: {
      systemAssigned: functionAppSystemAssignedIdentity
      userAssignedResourceIds: [
        createUserManagedIdentity.outputs.resourceId
      ]
    }
    appSettingsKeyValuePairs: {
      APPLICATIONINSIGHTS_CONNECTION_STRING: createApplicationInsights.outputs.connectionString
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: '@Microsoft.KeyVault(VaultName=${keyvaultName};SecretName=connectionString1)'
      WEBSITE_CONTENTSHARE: functionAppName
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'powershell'
      managedIdentityId: createUserManagedIdentity.outputs.clientId
    }
    siteConfig: {
      alwaysOn: false
      linuxFxVersion: 'POWERSHELL|7.4'
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.3'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    basicPublishingCredentialsPolicies: [
      {
        allow: false
        name: 'ftp'
      }
      {
        allow: true
        name: 'scm'
      }
    ]
    logsConfiguration: {
      applicationLogs: {
        fileSystem: {
          level: 'Verbose'
        }
      }
      detailedErrorMessages: {
        enabled: true
      }
      failedRequestsTracing: {
        enabled: true
      }
      httpLogs: {
        fileSystem: {
          enabled: true
          retentionInDays: 1
          retentionInMb: 35
        }
      }
    }
    tags: tags
  }
  dependsOn: [
    createUserManagedIdentity
    createAppServicePlan
  ]
}
