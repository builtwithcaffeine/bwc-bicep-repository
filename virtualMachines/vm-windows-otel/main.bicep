targetScope = 'subscription'

// Pwsh Input Parameters
param customerName string

@allowed(['dev', 'acc', 'prod'])
param environmentType string

param location string

param locationShortCode string

param deployedOn string = utcNow('yyyy-MM-dd')

param deployedBy string

param tags object = {
  Environment: environmentType
  DeployedOn: deployedOn
  DeployedBy: deployedBy
}

@secure()
param adminUsername string

@secure()
param adminPassword string

param alertEmailAddress string

// Boolean Features
param enableBastionHost bool
param enableMetricAlerts bool

// Azure Resource Names
var resourceGroupName = 'rg-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var monitorWorkspaceName = 'mon-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var dataCollectionRuleName = 'MSVMOtel-windows-${environmentType}-${locationShortCode}'
var userManagedIdentityName = 'id-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var networkSecurityGroupName = 'nsg-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var bastionHostName = 'bas-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var actionGroupName = 'ag-${customerName}-vm-otel-${environmentType}-${locationShortCode}'
var virtualMachineName = 'vm-winotel-${environmentType}'

// Azure Resource Configuration and Settings

var virtualNetworkSettings = {
  addressPrefixes: [
    '10.0.0.0/24'
  ]
  subnets: [
    {
      name: 'AzureBastionSubnet'
      addressPrefix: '10.0.0.0/26'
    }
    {
      name: 'snet-compute'
      addressPrefix: '10.0.0.64/26'
      networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
    }
  ]
}

//
// Azure Verified Modules
//

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group-${locationShortCode}'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createUserManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'create-user-managed-identity-${locationShortCode}'
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

module createAzureMonitorWorkSpace 'modules/monitor-workspace/main.bicep' = {
  name: 'create-azure-monitor-workspace-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: monitorWorkspaceName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createDataCollectionRule 'br/public:avm/res/insights/data-collection-rule:0.11.0' = {
  name: 'create-data-collection-rule-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: dataCollectionRuleName
    location: location
    tags: tags
    dataCollectionRuleProperties: {
      kind: 'Windows'
      dataSources: {
        performanceCountersOTel: [
          {
            streams: ['Microsoft-OtelPerfMetrics']
            samplingFrequencyInSeconds: 60
            counterSpecifiers: [
              'system.filesystem.usage'
              'system.disk.io'
              'system.disk.operation_time'
              'system.disk.operations'
              'system.memory.usage'
              'system.network.io'
              'system.cpu.time'
              'system.network.dropped'
              'system.network.errors'
              'system.uptime'
              'process.uptime'
              'process.cpu.time'
              'process.cpu.utilization'
              'process.memory.usage'
              'process.memory.virtual'
              'process.memory.utilization'
              'process.disk.io'
              'process.disk.operations'
              'process.paging.faults'
              'process.open_file_descriptors'
              'process.threads'
              'process.handles'
              'process.context_switches'
              'process.signals_pending'
              'system.processes.count'
              'system.processes.created'
              'system.cpu.load_average.15m'
              'system.cpu.load_average.1m'
              'system.cpu.load_average.5m'
              'system.paging.faults'
              'system.paging.operations'
              'system.paging.usage'
              'system.paging.utilization'
              'system.cpu.frequency'
              'system.cpu.logical.count'
              'system.cpu.physical.count'
              'system.cpu.utilization'
              'system.disk.io_time'
              'system.disk.merged'
              'system.disk.pending_operations'
              'system.disk.weighted_io_time'
              'system.filesystem.inodes.usage'
              'system.filesystem.utilization'
              'system.network.connections'
              'system.network.packets'
              'system.network.conntrack.count'
              'system.network.conntrack.max'
              'system.memory.limit'
              'system.memory.page_size'
              'system.memory.utilization'
            ]
            name: 'OtelDataSource'
          }
        ]
      }
      destinations: {
        monitoringAccounts: [
          {
            accountResourceId: createAzureMonitorWorkSpace.outputs.resourceId
            name: 'MonitoringAccountDestination'
          }
        ]
      }
      dataFlows: [
        {
          streams: ['Microsoft-OtelPerfMetrics']
          destinations: ['MonitoringAccountDestination']
        }
      ]
    }
  }
  dependsOn: [
    createAzureMonitorWorkSpace
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'create-network-security-group-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: 'create-virtual-network-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkSettings.addressPrefixes
    subnets: virtualNetworkSettings.subnets
    tags: tags
  }
  dependsOn: [
    createNetworkSecurityGroup
  ]
}

module createBastionHost 'br/public:avm/res/network/bastion-host:0.8.2' = if (enableBastionHost) {
  name: 'create-bastion-host-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: bastionHostName
    location: location
    virtualNetworkResourceId: createVirtualNetwork.outputs.resourceId
    skuName: 'Developer'
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.2' = {
  name: 'create-virtual-machine-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualMachineName
    computerName: virtualMachineName
    location: location
    availabilityZone: 1
    adminUsername: adminUsername
    adminPassword: adminPassword
    managedIdentities: {
      userAssignedResourceIds: [
        createUserManagedIdentity.outputs.resourceId
      ]
    }
    bootDiagnostics: true
    encryptionAtHost: true
    vTpmEnabled: true
    secureBootEnabled: true
    securityType: 'TrustedLaunch'
    vmSize: 'Standard_D4lds_v6'
    osType: 'Windows'
    timeZone: 'GMT Standard Time' // Get-TimeZone (From Pwsh) Id
    imageReference: {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2025-datacenter-azure-edition'
      version: 'latest'
    }
    osDisk: {
      createOption: 'FromImage'
      deleteOption: 'Delete'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    dataDisks: [
      {
        lun: 0
        createOption: 'Empty'
        deleteOption: 'Delete'
        diskSizeGB: 128
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    ]
    nicConfigurations: [
      {
        name: 'nic-${virtualMachineName}'
        enableAcceleratedNetworking: true
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig-${virtualMachineName}'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[1]
          }
        ]
      }
    ]
    extensionAntiMalwareConfig: {
      enabled: true
      enableAutomaticUpgrade: true
    }
    extensionMonitoringAgentConfig: {
      enabled: true
      enableAutomaticUpgrade: true
      dataCollectionRuleAssociations: [
        {
          dataCollectionRuleResourceId: createDataCollectionRule.outputs.resourceId
          name: 'SendMetricsToLAW'
        }
      ]
    }
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
    createUserManagedIdentity
  ]
}

module createActionGroup 'br/public:avm/res/insights/action-group:0.5.0' = if (enableMetricAlerts) {
  name: 'create-action-group-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: actionGroupName
    groupShortName: take('vmi-ag-${environmentType}', 12)
    emailReceivers: [
      {
        name: 'Email-${alertEmailAddress}'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualMachine
  ]
}

module createMetricAlerts 'modules/metric-alerts/main.bicep' = if (enableMetricAlerts) {
  name: 'create-metric-alerts-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    virtualMachineResourceId: createVirtualMachine.outputs.resourceId
    virtualMachineName: virtualMachineName
    userAssignedIdentityResourceId: createUserManagedIdentity.outputs.resourceId
    actionGroupResourceId: createActionGroup!.outputs.resourceId
    tags: tags
  }
  dependsOn: [
    createActionGroup
  ]
}
