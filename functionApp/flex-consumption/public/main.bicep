targetScope = 'subscription'

@description('Customer Name')
param customerName string = 'bicep'

@description('Environment Type')
@allowed(['dev', 'acc', 'prod'])
param environmentType string = 'dev'

@description('Azure Location')
param location string = 'westeurope'

@description('Azure Location Short Code')
param locationShortCode string = 'weu'

//
// Resource Names

@description('Resource Names')
param resourceGroupName string = 'rg-${customerName}-hugo-${environmentType}-${locationShortCode}'

@description('Managed Identity Name')
param managedIdentityName string = 'id-${customerName}-${environmentType}-${locationShortCode}'

@description('Storage Account Name')
param storageAccountName string = 'st${customerName}hugo${environmentType}${locationShortCode}'

@description('Log Analytics Workspace Name')
param logAnalyticsName string = 'log-${customerName}-hugo-${environmentType}-${locationShortCode}'

@description('Application Insights Name')
param applicationInsightsName string = 'appi-${customerName}-hugo-${environmentType}-${locationShortCode}'

@description('App Service Plan Name')
param appServicePlanName string = 'asp-${customerName}-hugo-${environmentType}-${locationShortCode}'

@description('Function App Name')
param functionAppName string = 'func-${customerName}-hugo-${environmentType}-${locationShortCode}'

//
// Azure Verified Modules
//

@description('Create Resource Group')
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
  }
}

@description('Create User Managed Identity')
module createUserManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.2' = {
  name: 'create-user-managed-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: managedIdentityName
    location: location
  }
  dependsOn: [
    createResourceGroup
  ]
}

@description('Create Storage Account')
module createStorageAccount 'br/public:avm/res/storage/storage-account:0.27.1' = {
  name: 'create-storage-account'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowSharedKeyAccess: false
    requireInfrastructureEncryption: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      containers: [
        {
          name: 'app-package-${functionAppName}'
          publicAccess: 'None'
          roleAssignments: [
            {
              roleDefinitionIdOrName: 'Storage Blob Data Contributor'
              principalType: 'ServicePrincipal'
              principalId: createUserManagedIdentity.outputs.principalId
            }
          ]
        }
        {
          name: 'azure-webjobs-hosts'
          publicAccess: 'None'
          roleAssignments: [
            {
              roleDefinitionIdOrName: 'Storage Blob Data Contributor'
              principalType: 'ServicePrincipal'
              principalId: createUserManagedIdentity.outputs.principalId
            }
          ]
        }
        {
          name: 'azure-webjobs-secrets'
          publicAccess: 'None'
          roleAssignments: [
            {
              roleDefinitionIdOrName: 'Storage Blob Data Contributor'
              principalType: 'ServicePrincipal'
              principalId: createUserManagedIdentity.outputs.principalId
            }
          ]
        }
      ]
    }
  }
  dependsOn: [
    createUserManagedIdentity
  ]
}

@description('Assign Role Based Authentication for User Managed Identity')
module storageBlobOwnerRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'storage-blob-owner-role-assignment'
  scope: resourceGroup(resourceGroupName)
  params: {
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
    resourceId: createStorageAccount.outputs.resourceId
    principalType: 'ServicePrincipal'
    principalId: createUserManagedIdentity.outputs.principalId
  }
  dependsOn: [
    createStorageAccount
  ]
}

@description('Create Log Analytics Workspace')
module createLogAnalytics 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'create-log-analytics'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 90
  }
  dependsOn: [
    createResourceGroup
  ]
}

@description('Create Application Insights')
module createApplicationInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'create-application-insights'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationInsightsName
    location: location
    applicationType: 'web'
    workspaceResourceId: createLogAnalytics.outputs.resourceId
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Monitoring Metrics Publisher'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
    ]
  }
  dependsOn: [
    createLogAnalytics
  ]
}

@description('Create App Service Plan - Flexible Consumption')
module createAppServicePlan 'br/public:avm/res/web/serverfarm:0.5.0' = {
  name: 'create-app-service-plan'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: appServicePlanName
    location: location
    kind: 'linux'
    skuName: 'FC1'
    skuCapacity: 1
  }
  dependsOn: [
    createResourceGroup
  ]
}

@description('Create Function App')
module createFunctionApp 'br/public:avm/res/web/site:0.19.3' = {
  name: 'create-function-app'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    serverFarmResourceId: createAppServicePlan.outputs.resourceId
    keyVaultAccessIdentityResourceId: createUserManagedIdentity.outputs.resourceId
    storageAccountRequired: true
    httpsOnly: true
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [
        createUserManagedIdentity.outputs.resourceId
      ]
    }
    basicPublishingCredentialsPolicies: [
      {
        name: 'scm'
        allow: false
      }
      {
        name: 'ftp'
        allow: false
      }
    ]
    outboundVnetRouting: {
      allTraffic: false
      applicationTraffic: false
      contentShareTraffic: false
      imagePullTraffic: false
      backupRestoreTraffic: false
    }
    functionAppConfig: {
      runtime: {
        name: 'powershell'
        version: '7.4'
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storageAccountName}.blob.core.windows.net/app-package-${functionAppName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: createUserManagedIdentity.outputs.resourceId
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 512
        maximumInstanceCount: 100
      }
    }
    siteConfig: {
      alwaysOn: false
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.3'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    configs: [
      {
        storageAccountUseIdentityAuthentication: true
        storageAccountResourceId: createStorageAccount.outputs.resourceId
        name: 'appsettings'
        properties: {
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${createUserManagedIdentity.outputs.clientId};Authorization=AAD'
          APPLICATIONINSIGHTS_CONNECTION_STRING: createApplicationInsights.outputs.connectionString
          AzureWebJobsStorage__clientId: createUserManagedIdentity.outputs.clientId
          AzureWebJobsStorage__credential: 'managedidentity'
        }
      }
    ]
  }
  dependsOn: [
    createAppServicePlan
  ]
}
