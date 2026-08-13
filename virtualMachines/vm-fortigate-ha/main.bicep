targetScope = 'subscription'

// Pwsh Input Parameters
param customerName string = 'bwc'

@allowed(['dev', 'acc', 'prod'])
param environmentType string = 'dev'

param location string = 'westeurope'

param locationShortCode string = 'weu'

@description('CIDR range permitted to access the FortiGate management portal.')
param managementSourceAddressPrefix string = '*'

param deployedOn string = utcNow('yyyy-MM-dd')

param deployedBy string = 'labadmin@builtwithcaffeine.cloud'

param tags object = {
  Environment: environmentType
  DeployedOn: deployedOn
  DeployedBy: deployedBy
}

@description('Local admin username for both FortiGate VMs.')
@secure()
param adminUser string = 'bwccloudops'

@description('Local admin password for both FortiGate VMs.')
@secure()
param adminPassword string = 'P@ssw0rd123!'

var resourceGroupName string = 'rg-x-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var userManagedIdentityName string = 'id-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var networkSecurityGroupName string = 'nsg-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var virtualNetworkName string = 'vnet-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var externalLoadBalancerName string = 'lbe-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var internalLoadBalancerName string = 'lbi-${customerName}-shared-hub-${environmentType}-${locationShortCode}'
var primaryVirtualMachineName string = 'vm-${customerName}-fortigate-${environmentType}-01'
var secondaryVirtualMachineName string = 'vm-${customerName}-fortigate-${environmentType}-02'

// Static IP plan - referenced by the customdata-fgt-a.conf / customdata-fgt-b.conf cloud-init files.
// If you change any of these values, update the matching customdata-fgt-*.conf files to match.
var ipPlan = {
  externalGateway: '10.0.0.1'
  internalGateway: '10.0.0.33'
  hasyncGateway: '10.0.0.65'
  managementGateway: '10.0.0.97'
  internalLoadBalancerFrontend: '10.0.0.38'
  primary: {
    external: '10.0.0.4'
    internal: '10.0.0.36'
    hasync: '10.0.0.68'
    management: '10.0.0.100'
  }
  secondary: {
    external: '10.0.0.5'
    internal: '10.0.0.37'
    hasync: '10.0.0.69'
    management: '10.0.0.101'
  }
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
        sourceAddressPrefix: managementSourceAddressPrefix
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

//
// Azure Verified Modules
//

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = {
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
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: 'snet-fortigate-hasync'
        addressPrefix: '10.0.0.64/27'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
      {
        name: 'snet-fortigate-management'
        addressPrefix: '10.0.0.96/27'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createNetworkSecurityGroup
  ]
}

module createExternalLoadBalancer 'br/public:avm/res/network/load-balancer:0.8.0' = {
  name: 'create-external-load-balancer-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: externalLoadBalancerName
    location: location
    frontendIPConfigurations: [
      {
        name: 'publicIPConfig1'
        publicIPAddressConfiguration: {
          name: 'fortigate-ha-pip'
          publicIPAllocationMethod: 'Static'
          skuName: 'Standard'
          skuTier: 'Regional'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'beap-external'
        backendMembershipMode: 'NIC'
      }
    ]
    probes: [
      {
        name: 'probe-tcp-8008'
        protocol: 'Tcp'
        port: 8008
        intervalInSeconds: 5
        numberOfProbes: 2
      }
    ]
    loadBalancingRules: [
      {
        name: 'lbrule-http'
        frontendIPConfigurationName: 'publicIPConfig1'
        backendAddressPoolName: 'beap-external'
        probeName: 'probe-tcp-8008'
        protocol: 'Tcp'
        frontendPort: 80
        backendPort: 80
        enableFloatingIP: true
        disableOutboundSnat: false
        idleTimeoutInMinutes: 5
      }
      {
        name: 'lbrule-udp-10551'
        frontendIPConfigurationName: 'publicIPConfig1'
        backendAddressPoolName: 'beap-external'
        probeName: 'probe-tcp-8008'
        protocol: 'Udp'
        frontendPort: 10551
        backendPort: 10551
        enableFloatingIP: true
        disableOutboundSnat: false
        idleTimeoutInMinutes: 5
      }
      {
        name: 'lbrule-https'
        frontendIPConfigurationName: 'publicIPConfig1'
        backendAddressPoolName: 'beap-external'
        probeName: 'probe-tcp-8008'
        protocol: 'Tcp'
        frontendPort: 443
        backendPort: 443
        enableFloatingIP: false
        disableOutboundSnat: false
        idleTimeoutInMinutes: 5
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createInternalLoadBalancer 'br/public:avm/res/network/load-balancer:0.8.0' = {
  name: 'create-internal-load-balancer-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: internalLoadBalancerName
    location: location
    frontendIPConfigurations: [
      {
        name: 'internalFrontendIPConfig1'
        subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[1]
        privateIPAddress: ipPlan.internalLoadBalancerFrontend
      }
    ]
    backendAddressPools: [
      {
        name: 'beap-internal'
        backendMembershipMode: 'NIC'
      }
    ]
    probes: [
      {
        name: 'probe-tcp-8008'
        protocol: 'Tcp'
        port: 8008
        intervalInSeconds: 5
        numberOfProbes: 2
      }
    ]
    loadBalancingRules: [
      {
        name: 'lbrule-ha-ports'
        frontendIPConfigurationName: 'internalFrontendIPConfig1'
        backendAddressPoolName: 'beap-internal'
        probeName: 'probe-tcp-8008'
        protocol: 'All'
        frontendPort: 0
        backendPort: 0
        enableFloatingIP: true
        idleTimeoutInMinutes: 4
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createPrimaryFortigateVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.2' = {
  name: 'create-primary-fortigate-vm-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: primaryVirtualMachineName
    computerName: primaryVirtualMachineName
    location: location
    vmSize: 'Standard_F4s'
    timeZone: 'GMT Standard Time'
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
      name: 'fortinet_fg-vm_payg_2023_g2'
      publisher: 'fortinet'
      product: 'fortinet_fortigate-vm_v5'
    }
    imageReference: {
      publisher: 'fortinet'
      offer: 'fortinet_fortigate-vm_v5'
      sku: 'fortinet_fg-vm_payg_2023_g2'
      version: '7.6.5'
    }
    osDisk: {
      name: '${primaryVirtualMachineName}-osdisk'
      createOption: 'FromImage'
      caching: 'ReadWrite'
      deleteOption: 'Detach'
      diskSizeGB: 2
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    customData: loadTextContent('customdata-fgt-a.conf')
    nicConfigurations: [
      {
        nicSuffix: '-nic-external'
        deleteOption: 'Delete'
        enableIPForwarding: true
        ipConfigurations: [
          {
            name: 'ipconfig-external'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
            privateIPAddress: ipPlan.primary.external
            loadBalancerBackendAddressPools: [
              {
                id: createExternalLoadBalancer.outputs.backendpools[0].id
              }
            ]
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
            privateIPAddress: ipPlan.primary.internal
            loadBalancerBackendAddressPools: [
              {
                id: createInternalLoadBalancer.outputs.backendpools[0].id
              }
            ]
          }
        ]
      }
      {
        nicSuffix: '-nic-hasync'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig-hasync'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[2]
            privateIPAddress: ipPlan.primary.hasync
          }
        ]
      }
      {
        nicSuffix: '-nic-management'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig-management'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[3]
            privateIPAddress: ipPlan.primary.management
            pipConfiguration: {
              publicIpNameSuffix: '-mgmt'
              skuName: 'Standard'
              publicIPAllocationMethod: 'Static'
            }
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

module createSecondaryFortigateVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.22.2' = {
  name: 'create-secondary-fortigate-vm-${locationShortCode}'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: secondaryVirtualMachineName
    computerName: secondaryVirtualMachineName
    location: location
    vmSize: 'Standard_F4s'
    timeZone: 'GMT Standard Time'
    availabilityZone: 2
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
      name: 'fortinet_fg-vm_payg_2023_g2'
      publisher: 'fortinet'
      product: 'fortinet_fortigate-vm_v5'
    }
    imageReference: {
      publisher: 'fortinet'
      offer: 'fortinet_fortigate-vm_v5'
      sku: 'fortinet_fg-vm_payg_2023_g2'
      version: '7.6.5'
    }
    osDisk: {
      name: '${secondaryVirtualMachineName}-osdisk'
      createOption: 'FromImage'
      caching: 'ReadWrite'
      deleteOption: 'Detach'
      diskSizeGB: 2
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    customData: loadTextContent('customdata-fgt-b.conf')
    nicConfigurations: [
      {
        nicSuffix: '-nic-external'
        deleteOption: 'Delete'
        enableIPForwarding: true
        ipConfigurations: [
          {
            name: 'ipconfig-external'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
            privateIPAddress: ipPlan.secondary.external
            loadBalancerBackendAddressPools: [
              {
                id: createExternalLoadBalancer.outputs.backendpools[0].id
              }
            ]
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
            privateIPAddress: ipPlan.secondary.internal
            loadBalancerBackendAddressPools: [
              {
                id: createInternalLoadBalancer.outputs.backendpools[0].id
              }
            ]
          }
        ]
      }
      {
        nicSuffix: '-nic-hasync'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig-hasync'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[2]
            privateIPAddress: ipPlan.secondary.hasync
          }
        ]
      }
      {
        nicSuffix: '-nic-management'
        deleteOption: 'Delete'
        ipConfigurations: [
          {
            name: 'ipconfig-management'
            subnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[3]
            privateIPAddress: ipPlan.secondary.management
            pipConfiguration: {
              publicIpNameSuffix: '-mgmt'
              skuName: 'Standard'
              publicIPAllocationMethod: 'Static'
            }
          }
        ]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createPrimaryFortigateVirtualMachine
  ]
}
