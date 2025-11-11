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
param vmHostName string = 'vm-devops-agent-01'

param vmUserName string = 'ladm_bwcadmin'

@secure()
param vmUserPassword string = 'P@ssw0rd123!'

//
param resourceGroupName string = 'rg-x-${customerName}-bicep-${environmentType}-${locationShortCode}'

param virtualNetworkName string = 'vnet-${customerName}-${environmentType}-${locationShortCode}'

@description('AVM - Create Resource Group')
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

@description('Custom Module - Create Entra Id - Application Registration')
module createAppRegistration 'modules/microsoft-graph/applications/main.bicep' = {
  name: 'create-app-registration'
  scope: resourceGroup(resourceGroupName)
  params: {
    displayName: 'sp-${vmHostName}-devops-${environmentType}'
    appName: 'sp-${vmHostName}-devops-${environmentType}'
    signInAudience: 'AzureADMyOrg'
    webRedirectUris: ['https://myapp.contoso.com/auth/callback']
    requiredResourceAccess: [
      {
        resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
        resourceAccess: [
          {
            id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d' // User.Read
            type: 'Scope'
          }
        ]
      }
    ]
  }
  dependsOn: [
    createResourceGroup
  ]
}

@description('Custom Module - Create Entra Id - Application Registration')
module createServicePrincipal 'modules/microsoft-graph/servicePrincipals/main.bicep' = {
  name: 'ceeate-service-principal'
  scope: resourceGroup(resourceGroupName)
  params: {
    appId: createAppRegistration.outputs.applicationId
    displayName: 'sp-${vmHostName}-devops-${environmentType}'
    appRoleAssignmentRequired: true
    preferredSingleSignOnMode: 'oidc'
    tags: ['Production', 'WebApp']
  }
  dependsOn: [
    createAppRegistration
  ]
}

@description('Custom Module - Create Entra Id - Federated Identity Credential')
module federatedCredential 'modules/microsoft-graph/applications/federatedIdentityCredentials/main.bicep' = {
  name: 'create-federated-workflow-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    applicationId: createAppRegistration.outputs.objectId
    name: 'devops-${vmHostName}-${environmentType}'
    issuer: 'https://vstoken.dev.azure.com/499b84ac-1321-427f-aa17-267ca6975798' // Application Id Enterrpise App Azure Devops
    subject: 'sc://bwcdevops/sandbox/sp-${vmHostName}-devops-${environmentType}'
    audiences: ['api://AzureADTokenExchange']
    credentialDescription: 'Azure DevOps Hosted Agent Federated Credential'
  }
  dependsOn: [
    createAppRegistration
    createServicePrincipal
  ]
}

module createNetworkSecurityGroup 'br/public:avm/res/network/network-security-group:0.5.2' = {
  name: 'create-network-security-group'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'nsg-${virtualNetworkName}-${environmentType}'
    location: location
    securityRules: [
      {
        name: 'allowSSHInbound_TCP'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
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

module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.1' = {
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
        name: 'default'
        addressPrefix: '10.0.0.0/24'
        networkSecurityGroupResourceId: createNetworkSecurityGroup.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createVirtualMachine 'br/public:avm/res/compute/virtual-machine:0.20.0' = {
  name: 'create-virtual-machine'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vmHostName
    adminUsername: vmUserName
    adminPassword: vmUserPassword
    location: location
    osType: 'Linux'
    vmSize: 'Standard_D2ls_v5'
    availabilityZone: -1
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
