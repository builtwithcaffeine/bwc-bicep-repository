targetScope = 'subscription'

@description('SSH Public Key')
param sshPublicKey string

@description('Name of the customer')
param customerName string

@description('Location of the resources')
param location string = 'westeurope'

@description('Short code for the location')
param locationShortCode string = 'weu'

@description('Deployed By')
param deployedBy string

@description('User Account GUID')
param userAccountGuid string

@description('Environment type')
@allowed([
  'dev'
  'acc'
  'prd'
])
param environmentType string = 'dev'

@description('Tags for the resources')
var tags = {
  customer: customerName
  environment: environmentType
  location: location
  deployedBy: deployedBy
}

@description('Resource group names')
var resourceGroupNames = [
  'rg-${customerName}-hub-${environmentType}-${locationShortCode}'
  'rg-${customerName}-workload-${environmentType}-${locationShortCode}'
]

@description('Hub Virtual Network Name')
var hubVirtualNetworkName = 'vnet-${customerName}-hub-${environmentType}-${locationShortCode}'

var workloadVirtualNetworkName = 'vnet-${customerName}-workload-${environmentType}-${locationShortCode}'

@description('Azure Bastion Host Name')
var bastionHostName = 'bas-${customerName}-hub-${environmentType}-${locationShortCode}'

@description('Azure Bastion Sku')
@allowed([
  'Developer'
  'Basic'
  'Premium'
  'Standard'
])
param bastionSku string = 'Standard'

@description('The Log Analytics Workspace Name')
param logAnalyticsWorkspaceName string = 'law-learning-linux-${locationShortCode}'

@description('The Data Collection Rule Name')
param linuxDataCollectionRuleName string = 'MSVMI-vminsights-linux'

@description('The name of the virtual machine')
param vmHostName string = 'vm-linux-01'

@description('The username for the virtual machine')
param vmUserName string = 'azureuser'

// Azure Verified Modules
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = [
  for (resourceGroupName, i) in array(resourceGroupNames): {
    name: 'create-resource-group-${i}'
    scope: subscription()
    params: {
      name: resourceGroupName
      location: location
      tags: tags
    }
  }
]

// [AVM Module] - Hub Virtual Network
module createHubVirtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'create-hub-virtual-network'
  scope: resourceGroup(resourceGroupNames[0])
  params: {
    name: hubVirtualNetworkName
    location: location
    addressPrefixes: [
      '10.0.0.0/24'
    ]
    subnets: [
      {
        name: 'AzureBastionSubnet'
        addressPrefix: '10.0.0.0/28'
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [AVM Module] - Azure Bastion Public IP
module createAzureBastionPublicIp 'br/public:avm/res/network/public-ip-address:0.8.0' = {
  name: 'create-azure-bastion-public-ip'
  scope: resourceGroup(resourceGroupNames[0])
  params: {
    name: 'pip-${bastionHostName}'
    location: location
    skuName: 'Standard'
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// [AVM Module] - Azure Bastion Host
module createAzureBastionHost 'br/public:avm/res/network/bastion-host:0.6.0' = {
  name: 'create-azure-bastion-host'
  scope: resourceGroup(resourceGroupNames[0])
  params: {
    name: bastionHostName
    location: location
    skuName: bastionSku
    bastionSubnetPublicIpResourceId: createAzureBastionPublicIp.outputs.resourceId
    virtualNetworkResourceId: createHubVirtualNetwork.outputs.resourceId
    tags: tags
  }
  dependsOn: [
    createAzureBastionPublicIp
    createHubVirtualNetwork
  ]
}

// [AVM Module] - Workload
module createKeyVault 'br/public:avm/res/key-vault/vault:0.11.3' = {
  name: 'create-key-vault'
  scope: resourceGroup(resourceGroupNames[1])
  params: {
    name: 'kv-${customerName}-workload-${environmentType}-${locationShortCode}'
    location: location
    enableRbacAuthorization: true
    enablePurgeProtection: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    tags: tags
    roleAssignments: [
      {
        principalId: userAccountGuid
        roleDefinitionIdOrName: 'Key Vault Secrets Officer'
        principalType: 'User'
      }
    ]
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createWorkloadNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'create-workload-network-security-group'
  scope: resourceGroup(resourceGroupNames[1])
  params: {
    name: 'nsg-${customerName}-workload-${environmentType}-${locationShortCode}'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createWorkloadVirtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'create-workload-virtual-network'
  scope: resourceGroup(resourceGroupNames[1])
  params: {
    name: workloadVirtualNetworkName
    location: location
    addressPrefixes: [
      '10.1.0.0/24'
    ]
    subnets: [
      {
        name: 'subnet-${customerName}-workload-${environmentType}-${locationShortCode}'
        addressPrefix: '10.1.0.0/24'
        networkSecurityGroupResourceId: createWorkloadNetworkSecurityGroup.outputs.resourceId
      }
    ]
    peerings: [
      {
        name: 'peering-to-${workloadVirtualNetworkName}'
        remoteVirtualNetworkResourceId: createHubVirtualNetwork.outputs.resourceId
        remotePeeringEnabled: true
        allowVirtualNetworkAccess: true
        allowForwardedTraffic: true
        allowGatewayTransit: false
        useRemoteGateways: false
      }
    ]
    tags: tags
  }
  dependsOn: [
    createWorkloadNetworkSecurityGroup
  ]
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.9.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupNames[1])
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: 31
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createLinuxDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.4.2' = {
  name: 'create-linux-data-collection-rule'
  scope: resourceGroup(resourceGroupNames[1])
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
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.8.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupNames[1])
  params: {
    name: vmHostName
    adminUsername: vmUserName
    //adminPassword: vmUserPassword
    disablePasswordAuthentication: true
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
    publicKeys: [
      {
        path: '/home/${vmUserName}/.ssh/authorized_keys'
        keyData: sshPublicKey
      }
    ]
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            pipConfiguration: {
              name: '${vmHostName}-pip-01'
            }
            subnetResourceId: createWorkloadVirtualNetwork.outputs.subnetResourceIds[0]
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
    tags: tags
  }
  dependsOn: [
    createWorkloadVirtualNetwork
  ]
}
