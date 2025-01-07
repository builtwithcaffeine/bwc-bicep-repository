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

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'createResourceGroup'
  params: {
    name: resourceGroupName
    location: location
  }
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
    // Required parameters
    dataCollectionRuleProperties: {
      dataFlows: [
        {
          destinations: [
            createLogAnalyticsWorkspace.outputs.name
          ]
          streams: [
            'Microsoft-InsightsMetrics'
          ]
        }
        {
          destinations: [
            createLogAnalyticsWorkspace.outputs.name
          ]
          streams: [
            'Microsoft-Syslog'
          ]
        }
      ]
      dataSources: {
        performanceCounters: [
          {
            counterSpecifiers: [
              'Logical Disk(*)\\% Free Inodes'
              'Logical Disk(*)\\% Free Space'
              'Logical Disk(*)\\% Used Inodes'
              'Logical Disk(*)\\% Used Space'
              'Logical Disk(*)\\Disk Read Bytes/sec'
              'Logical Disk(*)\\Disk Reads/sec'
              'Logical Disk(*)\\Disk Transfers/sec'
              'Logical Disk(*)\\Disk Write Bytes/sec'
              'Logical Disk(*)\\Disk Writes/sec'
              'Logical Disk(*)\\Free Megabytes'
              'Logical Disk(*)\\Logical Disk Bytes/sec'
              'Memory(*)\\% Available Memory'
              'Memory(*)\\% Available Swap Space'
              'Memory(*)\\% Used Memory'
              'Memory(*)\\% Used Swap Space'
              'Memory(*)\\Available MBytes Memory'
              'Memory(*)\\Available MBytes Swap'
              'Memory(*)\\Page Reads/sec'
              'Memory(*)\\Page Writes/sec'
              'Memory(*)\\Pages/sec'
              'Memory(*)\\Used MBytes Swap Space'
              'Memory(*)\\Used Memory MBytes'
              'Network(*)\\Total Bytes'
              'Network(*)\\Total Bytes Received'
              'Network(*)\\Total Bytes Transmitted'
              'Network(*)\\Total Collisions'
              'Network(*)\\Total Packets Received'
              'Network(*)\\Total Packets Transmitted'
              'Network(*)\\Total Rx Errors'
              'Network(*)\\Total Tx Errors'
              'Processor(*)\\% DPC Time'
              'Processor(*)\\% Idle Time'
              'Processor(*)\\% Interrupt Time'
              'Processor(*)\\% IO Wait Time'
              'Processor(*)\\% Nice Time'
              'Processor(*)\\% Privileged Time'
              'Processor(*)\\% Processor Time'
              'Processor(*)\\% User Time'
            ]
            name: 'perfCounterDataSource60'
            samplingFrequencyInSeconds: 60
            streams: [
              'Microsoft-InsightsMetrics'
            ]
          }
        ]
        syslog: [
          {
            facilityNames: [
              'auth'
              'authpriv'
            ]
            logLevels: [
              'Alert'
              'Critical'
              'Debug'
              'Emergency'
              'Error'
              'Info'
              'Notice'
              'Warning'
            ]
            name: 'sysLogsDataSource-debugLevel'
            streams: [
              'Microsoft-Syslog'
            ]
          }
          {
            facilityNames: [
              'cron'
              'daemon'
              'kern'
              'local0'
              'mark'
            ]
            logLevels: [
              'Alert'
              'Critical'
              'Emergency'
              'Error'
              'Warning'
            ]
            name: 'sysLogsDataSource-warningLevel'
            streams: [
              'Microsoft-Syslog'
            ]
          }
          {
            facilityNames: [
              'local1'
              'local2'
              'local3'
              'local4'
              'local5'
              'local6'
              'local7'
              'lpr'
              'mail'
              'news'
              'syslog'
            ]
            logLevels: [
              'Alert'
              'Critical'
              'Emergency'
              'Error'
            ]
            name: 'sysLogsDataSource-errLevel'
            streams: [
              'Microsoft-Syslog'
            ]
          }
        ]
      }
      description: 'Collecting Linux-specific performance counters and Linux Syslog'
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
