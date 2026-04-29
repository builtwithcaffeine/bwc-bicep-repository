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
@allowed(['dev', 'acc', 'prod'])
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
// Networking Mode

@description('Set to true to create a new VNet, NSG and Private DNS Zones. Set to false to reference an existing hub environment.')
param enableCreateVirtualNetwork bool

// Existing Hub Environment Parameters (required when enableCreateVirtualNetwork = false)

@description('Subscription ID of the existing shared hub VNet. Required when enableCreateVirtualNetwork is false.')
param sharedHubSubscriptionId string

@description('Resource Group name containing the existing shared hub VNet. Required when enableCreateVirtualNetwork is false.')
param sharedHubResourceGroupName string

@description('Name of the existing shared hub VNet. Required when enableCreateVirtualNetwork is false.')
param sharedHubVirtualNetworkName string

@description('Name of the existing shared/private-endpoint subnet. Required when enableCreateVirtualNetwork is false.')
param sharedHubSubnetShared string

@description('Name of the existing function app outbound subnet. Required when enableCreateVirtualNetwork is false.')
param sharedHubSubnetOutbound string

// Azure Private DNS Zones
// Private DNS Zone names for private endpoints

var privateDnsZoneArray array = [
  'privatelink.vaultcore.azure.net' // [0]
  'privatelink.blob.${environment().suffixes.storage}' // [1]
  'privatelink.queue.${environment().suffixes.storage}' // [2]
  'privatelink.table.${environment().suffixes.storage}' // [3]
  'privatelink.azurewebsites.net' // [4]
]

@description('Resource Group containing existing Private DNS Zones. Required when enableCreateVirtualNetwork is false.')
param sharedHubPrivateDnsZoneResourceGroupName string = ''

//
// Resource Names

var resourceGroupName = 'rg-x-${customerName}-example-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-${customerName}-example-${environmentType}-${locationShortCode}'
var networkSecurityGroupName = 'nsg-${customerName}-example-${environmentType}-${locationShortCode}'
var userManagedIdentityName = 'id-${customerName}-example-${environmentType}-${locationShortCode}'
var keyvaultName = 'kv-${customerName}-example-${environmentType}-${locationShortCode}'
var storageAccountName = 'st${customerName}example${environmentType}${locationShortCode}'
var logAnalyticsName = 'log-${customerName}-example-${environmentType}-${locationShortCode}'
var applicationInsightsName = 'appi-${customerName}-example-${environmentType}-${locationShortCode}'
var appServicePlanName = 'asp-${customerName}-example-${environmentType}-${locationShortCode}'
var functionAppName = 'func-${customerName}-example-${environmentType}-${locationShortCode}'

//
// Existing Hub Resource References (used when enableCreateVirtualNetwork = false)

resource existingHubVirtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = if (!enableCreateVirtualNetwork) {
  name: sharedHubVirtualNetworkName
  scope: resourceGroup(sharedHubSubscriptionId, sharedHubResourceGroupName)
}

resource existingHubSubnetShared 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = if (!enableCreateVirtualNetwork) {
  name: sharedHubSubnetShared
  parent: existingHubVirtualNetwork
}

resource existingHubSubnetOutbound 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = if (!enableCreateVirtualNetwork) {
  name: sharedHubSubnetOutbound
  parent: existingHubVirtualNetwork
}

resource existingPrivateDnsZoneVault 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (!enableCreateVirtualNetwork) {
  name: privateDnsZoneArray[0]
  scope: resourceGroup(sharedHubSubscriptionId, sharedHubPrivateDnsZoneResourceGroupName)
}

resource existingPrivateDnsZoneBlob 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (!enableCreateVirtualNetwork) {
  name: privateDnsZoneArray[1]
  scope: resourceGroup(sharedHubSubscriptionId, sharedHubPrivateDnsZoneResourceGroupName)
}

resource existingPrivateDnsZoneQueue 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (!enableCreateVirtualNetwork) {
  name: privateDnsZoneArray[2]
  scope: resourceGroup(sharedHubSubscriptionId, sharedHubPrivateDnsZoneResourceGroupName)
}

resource existingPrivateDnsZoneTable 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (!enableCreateVirtualNetwork) {
  name: privateDnsZoneArray[3]
  scope: resourceGroup(sharedHubSubscriptionId, sharedHubPrivateDnsZoneResourceGroupName)
}

resource existingPrivateDnsZoneWebsites 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (!enableCreateVirtualNetwork) {
  name: privateDnsZoneArray[4]
  scope: resourceGroup(sharedHubSubscriptionId, sharedHubPrivateDnsZoneResourceGroupName)
}

//
// Unified Resource ID Variables

var subnetSharedResourceId = enableCreateVirtualNetwork
  ? createVirtualNetwork.outputs.subnetResourceIds[0]
  : existingHubSubnetShared.id
var subnetOutboundResourceId = enableCreateVirtualNetwork
  ? createVirtualNetwork.outputs.subnetResourceIds[1]
  : existingHubSubnetOutbound.id
var privateDnsZoneVaultId = enableCreateVirtualNetwork
  ? createPrivateDnsZoneArray[0].outputs.resourceId
  : existingPrivateDnsZoneVault.id
var privateDnsZoneBlobId = enableCreateVirtualNetwork
  ? createPrivateDnsZoneArray[1].outputs.resourceId
  : existingPrivateDnsZoneBlob.id
var privateDnsZoneQueueId = enableCreateVirtualNetwork
  ? createPrivateDnsZoneArray[2].outputs.resourceId
  : existingPrivateDnsZoneQueue.id
var privateDnsZoneTableId = enableCreateVirtualNetwork
  ? createPrivateDnsZoneArray[3].outputs.resourceId
  : existingPrivateDnsZoneTable.id
var privateDnsZoneWebsitesId = enableCreateVirtualNetwork
  ? createPrivateDnsZoneArray[4].outputs.resourceId
  : existingPrivateDnsZoneWebsites.id

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

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.3' = if (enableCreateVirtualNetwork) {
  name: 'create-network-security-group'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: []
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.8.1' = if (enableCreateVirtualNetwork) {
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
  for dnsZone in privateDnsZoneArray: if (enableCreateVirtualNetwork) {
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
              privateDnsZoneResourceId: privateDnsZoneVaultId
            }
          ]
        }
        subnetResourceId: subnetSharedResourceId
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Key Vault Secrets User'
        principalType: 'ServicePrincipal'
        principalId: createUserManagedIdentity.outputs.principalId
      }
    ]
    tags: tags
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
        roleDefinitionIdOrName: 'Storage Blob Data Contributor'
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
              privateDnsZoneResourceId: privateDnsZoneBlobId
            }
          ]
        }
        subnetResourceId: subnetSharedResourceId
      }
      {
        service: 'queue'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneQueueId
            }
          ]
        }
        subnetResourceId: subnetSharedResourceId
      }
      {
        service: 'table'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDnsZoneTableId
            }
          ]
        }
        subnetResourceId: subnetSharedResourceId
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
    dataRetention: 90
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
    name: appServicePlanName
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
    virtualNetworkSubnetResourceId: subnetOutboundResourceId
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
      applicationTraffic: true
      contentShareTraffic: true
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
          value: '${createStorageAccount.outputs.serviceEndpoints.blob}app-package-${functionAppName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: createUserManagedIdentity.outputs.resourceId
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount:100
      }
    }
    siteConfig: {
      alwaysOn: false
      ftpsState: 'Disabled'
      http20Enabled: true
      minTlsVersion: '1.3'
      scmMinTlsVersion: '1.3'
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
              privateDnsZoneResourceId: privateDnsZoneWebsitesId
            }
          ]
        }
        subnetResourceId: subnetSharedResourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createAppServicePlan
  ]
}
