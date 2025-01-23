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
  'test'
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

// Storage Account Variables
param storageAccountName string = 'sa${projectName}${environmentType}${locationShortCode}'
param stSkuName string = 'Standard_GRS'
param stTlsVersion string = 'TLS1_2'
param stPublicNetworkAccess string = 'Enabled'
param stAllowedSharedKeyAccess bool = true
param stNetworkAcls object = {
  bypass: 'AzureServices'
  defaultAction: 'Allow'
}

// Log Analytics Variables
param logAnalyticsName string = 'log-${projectName}-${environmentType}-${locationShortCode}'

// Application Insights Variables
param appInsightsName string = 'appi-${projectName}-${environmentType}-${locationShortCode}'

// App Service Plan Variables
param appServicePlanName string = 'asp-${projectName}-${environmentType}-${locationShortCode}'
param aspCapacity int = 1
param aspSkuName string = 'WS1'
param aspKind string = 'windows'

param logicAppName string = 'logic-${projectName}-${environmentType}-${locationShortCode}'

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
module createKeyVault 'br/public:avm/res/key-vault/vault:0.11.2' = {
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
        roleDefinitionIdOrName: 'Key Vault Administrator'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: createUserManagedIdentity.outputs.principalId
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'ServicePrincipal'
      }
      {
        principalId: userAccountGuid
        roleDefinitionIdOrName: 'Key Vault Administrator'
        principalType: 'User'
      }
      {
        principalId: userAccountGuid
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'User'
      }
    ]
  }
  dependsOn: [
    createUserManagedIdentity
  ]
}

// [AVM Module] - Storage Account
module createStorageAccount 'br/public:avm/res/storage/storage-account:0.15.0' = {
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
      accessKey1: 'accessKey1'
      accessKey2: 'accessKey2'
      connectionString1: 'connectionString1'
      connectionString2: 'connectionString2'
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
module createLogAnalytics 'br/public:avm/res/operational-insights/workspace:0.9.1' = {
  name: 'create-log-analytics'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

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

// [AVM Module] - Application Insights
module createApplicationInsights 'br/public:avm/res/insights/component:0.4.2' = {
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

// [AVM Module] - Logic App
module createLogicApp 'br/public:avm/res/web/site:0.13.1' = {
  name: 'create-logic-app'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logicAppName
    kind: 'functionapp,workflowapp'
    location: location
    serverFarmResourceId: createAppServicePlan.outputs.resourceId
    appInsightResourceId: createApplicationInsights.outputs.resourceId
    keyVaultAccessIdentityResourceId: createUserManagedIdentity.outputs.resourceId
    storageAccountRequired: true
    storageAccountResourceId: createStorageAccount.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [
        createUserManagedIdentity.outputs.resourceId
      ]
    }
    appSettingsKeyValuePairs: {
      APP_KIND: 'workflowApp'
      FUNCTIONS_EXTENSION_VERSION: '~4'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet'
      APPLICATIONINSIGHTS_CONNECTION_STRING: createApplicationInsights.outputs.connectionString
      WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: '@Microsoft.KeyVault(VaultName=${keyvaultName};SecretName=connectionString1)'
      WEBSITE_CONTENTSHARE: logicAppName
    }
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.3'
      http20Enabled: true
      use32BitWorkerProcess: false
      alwaysOn: true
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
  }
}
