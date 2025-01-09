targetScope = 'subscription'

// Imported Values

@description('The location of the resources')
param location string

@description('The short code of the location')
param locationShortCode string

@description('The Public IP Address')
param publicIp string

@description('The name of the virtual machine')
param vmHostName string = 'vm-linux-01'

@description('The Local User Account Name')
param vmUserName string

@description('The Local User Account Password')
@secure()
param vmUserPassword string

@description('The Resource Group Name')
param resourceGroupName string = 'rg-learning-linux-vminsights-${locationShortCode}-123'

@description('The User Assigned Managed Identity Name')
param userManagedIdentityName string = 'id-azure-policy-vminsights-lin-${locationShortCode}'

@description('The Network Security Group Name')
param networkSecurityGroupName string = 'nsg-learning-linux-${locationShortCode}'

@description('The Log Analytics Workspace Name')
param logAnalyticsWorkspaceName string = 'law-learning-linux-${locationShortCode}'

@description('The Data Collection Rule Name')
param linuxDataCollectionRuleName string = 'MSVMI-vminsights-linux'

@description('The Virtual Network Name')
param virtualNetworkName string = 'vnet-learning-linux-${locationShortCode}'

@description('The Subnet Name')
param subnetName string = 'snet-learning-linux-${locationShortCode}'

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
    createUserManagedIdentity
  ]
}

module createResourceRoleAssignmentLogAnalyticsContributor 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'create-resource-role-assignment-law-contributor'
  scope: resourceGroup(resourceGroupName)
  params: {
    resourceId: createLogAnalyticsWorkspace.outputs.resourceId
    principalId: createUserManagedIdentity.outputs.principalId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Contributor
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    createLogAnalyticsWorkspace
  ]
}

module createResourceRoleAssignmentMonitoringContributor 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'create-resource-role-assignment-monitoring-contributor'
  scope: resourceGroup(resourceGroupName)
  params: {
    resourceId: createLogAnalyticsWorkspace.outputs.resourceId
    principalId: createUserManagedIdentity.outputs.principalId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/749f88d5-cbae-40b8-bcfc-e573ddc772fa' // Monitoring Contributor
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    createLogAnalyticsWorkspace
  ]
}

module createLinuxDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.4.2' = {
  name: 'create-linux-data-collection-rule'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: linuxDataCollectionRuleName
    location: location
    dataCollectionRuleProperties: {
      kind: 'Linux'
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
    createUserManagedIdentity
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
          destinationPortRange: '22'
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
    createNetworkSecurityGroup
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
    osType: 'Linux'
    vmSize: 'Standard_B2ms'
    zone: 0
    bootDiagnostics: true
    secureBootEnabled: true
    vTpmEnabled: true
    securityType: 'TrustedLaunch'
    imageReference: {
      publisher: 'Canonical'
      offer: 'ubuntu-24_04-lts'
      sku: 'server'
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
    extensionMonitoringAgentConfig: {
      dataCollectionRuleAssociations: [
        {
          dataCollectionRuleResourceId: createLinuxDataCollectionRule.outputs.resourceId
          name: 'SendMetricsToLAW'
        }
      ]
      enabled: true
      enableAutomaticUpgrade: true
    }
  }
  dependsOn: [
    createVirtualNetwork
    createLinuxDataCollectionRule
  ]
}
