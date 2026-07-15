targetScope = 'subscription'

param customerName string = 'bwc'
param environment string = 'dev'
param location string = 'uksouth'
param locationShortCode string = 'uks'

param deployedOn string = utcNow('yyyy-MM-dd')

type tagsType = {
  Environment: string
  DeployedOn: string
}

param tags tagsType = {
  Environment: environment
  DeployedOn: deployedOn
}

// Variable Names
var resourceGroupName string = 'rg-${customerName}-fortigate-${environment}-${locationShortCode}'
var userManagedIdentityName string = 'id-${customerName}-fortigate-${environment}-${locationShortCode}'
var networkSecurityGroupName string = 'nsg-${customerName}-fortigate-${environment}-${locationShortCode}'
var virtualNetworkName string = 'vnet-${customerName}-fortigate-${environment}-${locationShortCode}'
var virtualMachineName string = 'vm-fortigate-${environment}-${locationShortCode}'

@secure()
param adminUser string

@secure()
param adminPassword string

// Variable Settings
var virtualNetworkSettings = {
  addressPrefixes: [
    '10.0.0.0/24'
  ]
  subnets: [
    {
      name: 'snet-fortigate-external'
      addressPrefix: '10.0.0.0/27'
      networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
    }
    {
      name: 'snet-fortigate-internal'
      addressPrefix: '10.0.0.32/27'
    }
    {
      name: 'snet-fortigate-management'
      addressPrefix: '10.0.0.64/27'
    }
  ]
}

var networkSecuritySettings = {
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

// Azure Verified Modules
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

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'create-nsg-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: networkSecuritySettings.securityRules
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.9.0' = {
  name: 'create-vnet-${locationShortCode}'
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

module createFortigateVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.2' = {
  name: 'create-fortigate-vm-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: virtualMachineName
    location: location
    vmSize: 'Standard_D4ls_v5'
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
    osType: 'Linux'
    plan: {
      name: 'fortinet_fg-vm_payg_2023'
      publisher: 'fortinet'
      product: 'fortinet_fortigate-vm_v5'
    }
    imageReference: {
      publisher: 'fortinet'
      offer: 'fortinet_fortigate-vm_v5'
      sku: 'fortinet_fg-vm_payg_2023'
      version: '7.4.7'
    }
    osDisk: {
      name: '${virtualMachineName}-osdisk'
      createOption: 'FromImage'
      caching: 'ReadWrite'
      deleteOption: 'Detach'
      diskSizeGB: 2
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic-external'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig-external'
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
