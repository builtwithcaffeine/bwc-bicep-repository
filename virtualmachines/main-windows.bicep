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

@description('Azure Policy Name')
param windowsVirtualMachineInsightsPolicyName string = 'Configure Virtual Machine Insights for Windows'

@description('The Azure Policy Definition Id')
param windowsVirtualMachineInsightsPolicyDefinitionId string = '/providers/Microsoft.Authorization/policyDefinitions/244efd75-0d92-453c-b9a3-7d73ca36ed52'

@description('Azure Policy Name')
param windowsVirtualMachineScaleSetInsightsPolicyName string = 'Configure Virtual Machine Scale Set Insights for Windows'

@description('The Azure Policy Definition Id')
param windowsVirtualMachineScaleSetInsightsPolicyDefinitionId string = '/providers/Microsoft.Authorization/policyDefinitions/0a3b9bf4-d30e-424a-af6b-9a93f6f78792'

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

module createAzureRoleAssignment 'modules/authorization/role-assignment/subscription/main.bicep' = {
  name: 'create-azure-role-assignment'
  scope: subscription()
  params: {
    principalType: 'ServicePrincipal'
    roleDefinitionIdOrName: '/providers/Microsoft.Authorization/roleDefinitions/9980e02c-c2be-4d73-94e8-173b1dc7cf3c' // Virtual Machine Contributor
    principalId: createUserManagedIdentity.outputs.principalId
  }
  dependsOn: [
    createUserManagedIdentity
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
    dataCollectionRuleProperties: {
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
      description: 'Collect Operating System Diagnostic Data'
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

module createWindowsVirtualMachineInsightsPolicy 'modules/authorization/policy-assignment/subscription/main.bicep' = {
  name: 'create-windows-vm-data-collection-configuration'
  scope: subscription()
  params: {
    name: 'virtual-machine-insights-windows'
    subscriptionId: subscription().subscriptionId
    displayName: windowsVirtualMachineInsightsPolicyName
    description: 'Automatically configure Virtual Machine Insights for Windows virtual machines'
    policyDefinitionId: windowsVirtualMachineInsightsPolicyDefinitionId
    parameters: {
      DcrResourceId: {
        value: createWindowsDataCollectionRule.outputs.resourceId
      }
    }
    identity: 'UserAssigned'
    userAssignedIdentityId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${createUserManagedIdentity.outputs.name}'
    location: location
  }
  dependsOn: [
    createUserManagedIdentity
    createWindowsDataCollectionRule
  ]
}

module createWindowsVirtualMachineInsightsPolicyRemediation 'modules/policy-insights/remeditation/subscription/main.bicep' = {
  name: 'create-windows-vm-data-collection-configuration-remediation'
  scope: subscription()
  params: {
    name: 'virtual-machine-insights-windows-remediation'
    location: location
    policyAssignmentId: createWindowsVirtualMachineInsightsPolicy.outputs.resourceId
    policyDefinitionReferenceId: 'associatedatacollectionrulewindows'
    resourceCount: 10
    resourceDiscoveryMode: 'ExistingNonCompliant'
    parallelDeployments: 10
    failureThresholdPercentage: '0.5'
    filtersLocations: []
  }
  dependsOn: [
    createWindowsVirtualMachineInsightsPolicy
  ]
}

module createWindowsVirtualMachineScaleSetInsightsPolicy 'modules/authorization/policy-assignment/subscription/main.bicep' = {
  name: 'create-windows-vmss-data-collection-configuration'
  scope: subscription()
  params: {
    name: 'virtual-machine-scale-set-insights-windows'
    subscriptionId: subscription().subscriptionId
    displayName: windowsVirtualMachineScaleSetInsightsPolicyName
    description: 'Automatically configure Virtual Machine Scale Set Insights for Windows virtual machines'
    policyDefinitionId: windowsVirtualMachineScaleSetInsightsPolicyDefinitionId
    parameters: {
      DcrResourceId: {
        value: createWindowsDataCollectionRule.outputs.resourceId
      }
    }
    identity: 'UserAssigned'
    userAssignedIdentityId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${createUserManagedIdentity.outputs.name}'
    location: location
  }
  dependsOn: [
    createUserManagedIdentity
    createWindowsDataCollectionRule
  ]
}

module createWindowsVirtualMachineScaleSetInsightsPolicyRemediation 'modules/policy-insights/remeditation/subscription/main.bicep' = {
  name: 'create-windows-vmss-data-collection-configuration-remediation'
  scope: subscription()
  params: {
    name: 'virtual-machine-scale-set-insights-windows-remediation'
    location: location
    policyAssignmentId: createWindowsVirtualMachineScaleSetInsightsPolicy.outputs.resourceId
    policyDefinitionReferenceId: 'associatedatacollectionrulewindows'
    resourceCount: 10
    resourceDiscoveryMode: 'ExistingNonCompliant'
    parallelDeployments: 10
    failureThresholdPercentage: '0.5'
    filtersLocations: []
  }
  dependsOn: [
    createWindowsVirtualMachineScaleSetInsightsPolicy
  ]
}
