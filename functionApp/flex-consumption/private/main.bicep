targetScope = 'subscription'

//
// Default Values

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Customer Name')
param customerName string

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
param privateDnsZoneArray array = [
  'privatelink.vaultcore.azure.net' // [0]
  'privatelink.blob.core.windows.net' // [1]
  'privatelink.queue.core.windows.net' // [2]
  'privatelink.table.core.windows.net' // [3]
  'privatelink.azurewebsites.net' // [4]
]

//
//

param resourceGroupName string = 'rg-x-${customerName}-example-${environmentType}-${locationShortCode}'
param virtualNetworkName string = 'vnet-${customerName}-example-${environmentType}-${locationShortCode}'
param userManagedIdentityName string = 'id-${customerName}-example-${environmentType}-${locationShortCode}'
param keyvaultName string = 'kv-${customerName}-example-${environmentType}-${locationShortCode}'
param storageAccountName string = 'st${customerName}example${environmentType}${locationShortCode}'
param logAnalyticsName string = 'log-${customerName}-example-${environmentType}-${locationShortCode}'
param applicationInsightsName string = 'appi-${customerName}-example-${environmentType}-${locationShortCode}'
param functionAppName string = 'func-${customerName}-example-${environmentType}-${locationShortCode}'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'create-network-security-group'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'nsg-${customerName}-example-${environmentType}-${locationShortCode}'
    location: location
    securityRules: []
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'create-virtual-network'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: [
      '10.0.0.0/24'
    ]
    subnets: [
      {
        name: 'snet-shared'
        addressPrefix: '10.0.0.0/27'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: 'snet-funcapp-outbound'
        addressPrefix: '10.0.0.32/27'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
        delegation: 'Microsoft.App/environments'
      }
    ]
  }
  dependsOn: [
    createNetworkSecurityGroup
  ]
}

module createPrivateDnsZoneArray 'br/public:avm/res/network/private-dns-zone:0.8.1' = [
  for dnsZone in privateDnsZoneArray: {
    name: 'create-private-dns-zone-${dnsZone}'
    scope: resourceGroup(resourceGroupName)
    params: {
      name: dnsZone
      virtualNetworkLinks: [
        {
          name: 'link-${virtualNetworkName}'
          virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
          registrationEnabled: false
        }
      ]
      tags: tags
    }
    dependsOn: [
      createVirtualNetwork
    ]
  }
]

module createUserManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.0' = {
  name: 'create-user-managed-identity'
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

module createKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'create-key-vault'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: keyvaultName
    location: location
    enableSoftDelete: true
    softDeleteRetentionInDays: 14
    enableRbacAuthorization: true
    enablePurgeProtection: false
    publicNetworkAccess: 'Disabled'
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createPrivateDnsZoneArray[0].outputs.resourceId
            }
          ]
        }
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
      }
    ]
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createStorageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'create-storage-account'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
    publicNetworkAccess: 'Disabled'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Storage Blob Data Owner'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
      {
        roleDefinitionIdOrName: 'Storage Account Contributor'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
      {
        roleDefinitionIdOrName: 'Storage Queue Data Contributor'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
      {
        roleDefinitionIdOrName: 'Storage Table Data Contributor'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
    ]
    blobServices: {
      containers: [
        {
          name: 'app-package-${functionAppName}'
          publicAccess: 'None'
        }
        {
          name: 'azure-webjobs-hosts'
          publicAccess: 'None'
        }
        {
          name: 'azure-webjobs-secrets'
          publicAccess: 'None'
        }
      ]
    }
    privateEndpoints: [
      {
        service: 'blob'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createPrivateDnsZoneArray[1].outputs.resourceId
            }
          ]
        }
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createUserManagedIdentity
  ]
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 30
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createApplicationInsights 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'create-application-insights'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationInsightsName
    location: location
    workspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
    disableLocalAuth: true
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Monitoring Metrics Publisher'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createUserManagedIdentity
  ]
}

module createAppServicePlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'create-app-service-plan'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'asp-${customerName}-example-${environmentType}-${locationShortCode}'
    location: location
    kind: 'linux'
    skuName: 'FC1'
    skuCapacity: 1
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createFunctionApp 'br/public:avm/res/web/site:0.22.0' = {
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
      allTraffic: true
      applicationTraffic: false
      contentShareTraffic: true
      imagePullTraffic: false
      backupRestoreTraffic: false
    }
    functionAppConfig: {
      runtime: {
        name: 'python'
        version: '3.11'
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${createStorageAccount.outputs.serviceEndpoints.blob}app-package-${functionAppName}'
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
        name: 'appsettings'
        properties: {
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${createUserManagedIdentity.outputs.clientId};Authorization=AAD'
          APPLICATIONINSIGHTS_CONNECTION_STRING: createApplicationInsights.outputs.connectionString
          AzureWebJobsStorage__blobServiceUri: createStorageAccount.outputs.serviceEndpoints.blob
          AzureWebJobsStorage__queueServiceUri: createStorageAccount.outputs.serviceEndpoints.queue
          AzureWebJobsStorage__tableServiceUri: createStorageAccount.outputs.serviceEndpoints.table
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__clientId: createUserManagedIdentity.outputs.clientId
        }
      }
    ]
    privateEndpoints: [
      {
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: createPrivateDnsZoneArray[4].outputs.resourceId
            }
          ]
        }
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createAppServicePlan
  ]
}
