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
param resourceGroupName string = 'rg-learning-linux-${locationShortCode}'

@description('The User Assigned Managed Identity Name')
param userManagedIdentityName string = 'id-azure-policy-vminsights-${locationShortCode}'

@description('The Network Security Group Name')
param networkSecurityGroupName string = 'nsg-learning-linux-${locationShortCode}'

@description('The Log Analytics Workspace Name')
param logAnalyticsWorkspaceName string = 'law-learning-linux-${locationShortCode}'

@description('The Data Collection Rule Name')
param linuxDataCollectionRuleName string = 'MSVMI-dcr-linux'

@description('The Virtual Network Name')
param virtualNetworkName string = 'vnet-learning-linux-${locationShortCode}'

@description('The Subnet Name')
param subnetName string = 'snet-learning-linux-${locationShortCode}'

@description('Azure Policy Name')
param linuxVirtualMachineInsightsPolicyName string = 'Configure Virtual Machine Insights for Linux'

@description('The Azure Policy Definition Id')
param linuxVirtualMachineInsightsPolicyDefinitionId string = '/providers/Microsoft.Authorization/policyDefinitions/58e891b9-ce13-4ac3-86e4-ac3e1f20cb07'

@description('Azure Policy Name')
param linuxVirtualMachineScaleSetInsightsPolicyName string = 'Configure Virtual Machine Scale Set Insights for Linux'

@description('The Azure Policy Definition Id')
param linuxVirtualMachineScaleSetInsightsPolicyDefinitionId string = '/providers/Microsoft.Authorization/policyDefinitions/050a90d5-7cce-483f-8f6c-0df462036dda'

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

module createLinuxDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.4.2' = {
  name: 'create-linux-data-collection-rule'
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
      kind: 'Linux'
    }
    name: linuxDataCollectionRuleName
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
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createLinuxVirtualMachineInsightsPolicy 'modules/authorization/policy-assignment/subscription/main.bicep' = {
  name: 'create-linux-vm-data-collection-configuration'
  scope: subscription()
  params: {
    name: 'virtual-machine-insights-linux'
    subscriptionId: subscription().subscriptionId
    displayName: linuxVirtualMachineInsightsPolicyName
    description: 'Automatically configure Virtual Machine Insights for linux virtual machines'
    policyDefinitionId: linuxVirtualMachineInsightsPolicyDefinitionId
    parameters: {
      DcrResourceId: {
        value: createLinuxDataCollectionRule.outputs.resourceId
      }
    }
    identity: 'UserAssigned'
    userAssignedIdentityId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${createUserManagedIdentity.outputs.name}'
    location: location
  }
  dependsOn: [
    createUserManagedIdentity
    createLinuxDataCollectionRule
  ]
}

module createLinuxVirtualMachineInsightsPolicyRemediation 'modules/policy-insights/remeditation/subscription/main.bicep' = {
  name: 'create-linux-vm-data-collection-configuration-remediation'
  scope: subscription()
  params: {
    name: 'virtual-machine-insights-linux-remediation'
    location: location
    policyAssignmentId: createLinuxVirtualMachineInsightsPolicy.outputs.resourceId
    policyDefinitionReferenceId: 'associatedatacollectionrulelinux'
    resourceCount: 10
    resourceDiscoveryMode: 'ReEvaluateCompliance'
    parallelDeployments: 10
    failureThresholdPercentage: '0.5'
    filtersLocations: []
  }
  dependsOn: [
    createLinuxVirtualMachineInsightsPolicy
  ]
}

module createLinuxVirtualMachineScaleSetInsightsPolicy 'modules/authorization/policy-assignment/subscription/main.bicep' = {
  name: 'create-linux-vmss-data-collection-configuration'
  scope: subscription()
  params: {
    name: 'virtual-machine-scale-set-insights-linux'
    subscriptionId: subscription().subscriptionId
    displayName: linuxVirtualMachineScaleSetInsightsPolicyName
    description: 'Automatically configure Virtual Machine Scale Set Insights for linux virtual machines'
    policyDefinitionId: linuxVirtualMachineScaleSetInsightsPolicyDefinitionId
    parameters: {
      DcrResourceId: {
        value: createLinuxDataCollectionRule.outputs.resourceId
      }
    }
    identity: 'UserAssigned'
    userAssignedIdentityId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${createUserManagedIdentity.outputs.name}'
    location: location
  }
  dependsOn: [
    createUserManagedIdentity
    createLinuxDataCollectionRule
  ]
}

module createLinuxVirtualMachineScaleSetInsightsPolicyRemediation 'modules/policy-insights/remeditation/subscription/main.bicep' = {
  name: 'create-linux-vmms-data-collection-configuration-remediation'
  scope: subscription()
  params: {
    name: 'virtual-machine-scale-set-insights-linux-remediation'
    location: location
    policyAssignmentId: createLinuxVirtualMachineScaleSetInsightsPolicy.outputs.resourceId
    policyDefinitionReferenceId: 'associatedatacollectionrulelinux'
    resourceCount: 10
    resourceDiscoveryMode: 'ReEvaluateCompliance'
    parallelDeployments: 10
    failureThresholdPercentage: '0.5'
    filtersLocations: []
  }
  dependsOn: [
    createLinuxVirtualMachineScaleSetInsightsPolicy
  ]
}
