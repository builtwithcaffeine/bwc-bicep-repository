targetScope = 'subscription'

param subscriptionId string = subscription().subscriptionId

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

@description('Resource Group Name')
param resourceGroupName string = 'rg-x-${customerName}-appgw-${environmentType}-${locationShortCode}'

@description('Virtual Network Name')
param virtualNetworkName string = 'vnet-agw-${customerName}-${environmentType}-${locationShortCode}'

@description('Virtual Network Address Prefixes')
param virtualNetworkAddressPrefixes array = [
  '10.0.0.0/24'
]

@description('Subnets Configuration')
param subnets array = [
  {
    name: 'subnet-appgw'
    addressPrefix: '10.0.0.0/29'
  }
]

@description('Application Gateway WAF Name')
param applicationGatewayWafName string = 'waf-agw-${customerName}-${environmentType}-${locationShortCode}'

@description('WAF Configuration - Managed Rules')
param applicationGatewayManagedRules object = {
  managedRuleSets: [
    {
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
  ]
}

@description('WAF Configuration - Policy Settings')
param applicationGatewayPolicySettings object = {
  state: 'Enabled'
  mode: 'Detection'
  fileUploadEnforcement: true
  requestBodyEnforcement: true
  requestBodyCheck: true
  maxRequestBodySizeInKb: 256
  fileUploadLimitInMb: 128
  requestBodyInspectLimitInKB: 256
}

@description('Application Gateway Public IP Name')
param applicationGatewayPublicIpName string = 'pip-agw-${customerName}-${environmentType}-${locationShortCode}'
param applicationGatewayDnsFqdn string = 'appgw-${customerName}-primary-${environmentType}'

@description('Application Gateway Name')
param applicationGatewayName string = 'agw-${customerName}-${environmentType}-${locationShortCode}'

param applicationGatewaySettings array = [
  {
    name: 'applicationGatewaySettings'
    properties: {
      enableHttp2: true
      sku: 'WAF_v2'
      firewallPolicyResourceId: ''
      autoscaleMinCapacity: 1
      autoscaleMaxCapacity: 3
      frontendPorts: [
        {
          name: 'frontendPort1'
          properties: {
            port: 80
          }
        }
      ]
      backendAddressPools: [
        {
          name: 'backendAddressPool1'
        }
      ]
      backendHttpSettingsCollection: [
        {
          name: 'backendHttpSettings1'
          properties: {
            cookieBasedAffinity: 'Disabled'
            port: 80
            protocol: 'Http'
          }
        }
      ]
      httpListeners: [
        {
          name: 'httpListener1'
          properties: {
            frontendIPConfiguration: {
              id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}/frontendIPConfigurations/publicIPConfig1'
            }
            frontendPort: {
              id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}/frontendPorts/frontendPort1'
            }
            hostName: 'www.contoso.com'
            protocol: 'Http'
          }
        }
      ]
      requestRoutingRules: [
        {
          name: 'requestRoutingRule1'
          properties: {
            backendAddressPool: {
              id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}/backendAddressPools/backendAddressPool1'
            }
            backendHttpSettings: {
              id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}/backendHttpSettingsCollection/backendHttpSettings1'
            }
            httpListener: {
              id: '/subscriptions/${subscriptionId}/resourceGroups/${resourceGroupName}/providers/Microsoft.Network/applicationGateways/${applicationGatewayName}/httpListeners/httpListener1'
            }
            priority: 100
            ruleType: 'Basic'
          }
        }
      ]
    }
  }
]

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
  name: 'createVirtualNetwork'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkAddressPrefixes
    subnets: subnets
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
      fqdn: '${applicationGatewayDnsFqdn}.${location}.cloudapp.azure.com'
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
          name: 'privateIPConfig1'
          properties: {
            subnet: {
              id: createVirtualNetwork.outputs.subnetResourceIds[0]
            }
          }
        }
      ]
    enableHttp2: applicationGatewaySettings[0].properties.enableHttp2
    sku: applicationGatewaySettings[0].properties.sku
    firewallPolicyResourceId: createApplicationGatewayWaf.outputs.resourceId
    autoscaleMinCapacity: applicationGatewaySettings[0].properties.autoscaleMinCapacity
    autoscaleMaxCapacity: applicationGatewaySettings[0].properties.autoscaleMaxCapacity
    backendAddressPools: applicationGatewaySettings[0].properties.backendAddressPools
    backendHttpSettingsCollection: applicationGatewaySettings[0].properties.backendHttpSettingsCollection
    frontendPorts: applicationGatewaySettings[0].properties.frontendPorts
    httpListeners: applicationGatewaySettings[0].properties.httpListeners
    requestRoutingRules: applicationGatewaySettings[0].properties.requestRoutingRules
    tags: tags
  }
  dependsOn: [
    createApplicationGatewayPublicIp
  ]
}
