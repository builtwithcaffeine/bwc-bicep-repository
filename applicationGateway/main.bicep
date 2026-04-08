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

//
// Bicep Deployment Variables

var resourceGroupName = 'rg-x-${customerName}-agw-${environmentType}-${locationShortCode}'
var logAnalyticsWorkspaceName = 'log-${customerName}-agwdiags-${environmentType}-${locationShortCode}'
var virtualNetworkName = 'vnet-agw-${customerName}-${environmentType}-${locationShortCode}'
var networkSecurityGroupName = 'nsg-agw-${customerName}-${environmentType}-${locationShortCode}'
var applicationGatewayWafName = 'waf-agw-${customerName}-${environmentType}-${locationShortCode}'
var applicationGatewayPublicIpName = 'pip-agw-${customerName}-${environmentType}-${locationShortCode}'
var applicationGatewayDnsFqdn = 'agw-${customerName}-primary-${environmentType}'
var applicationGatewayName = 'agw-${customerName}-${environmentType}-${locationShortCode}'
var applicationGatewaySku = 'WAF_v2'

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
  mode: 'Detection'
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

@description('Application Gateway - Listener Host Name')
param listenerHostName string = 'demo.builtwithcaffeine.cloud'

//
// Variables

var enableHttp2 = true
var applicationGatewayResourceIdPath = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    dataRetention: 30
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'create-network-security-group'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: [
      {
        name: 'Allow-GatewayManager-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'GatewayManager'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '65200-65535'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '80'
        }
      }
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          priority: 210
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.2' = {
  name: 'create-virtual-network'
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

module createApplicationGatewayWaf 'br/public:avm/res/network/application-gateway-web-application-firewall-policy:0.2.0' = {
  name: 'create-application-gateway-waf'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationGatewayWafName
    location: location
    managedRules: applicationGatewayManagedRules
    policySettings: applicationGatewayPolicySettings
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createApplicationGatewayPublicIp 'br/public:avm/res/network/public-ip-address:0.9.0' = {
  name: 'create-application-gateway-public-ip'
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

module createApplicationGateway 'br/public:avm/res/network/application-gateway:0.7.0' = {
  name: 'create-application-gateway'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: applicationGatewayName
    location: location
    enableHttp2: enableHttp2
    sku: applicationGatewaySku
    sslPolicyType: 'Predefined'
    sslPolicyName: 'AppGwSslPolicy20220101'
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
        name: 'bp-demo.builtwithcaffeine.cloud'
      }
    ]
    probes: [
      {
        name: 'hp-demo.builtwithcaffeine.cloud'
        properties: {
          protocol: 'Http'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'bs-demo.builtwithcaffeine.cloud'
        properties: {
          cookieBasedAffinity: 'Disabled'
          port: 80
          protocol: 'Http'
          hostName: listenerHostName
          pickHostNameFromBackendAddress: true
          probe: {
            id: '${applicationGatewayResourceIdPath}/probes/hp-demo.builtwithcaffeine.cloud'
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-demo.builtwithcaffeine.cloud'
        properties: {
          frontendIPConfiguration: {
            id: '${applicationGatewayResourceIdPath}/frontendIPConfigurations/publicIPConfig1'
          }
          frontendPort: {
            id: '${applicationGatewayResourceIdPath}/frontendPorts/frontendPort-http'
          }
          hostName: listenerHostName
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule-demo.builtwithcaffeine.cloud'
        properties: {
          backendAddressPool: {
            id: '${applicationGatewayResourceIdPath}/backendAddressPools/bp-demo.builtwithcaffeine.cloud'
          }
          backendHttpSettings: {
            id: '${applicationGatewayResourceIdPath}/backendHttpSettingsCollection/bs-demo.builtwithcaffeine.cloud'
          }
          httpListener: {
            id: '${applicationGatewayResourceIdPath}/httpListeners/http-demo.builtwithcaffeine.cloud'
          }
          priority: 100
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
