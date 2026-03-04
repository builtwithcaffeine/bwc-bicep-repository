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

@description('Cloud-init configuration as a string')
@allowed([
  'cloudInit.yaml'
])
param cloudInitFile string = 'cloudInit.yaml'

var cloudInitData = loadTextContent(cloudInitFile)

// var cloudInitData = '''
// #cloud-config
// package_update: true
// package_upgrade: true
// packages:
//   - nginx

// runcmd:
//   - systemctl enable nginx
//   - systemctl start nginx

// write_files:
//   - path: /var/www/html/index.html
//     permissions: '0644'
//     content: |
//       <html>
//         <head>
//           <title>Welcome to Nginx on Ubuntu 24.04 LTS!</title>
//         </head>
//         <body>
//           <h1>It works!</h1>
//         </body>
//       </html>
// '''

//
// Bicep Deployment Variables

@description('The Resource Group Name')
param resourceGroupName string = 'rg-x-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The Network Security Group Name')
param networkSecurityGroupName string = 'nsg-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The Virtual Network Name')
param virtualNetworkName string = 'vnet-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The Subnet Name')
param subnetName string = 'snet-${customerName}-openvpn-${environmentType}-${locationShortCode}'

@description('The Virtual Network Address Space')
param vnetAddressSpace array

@description('The Virtual Network Address Space')
param subnetAddressPrefix string

@description('The name of the virtual machine')
param vmHostName string = 'vm-linux-01'

@description('The Local User Account Name')
param vmUserName string

@description('The Local User Account Password')
@secure()
param vmUserPassword string

@description('Public IP Address')
param publicIpAddress string

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

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'createNetworkSecurityGroup'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: networkSecurityGroupName
    location: location
    securityRules: [
      {
        name: 'allowOpenVPN_UDP'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Udp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1194'
        }
      }
      {
        name: 'allowSSH_TCP'
        properties: {
          priority: 101
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: publicIpAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
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
    addressPrefixes: vnetAddressSpace
    subnets: [
      {
        name: subnetName
        addressPrefix: subnetAddressPrefix
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createNetworkSecurityGroup
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.21.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmHostName
    adminUsername: vmUserName
    adminPassword: vmUserPassword
    location: location
    osType: 'Linux'
    vmSize: 'Standard_D2als_v6'
    customData: cloudInitData
    availabilityZone: 1
    bootDiagnostics: true
    secureBootEnabled: true
    encryptionAtHost: true
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
        enableAcceleratedNetworking: true
        enableIPForwarding: true
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    tags: tags
  }
  dependsOn: [
    createVirtualNetwork
  ]
}
