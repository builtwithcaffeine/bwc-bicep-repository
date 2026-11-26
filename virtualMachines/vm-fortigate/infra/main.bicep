targetScope = 'subscription'

@description('Customer name for the resources.')
param customerName string = 'bwc'

@description('Environment for the resources.')
param environment string = 'dev'

@description('Location for the resources.')
param location string = 'uksouth'

@description('Short code for the location.')
param locationShortCode string = 'uks'

@description('Deployment date for the resources.')
param deployedOn string = utcNow('yyyy-MM-dd')

@description('Deployed by for the resources.')
param deployedBy string = ''

@description('Tags type for the resources.')
type tagsType = {
  Environment: string
  DeployedOn: string
  DeployedBy: string
}

@description('Tags for the resources.')
param tags tagsType = {
  Environment: environment
  DeployedOn: deployedOn
  DeployedBy: deployedBy
}

@description('FortiGate system time zone.')
@allowed([
  'Europe/London'
  'Europe/Amsterdam'
])
param timeZone string = 'Europe/London'

// Variable Names
var resourceGroupName string = 'rg-${customerName}-fortigate-${environment}-${locationShortCode}'
var userManagedIdentityName string = 'id-${customerName}-fortigate-${environment}-${locationShortCode}'
var externalNetworkSecurityGroupName string = 'nsg-${customerName}-fortigate-external'
var internalNetworkSecurityGroupName string = 'nsg-${customerName}-fortigate-internal'
var virtualNetworkName string = 'vnet-${customerName}-fortigate-${environment}-${locationShortCode}'
var virtualMachineName string = 'vm-fortigate-${environment}-01'

@secure()
@description('Admin username for the FortiGate VM.')
param adminUser string

@secure()
@description('Admin password for the FortiGate VM.')
param adminPassword string

@description('External private IP for the FortiGate VM.')
var externalPrivateIp = '10.0.0.4'

@description('Internal private IP for the FortiGate VM.')
var internalPrivateIp = '10.0.0.36'

// Variable Settings
var virtualNetworkSettings = {
  addressPrefixes: [
    '10.0.0.0/24'
  ]
  subnets: [
    {
      name: 'snet-fortigate-external'
      addressPrefix: '10.0.0.0/27'
      networkSecurityGroupResourceId: createExternalNetworkSecurityGroup.outputs.resourceId
    }
    {
      name: 'snet-fortigate-internal'
      addressPrefix: '10.0.0.32/27'
      networkSecurityGroupResourceId: createInternalNetworkSecurityGroup.outputs.resourceId
    }
    {
      name: 'snet-fortigate-management'
      addressPrefix: '10.0.0.64/27'
    }
  ]
}

var externalNetworkSecuritySettings = {
  securityRules: [
    {
      name: 'AllowManagementPortal'
      properties: {
        access: 'Allow'
        direction: 'Inbound'
        priority: 980
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '443'
        sourceAddressPrefix: '*' // TODO: Restrict to a specific management IP range for WAF compliance
        destinationAddressPrefix: '*'
      }
    }
    {
      name: 'DenyManagementPortal'
      properties: {
        access: 'Deny'
        direction: 'Inbound'
        priority: 990
        protocol: 'Tcp'
        sourcePortRange: '*'
        destinationPortRange: '443'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
      }
    }
    {
      name: 'AllowAllInbound'
      properties: {
        access: 'Allow'
        direction: 'Inbound'
        priority: 1000
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
      }
    }
  ]
}

var internalNetworkSecuritySettings = {
  securityRules: [
    {
      name: 'AllowAllInbound'
      properties: {
        access: 'Allow'
        direction: 'Inbound'
        priority: 1000
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
      }
    }
    {
      name: 'AllowAllOutbound'
      properties: {
        access: 'Allow'
        direction: 'Outbound'
        priority: 1000
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '*'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
      }
    }
  ]
}

// Azure Verified Modules
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
    name: userManagedIdentityName
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createExternalNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.4' = {
  name: 'create-external-network-security-group-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: externalNetworkSecurityGroupName
    location: location
    securityRules: externalNetworkSecuritySettings.securityRules
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createInternalNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.4' = {
  name: 'create-internal-network-security-group-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: internalNetworkSecurityGroupName
    location: location
    securityRules: internalNetworkSecuritySettings.securityRules
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
    subnets: virtualNetworkSettings.subnets
    tags: tags
  }
}

module createFortigateVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.4' = {
  name: 'create-fortigate-vm-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualMachineName
    computerName: virtualMachineName
    location: location
    vmSize: 'Standard_D4s_v6'
    availabilityZone: 1
    adminUsername: adminUser
    adminPassword: adminPassword
    managedIdentities: {
      userAssignedResourceIds: [
        createUserManagedIdentity.outputs.resourceId
      ]
    }
    bootDiagnostics: true
    encryptionAtHost: true
    securityType: 'TrustedLaunch'
    secureBootEnabled: true
    vTpmEnabled: true
    osType: 'Linux'
    plan: {
      name: 'fortinet_fg-vm_payg_80_g2'
      publisher: 'fortinet'
      product: 'fortinet_fortigate-vm'
    }
    imageReference: {
      publisher: 'fortinet'
      offer: 'fortinet_fortigate-vm'
      sku: 'fortinet_fg-vm_payg_80_g2'
      version: '8.0.2'
    }
    customData: join(
      [
        'config system global'
        'set hostname ${virtualMachineName}'
        'set timezone "${timeZone}"'
        'set allow-traffic-redirect disable'
        'end'
        'config system sdn-connector'
        'edit AzureSDN'
        'set type azure'
        'next'
        'end'
        'config router static'
        'edit 1'
        'set gateway 10.0.0.1'
        'set device port1'
        'next'
        'edit 2'
        'set dst 10.0.0.0/24'
        'set gateway 10.0.0.33'
        'set device port2'
        'next'
        'end'
        'config system interface'
        'edit port1'
        'set mode static'
        'set ip ${externalPrivateIp}/27'
        'set description external'
        'set allowaccess ping ssh https'
        'next'
        'edit port2'
        'set mode static'
        'set ip ${internalPrivateIp}/27'
        'set description internal'
        'set allowaccess ping ssh https'
        'next'
        'end'
        'config system ntp'
        'set ntpsync enable'
        'set type fortiguard'
        'set syncinterval 60'
        'set server-mode enable'
        'set interface "port1"'
        'end'
      ],
      '\n'
    )
    osDisk: {
      name: '${virtualMachineName}-osdisk'
      createOption: 'FromImage'
      caching: 'ReadWrite'
      deleteOption: 'Detach'
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    dataDisks: [
      {
        name: '${virtualMachineName}-datadisk'
        lun: 0
        diskSizeGB: 30
        createOption: 'Empty'
        deleteOption: 'Detach'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    ]
    nicConfigurations: [
      {
        nicSuffix: '-nic-external'
        deleteOption: 'Delete'
        enableIPForwarding: true
        ipConfigurations: [
          {
            name: 'ipconfig-external'
            privateIPAllocationMethod: 'Static'
            privateIPAddress: externalPrivateIp
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
            pipConfiguration: {
              publicIpNameSuffix: '-pip'
              skuName: 'Standard'
              publicIPAllocationMethod: 'Static'
            }
          }
        ]
      }
      {
        nicSuffix: '-nic-internal'
        deleteOption: 'Delete'
        enableIPForwarding: true
        ipConfigurations: [
          {
            name: 'ipconfig-internal'
            privateIPAllocationMethod: 'Static'
            privateIPAddress: internalPrivateIp
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[1]
          }
        ]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
