targetScope = 'subscription'

// Imported Values

@description('The location of the resources')
param location string

@description('The short code of the location')
param locationShortCode string

@description('The Public IP Address')
param publicIp string

@description('The name of the virtual machine')
param vmHostName string = 'vm-windows-01'

@description('The Local User Account Name')
param vmUserName string

@description('The Local User Account Password')
@secure()
param vmUserPassword string

@description('The Resource Group Name')
param resourceGroupName string = 'rg-learning-windows-${locationShortCode}'

@description('The User Assigned Managed Identity Name')
param userManagedIdentityName string = 'id-azure-policy-vminsights-${locationShortCode}'

@description('The Network Security Group Name')
param networkSecurityGroupName string = 'nsg-learning-windows-${locationShortCode}'

@description('The Log Analytics Workspace Name')
param logAnalyticsWorkspaceName string = 'law-learning-windows-${locationShortCode}'

@description('The Data Collection Rule Name')
param windowsDataCollectionRuleName string = 'MSVMI-dcr-windows'

@description('The Virtual Network Name')
param virtualNetworkName string = 'vnet-learning-windows-${locationShortCode}'

@description('The Subnet Name')
param subnetName string = 'snet-learning-windows-${locationShortCode}'

//
// Azure Verified Modules

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
  }
}

module createUserManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'createUserManagedIdentity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: userManagedIdentityName
    location: location
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createWindowsDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.4.2' = {
  name: 'create-windows-data-collection-rule'
  scope: resourceGroup(resourceGroupName)
  params: {
    // Required parameters
    dataCollectionRuleProperties: {
            dataFlows:[
              {
                streams: [
                  'Microsoft-InsightsMetrics'
                ]
                destinations: [
                  createLogAnalyticsWorkspace.outputs.name
                ]
              }
              {
                streams: [
                  'Microsoft-ServiceMap'
                ]
                destinations: [
                  createLogAnalyticsWorkspace.outputs.name
                ]
              }
            ]
            dataSources: {
              performanceCounters: [
                {
                  streams: [
                    'Microsoft-InsightsMetrics'
                  ]
                  samplingFrequencyInSeconds: 60
                  counterSpecifiers: [
                    '\\VmInsights\\DetailedMetrics'
                  ]
                  name: 'VMInsightsPerfCounters'
                }
              ]
              extensions: [
                {
                  streams: [
                    'Microsoft-ServiceMap'
                  ]
                  extensionName: 'DependencyAgent'
                  extensionSettings: {}
                  name: 'DependencyAgentDataSource'
                }
              ]
            }
      description: 'Collecting Windows-specific performance counters and Windows Event Logs'
      destinations: {
        azureMonitorMetrics: {
          name: 'azureMonitorMetrics-default'
        }
        logAnalytics: [
          {
            name: createLogAnalyticsWorkspace.outputs.name
            workspaceId: createLogAnalyticsWorkspace.outputs.logAnalyticsWorkspaceId
            workspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
          }
        ]
      }
      kind: 'Windows'
    }
    name: windowsDataCollectionRuleName
    location: location
    tags: {
      'hidden-title': 'This is visible in the resource name'
      kind: 'Windows'
      resourceType: 'Data Collection Rules'
    }
  }
  dependsOn: [
    createLogAnalyticsWorkspace
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: [
      {
        name: 'ALLOW_SSH_INBOUND_TCP'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: publicIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
    ]
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.5.1' = {
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
        name: subnetName
        addressPrefix: '10.0.0.0/24'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
    ]
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.8.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmHostName
    adminUsername: vmUserName
    adminPassword: vmUserPassword
    location: location
    osType: 'Windows'
    vmSize: 'Standard_B2ms'
    zone: 0
    bootDiagnostics: true
    secureBootEnabled: true
    vTpmEnabled: true
    securityType: 'TrustedLaunch'
    imageReference: {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition-hotpatch'
      version: 'latest'
    }
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            pipConfiguration: {
              name: '${vmHostName}-pip-01'
            }
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
          }
        ]
        nicSuffix: '-nic-01'
        enableAcceleratedNetworking: false
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

