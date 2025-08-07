targetScope = 'subscription'

//
param customerName string
param environmentType string
param location string
param locationShortCode string
param deployedBy string
param publicIp string

param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

//
param resourceGroupName string
param networkSecurityGroupName string
param virtualNetworkName string
param subnetName string

param logAnalyticsWorkspaceName string
param windowsDataCollectionRuleName string

param vmHostName string
param vmUserName string

@secure()
param vmUserPassword string

param maintenanceConfiguration array


//
// Azure Verified Modules
//

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}


module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: [
      {
        name: 'ALLOW_MSRDP_INBOUND_TCP'
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

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 90
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createWindowsDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.4.2' = {
  scope: resourceGroup(resourceGroupName)
  name: 'create-windows-data-collection-rule'
  params: {
    name: windowsDataCollectionRuleName
    location: location
    dataCollectionRuleProperties: {
      kind: 'Windows'
      description: 'Data collection rule for VM Insights.'
      dataFlows: [
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
      destinations: {
        logAnalytics: [
          {
            workspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
            workspaceId: createLogAnalyticsWorkspace.outputs.logAnalyticsWorkspaceId
            name: createLogAnalyticsWorkspace.outputs.name
          }
        ]
      }
    }
  }
  dependsOn: [
      createLogAnalyticsWorkspace
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.17.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmHostName
    adminUsername: vmUserName
    adminPassword: vmUserPassword
    location: location
    osType: 'Windows'
    vmSize: 'Standard_D2ls_v6'
    availabilityZone: -1
    bootDiagnostics: true
    secureBootEnabled: true
    encryptionAtHost: true
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
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    extensionMonitoringAgentConfig: {
      dataCollectionRuleAssociations: [
        {
          dataCollectionRuleResourceId: createWindowsDataCollectionRule.outputs.resourceId
          name: 'SendMetricsToLAW'
        }
      ]
      enabled: true
      enableAutomaticUpgrade: true
    }
    tags: union(tags, { UpdateManagement: 'mc-${customerName}-${environmentType}-windows' })
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createMaintenanceConfiguration 'br/public:avm/res/maintenance/maintenance-configuration:0.3.1' = {
  name: 'create-maintenance-configuration'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'mc-${customerName}-${environmentType}-windows'
    location: location
    maintenanceScope: 'InGuestPatch'
    extensionProperties: maintenanceConfiguration[0].extensionProperties
    maintenanceWindow: maintenanceConfiguration[0].maintenanceWindow
    installPatches: maintenanceConfiguration[0].installPatches
    tags: tags
  }
  dependsOn: [
    createVirtualMachine
  ]
}

module assignMaintenanceConfiguration 'br/public:avm/res/maintenance/configuration-assignment:0.2.0' = {
  name: 'assign-maintenance-configuration'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'ma-${customerName}-${environmentType}-windows'
    location: location
    filter: {
      osTypes: [
        'Windows'
      ]
      resourceTypes: [
        'Virtual Machines'
      ]
      tagSettings: {
        filterOperator: 'All'
        tags: {
          UpdateManagement: [
              'mc-${customerName}-${environmentType}-windows'
          ]
        }
      }
    }
    maintenanceConfigurationResourceId: createMaintenanceConfiguration.outputs.resourceId
  }
  dependsOn: [
    createMaintenanceConfiguration
  ]
}


