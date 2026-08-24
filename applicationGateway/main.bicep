targetScope = 'subscription'

//
// Imported Parameters

@description('Azure Location')
param location string

@description('Azure Location Short Code')
param locationShortCode string

@description('Customer Name')
param customerName string

@description('Environment Type')
param environmentType string

@description('User Deployment Name')
param deployedBy string

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

@description('Deploy a public Blob Storage container for Application Gateway custom status pages')
param enableAgwStorageStatus bool = false

//
// Bicep Deployment Variables

var resourceGroupName = 'rg-x-${customerName}-agw-shared-${environmentType}-${locationShortCode}'
var managedIdentityName = 'id-${applicationGatewayName}'
var storageAccountName = 'st${customerName}agwstatus${environmentType}${locationShortCode}'
var logAnalyticsWorkspaceName = 'log-${customerName}-agw-shared-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-${customerName}-agw-shared-${environmentType}-${locationShortCode}'
var networkSecurityGroupName = 'nsg-${customerName}-agw-shared-${environmentType}-${locationShortCode}'
var applicationGatewayWafPolicyName = 'wafpol-${customerName}-agw-shared-${environmentType}-${locationShortCode}'
var applicationGatewayPublicIpName = 'pip-${customerName}-agw-shared-${environmentType}-${locationShortCode}'
var applicationGatewayDnsFqdn = 'agw-${customerName}-shared-${environmentType}'
var applicationGatewayName = 'agw-${customerName}-shared-${environmentType}-${locationShortCode}-01'

//
// User-Defined Types

type subnetConfigType = {
  @description('Subnet name')
  name: string

  @description('Subnet address prefix in CIDR notation')
  addressPrefix: string
}

type virtualNetworkSettingsType = {
  @description('VNet address space prefixes')
  addressPrefixes: string[]

  @description('Subnet configurations')
  subnets: subnetConfigType[]
}

type managedRuleSetType = {
  @description('Rule set type (e.g. OWASP)')
  ruleSetType: string

  @description('Rule set version (e.g. 3.2)')
  ruleSetVersion: string
}

type wafManagedRulesType = {
  @description('Managed rule sets to apply')
  managedRuleSets: managedRuleSetType[]
}

type wafPolicySettingsType = {
  @description('WAF state: Enabled or Disabled')
  state: ('Enabled' | 'Disabled')

  @description('WAF mode: Detection or Prevention')
  mode: ('Detection' | 'Prevention')

  @description('Enforce file upload limits')
  fileUploadEnforcement: bool

  @description('Enforce request body limits')
  requestBodyEnforcement: bool

  @description('Enable request body inspection')
  requestBodyCheck: bool

  @description('Max request body size in KB')
  maxRequestBodySizeInKb: int

  @description('File upload limit in MB')
  fileUploadLimitInMb: int

  @description('Request body inspect limit in KB')
  requestBodyInspectLimitInKB: int
}

//
// Typed Parameters

@description('Virtual Network Settings')
param virtualNetworkSettings virtualNetworkSettingsType = {
  addressPrefixes: [
    '10.0.0.0/24'
  ]
  subnets: [
    {
      name: 'snet-agw'
      addressPrefix: '10.0.0.0/26'
    }
  ]
}

@description('WAF Configuration - Managed Rules')
param applicationGatewayManagedRules wafManagedRulesType = {
  managedRuleSets: [
    {
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
  ]
}

@description('WAF Configuration - Policy Settings')
param applicationGatewayPolicySettings wafPolicySettingsType = {
  state: 'Enabled'
  mode: toLower(environmentType) == 'prod' ? 'Prevention' : 'Detection'
  fileUploadEnforcement: true
  requestBodyEnforcement: true
  requestBodyCheck: true
  maxRequestBodySizeInKb: 256
  fileUploadLimitInMb: 128
  requestBodyInspectLimitInKB: 256
}

@description('Application Gateway - Autoscale Minimum Capacity')
@minValue(1)
@maxValue(125)
param autoscaleMinCapacity int = 1

@description('Application Gateway - Autoscale Maximum Capacity')
@minValue(1)
@maxValue(125)
param autoscaleMaxCapacity int = 2

@description('Log Analytics Workspace - SKU Name')
param logAnalyticsWorkspaceSkuName string = 'PerGB2018'

@description('Log Analytics Workspace - Data Retention in Days')
@minValue(30)
@maxValue(730)
param logAnalyticsWorkspaceRetentionInDays int = 30

@description('Application Gateway - SKU')
@allowed([
  'WAF_v2'
])
param applicationGatewaySku string = 'WAF_v2'

@description('Application Gateway - Enable HTTP/2')
param applicationGatewayEnableHttp2 bool = true

@description('Application Gateway - SSL Policy Type')
@allowed([
  'Predefined'
])
param applicationGatewaySslPolicyType string = 'Predefined'

@description('Application Gateway - SSL Policy Name')
@allowed([
  'AppGwSslPolicy20150501'
  'AppGwSslPolicy20170401'
  'AppGwSslPolicy20170401S'
  'AppGwSslPolicy20220101'
  'AppGwSslPolicy20220101S'
])
param applicationGatewaySslPolicyName string = 'AppGwSslPolicy20220101'

@description('Application Gateway - Default Listener Protocol')
@allowed([
  'Http'
])
param defaultListenerProtocol string = 'Http'

@description('Application Gateway - Default Listener Host Name')
param defaultListenerHostName string

@description('Application Gateway - Default Backend FQDN. Leave empty when no backend compute exists yet.')
param defaultBackendFqdn string = ''

@description('Application Gateway - Default Backend Protocol')
@allowed([
  'Http'
  'Https'
])
param defaultBackendProtocol string = 'Http'

@description('Application Gateway - Default Backend Port')
@minValue(1)
@maxValue(65535)
param defaultBackendPort int = 80

@description('Application Gateway - Default Health Probe Path')
param defaultHealthProbePath string = '/'

@description('Application Gateway - Default Health Probe Interval in Seconds')
@minValue(1)
param defaultHealthProbeIntervalInSeconds int = 30

@description('Application Gateway - Default Health Probe Timeout in Seconds')
@minValue(1)
param defaultHealthProbeTimeoutInSeconds int = 30

@description('Application Gateway - Default Health Probe Unhealthy Threshold')
@minValue(1)
@maxValue(20)
param defaultHealthProbeUnhealthyThreshold int = 3

@description('Application Gateway - Default Route Priority')
@minValue(1)
@maxValue(20000)
param defaultRoutePriority int = 100

//
// Variables

var networkSecurityRules = [
  {
    name: 'Allow-GatewayManager-Inbound'
    properties: {
      priority: 100
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '65200-65535'
      sourceAddressPrefix: 'GatewayManager'
      destinationAddressPrefix: '*'
    }
  }
  {
    name: 'Allow-AzureLoadBalancer-Inbound'
    properties: {
      priority: 110
      direction: 'Inbound'
      access: 'Allow'
      protocol: '*'
      sourcePortRange: '*'
      destinationPortRange: '*'
      sourceAddressPrefix: 'AzureLoadBalancer'
      destinationAddressPrefix: '*'
    }
  }
  {
    name: 'Allow-HTTP-Inbound'
    properties: {
      priority: 200
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '80'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
    }
  }
  {
    name: 'Allow-HTTPS-Inbound'
    properties: {
      priority: 210
      direction: 'Inbound'
      access: 'Allow'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: '443'
      sourceAddressPrefix: '*'
      destinationAddressPrefix: '*'
    }
  }
]

var applicationGatewayResourceIdPath = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}'
var hasDefaultBackend = !empty(defaultBackendFqdn)
var defaultListenerProtocolName = toLower(defaultListenerProtocol)

// Application Gateway child-resource naming standard:
// - Backend pool: bep-<protocol>-<hostname>
// - Backend settings: bes-<protocol>-<hostname>
// - Listener: <protocol>-<hostname>
// - Routing rule: rule-<protocol>-<hostname>
// - Health probe: probe-<protocol>-<hostname>
// - Redirect config: rdc-<purpose>
// - Rewrite rule set: rrs-<purpose>
// - URL path map: upm-<purpose>

var applicationGatewayDefaultHttpListenerName = '${defaultListenerProtocolName}-${defaultListenerHostName}'
var applicationGatewayDefaultBackendAddressPoolName = 'bep-${applicationGatewayDefaultHttpListenerName}'
var applicationGatewayDefaultBackendHttpSettingsName = 'bes-${applicationGatewayDefaultHttpListenerName}'
var applicationGatewayDefaultHealthProbeName = 'probe-${applicationGatewayDefaultHttpListenerName}'
var applicationGatewayDefaultRouteName = 'rule-${applicationGatewayDefaultHttpListenerName}'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.4' = {
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
    name: managedIdentityName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createStorageAccount 'br/public:avm/res/storage/storage-account:0.33.0' = if (enableAgwStorageStatus) {
  name: 'create-storage-account-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    blobServices: {
      containers: [
        {
          name: 'status-codes'
          publicAccess: 'Blob'
        }
      ]
    }
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'create-log-analytics-workspace-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    skuName: logAnalyticsWorkspaceSkuName
    dataRetention: logAnalyticsWorkspaceRetentionInDays
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'create-network-security-group-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: networkSecurityRules
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'create-virtual-network-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkSettings.addressPrefixes
    subnets: [
      {
        name: virtualNetworkSettings.subnets[0].name
        addressPrefix: virtualNetworkSettings.subnets[0].addressPrefix
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createApplicationGatewayWaf 'br/public:avm/res/network/application-gateway-web-application-firewall-policy:0.3.0' = {
  name: 'create-application-gateway-waf-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationGatewayWafPolicyName
    location: location
    managedRules: applicationGatewayManagedRules
    policySettings: applicationGatewayPolicySettings
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createApplicationGatewayPublicIp 'br/public:avm/res/network/public-ip-address:0.13.0' = {
  name: 'create-application-gateway-public-ip-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationGatewayPublicIpName
    skuName: 'Standard'
    skuTier: 'Regional'
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: applicationGatewayDnsFqdn
    }
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createApplicationGateway 'br/public:avm/res/network/application-gateway:0.10.0' = {
  name: 'create-application-gateway-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationGatewayName
    location: location
    enableHttp2: applicationGatewayEnableHttp2
    sku: applicationGatewaySku
    sslPolicyType: applicationGatewaySslPolicyType
    sslPolicyName: applicationGatewaySslPolicyName
    firewallPolicyResourceId: createApplicationGatewayWaf.outputs.resourceId
    autoscaleMinCapacity: autoscaleMinCapacity
    autoscaleMaxCapacity: autoscaleMaxCapacity
    frontendIPConfigurations: [
      {
        name: 'publicIPConfig1'
        properties: {
          publicIPAddress: {
            id: createApplicationGatewayPublicIp.outputs.resourceId
          }
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: 'gatewayIPConfig1'
        properties: {
          subnet: {
            id: createVirtualNetwork.outputs.subnetResourceIds[0]
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'frontendPort-http'
        properties: {
          port: 80
        }
      }
      {
        name: 'frontendPort-https'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: applicationGatewayDefaultBackendAddressPoolName
        properties: {
          backendAddresses: hasDefaultBackend ? [
            {
              fqdn: defaultBackendFqdn
            }
          ] : []
        }
      }
    ]
    probes: hasDefaultBackend ? [
      {
        name: applicationGatewayDefaultHealthProbeName
        properties: {
          protocol: defaultBackendProtocol
          host: defaultBackendFqdn
          path: defaultHealthProbePath
          interval: defaultHealthProbeIntervalInSeconds
          timeout: defaultHealthProbeTimeoutInSeconds
          unhealthyThreshold: defaultHealthProbeUnhealthyThreshold
        }
      }
    ] : []
    backendHttpSettingsCollection: [
      {
        name: applicationGatewayDefaultBackendHttpSettingsName
        properties: union({
          cookieBasedAffinity: 'Disabled'
          port: defaultBackendPort
          protocol: defaultBackendProtocol
        }, hasDefaultBackend ? {
          hostName: defaultBackendFqdn
          pickHostNameFromBackendAddress: false
          probe: {
            id: '${applicationGatewayResourceIdPath}/probes/${applicationGatewayDefaultHealthProbeName}'
          }
        } : {})
      }
    ]
    httpListeners: [
      {
        name: applicationGatewayDefaultHttpListenerName
        properties: {
          frontendIPConfiguration: {
            id: '${applicationGatewayResourceIdPath}/frontendIPConfigurations/publicIPConfig1'
          }
          frontendPort: {
            id: '${applicationGatewayResourceIdPath}/frontendPorts/frontendPort-http'
          }
          protocol: defaultListenerProtocol
          hostName: defaultListenerHostName
        }
      }
    ]
    requestRoutingRules: [
      {
        name: applicationGatewayDefaultRouteName
        properties: {
          backendAddressPool: {
            id: '${applicationGatewayResourceIdPath}/backendAddressPools/${applicationGatewayDefaultBackendAddressPoolName}'
          }
          backendHttpSettings: {
            id: '${applicationGatewayResourceIdPath}/backendHttpSettingsCollection/${applicationGatewayDefaultBackendHttpSettingsName}'
          }
          httpListener: {
            id: '${applicationGatewayResourceIdPath}/httpListeners/${applicationGatewayDefaultHttpListenerName}'
          }
          priority: defaultRoutePriority
          ruleType: 'Basic'
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
      }
    ]
    tags: tags
  }
}
