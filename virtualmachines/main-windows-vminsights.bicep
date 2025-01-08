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
param userManagedIdentityName string = 'id-azure-policy-vminsights-win-${locationShortCode}'

@description('The Network Security Group Name')
param networkSecurityGroupName string = 'nsg-learning-windows-${locationShortCode}'

@description('The Log Analytics Workspace Name')
param logAnalyticsWorkspaceName string = 'law-learning-windows-${locationShortCode}'

@description('The Data Collection Rule Name')
param windowsDataCollectionRuleName string = 'MSVMI-vminsights-windows'

@description('The Virtual Network Name')
param virtualNetworkName string = 'vnet-learning-windows-${locationShortCode}'

@description('The Subnet Name')
param subnetName string = 'snet-learning-windows-${locationShortCode}'

@description('Azure Policy Name')
param windowsVirtualMachineInsightsPolicyName string = 'Configure Virtual Machine Insights for Windows'

@description('The Azure Policy Definition Id')
param windowsVirtualMachineInsightsPolicyDefinitionId string = '/providers/Microsoft.Authorization/policyDefinitions/244efd75-0d92-453c-b9a3-7d73ca36ed52'


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

module createResourceRoleAssignmentLogAnalyticsContributor 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'create-resource-role-assignment-law-contributor'
  scope: resourceGroup(resourceGroupName)
  params: {
    resourceId: createLogAnalyticsWorkspace.outputs.resourceId
    principalId: createUserManagedIdentity.outputs.principalId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Contributor
  }
  dependsOn: [
    createUserManagedIdentity
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
  }
    dependsOn: [
    createUserManagedIdentity
    createLogAnalyticsWorkspace
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

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: [
      {
        name: 'ALLOW_RDP_INBOUND_TCP'
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
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

// module createPolicyAzureMonitorWindows 'modules/authorization/policy-assignment/subscription/main.bicep' = {
//   name: 'create-policy-azure-monitor-vminsights-windows'
//   scope: subscription()
//   params: {
//     name: windowsVirtualMachineInsightsPolicyName
//     displayName: windowsVirtualMachineInsightsPolicyName
//     description: 'Monitor and secure your Windows virtual machines, virtual machine scale sets, and Arc machines by deploying the Azure Monitor Agent extension and associating the machines with a specified Data Collection Rule. Deployment will occur on machines with supported OS images (or machines matching the provided list of images) in supported regions.'
//     policyDefinitionId: windowsVirtualMachineInsightsPolicyDefinitionId
//     parameters: {
//       DcrResourceId: {
//         value: createWindowsDataCollectionRule.outputs.resourceId
//       }
//     }
//     location: location
//     identity: 'UserAssigned'
//     userAssignedIdentityId: createUserManagedIdentity.outputs.resourceId
//   }
//   dependsOn: [
//     createWindowsDataCollectionRule
//     createLogAnalyticsWorkspace
//   ]
// }

// module createPolicyAzureMonitorWindowsRemediation 'modules/policy-insights/remeditation/subscription/main.bicep' = {
//   name: 'create-policy-azure-monitor-vm-insights-windows-remediation'
//   scope: subscription()
//   params: {
//     name: 'remediate-windows-vm-insights'
//     policyAssignmentId: createPolicyAzureMonitorWindows.outputs.resourceId
//     policyDefinitionReferenceId: 'associatedatacollectionrulewindows'
//     location: location
//   }
//   dependsOn: [
//     createPolicyAzureMonitorWindows
//   ]
// }

// module createPolicyAzureMonitorAgentRemediation 'modules/policy-insights/remeditation/subscription/main.bicep' = {
//   name: 'create-policy-azure-monitor-agent-windows-remediation'
//   scope: subscription()
//   params: {
//     name: 'remediate-windows-vm-insights'
//     policyAssignmentId: createPolicyAzureMonitorWindows.outputs.resourceId
//     policyDefinitionReferenceId: 'deployAzureMonitorAgentWindows'
//     location: location
//   }
//   dependsOn: [
//     createPolicyAzureMonitorWindows
//   ]
// }
