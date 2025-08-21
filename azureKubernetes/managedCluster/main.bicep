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
@description('AKS Admins Group ID')
param aksAdminsGroupId string

//
// Bicep Deployment Variables

var resourceGroupName = 'rg-x-${customerName}-aks-${environmentType}-${locationShortCode}'

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'create-log-analytics-workspace'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'law-aks-${customerName}-${environmentType}-${locationShortCode}'
    location: location
    skuName: 'PerGB2018'
    dataRetention: 30
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// Create Virtual Network
// module createVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.0' = {
//   name: 'create-virtual-network'
//   scope: resourceGroup(resourceGroupName)
//   params: {
//     name: 'vnet-aks-${customerName}-${environmentType}-${locationShortCode}'
//     location: location
//     addressPrefixes: [
//       '10.10.0.0/16'
//     ]
//     subnets: [
//       {
//         name: 'snet-aks'
//         addressPrefix: '10.10.0.0/22'
//       }
//     ]
//     tags: tags
//   }
//   dependsOn: [
//     createResourceGroup
//   ]
// }

// Create Aks Managed Identity
module createManagedIdentityControlAks 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity-aks-control'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-aks-${customerName}-${environmentType}-${locationShortCode}-control'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// Create Aks Managed Identity
module createManagedIdentityRunAks 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity-aks-run'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-aks-${customerName}-${environmentType}-${locationShortCode}-run'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// Create Aks Managed Identity
module createManagedIdentityCertMgrAks 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity-aks-cert-mgr'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-aks-cert-mgr-${customerName}-${environmentType}-${locationShortCode}'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

// Create Azure Kubernetes Cluster
module createAzureKubernetesCluster 'br/public:avm/res/container-service/managed-cluster:0.10.1' = {
  name: 'create-azure-kubernetes-cluster'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'aks-${customerName}-${environmentType}-${locationShortCode}'
    location: location
    skuName: 'Base'
    skuTier: 'Standard'
    kubernetesVersion: '1.31'
    networkPlugin: 'azure'
    networkPolicy: 'azure'
    outboundType: 'loadBalancer'
    loadBalancerSku: 'standard'
    disableRunCommand: true
    enableKeyvaultSecretsProvider: true
    enableContainerInsights: true
    monitoringWorkspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
    disableLocalAccounts: true
    enablePrivateCluster: false
    publicNetworkAccess: 'Enabled'
    aadProfile: {
      aadProfileManaged: true
      aadProfileEnableAzureRBAC: true
      aadProfileAdminGroupObjectIDs: [
        aksAdminsGroupId
      ]
    }
    managedIdentities: {
      userAssignedResourceIds: [
        createManagedIdentityControlAks.outputs.resourceId
      ]
    }
    primaryAgentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: 1
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableEncryptionAtHost: true
        //vnetSubnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
        nodeLabels: {
          nodetype: 'system'
        }
      }
    ]
    agentPools: [
      {
        name: 'user'
        mode: 'User'
        count: 1
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        enableEncryptionAtHost: true
        //vnetSubnetResourceId: createVirtualNetwork.outputs.subnetResourceIds[0]
        nodeLabels: {
          nodetype: 'user'
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    createManagedIdentityControlAks
  ]
}

// Assign Entra Id Security Group: Azure Kubernetes Service Cluster Admin
module aksClusterRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'aks-cluster-role-assignment'
  scope: resourceGroup(resourceGroupName)
  params: {
    resourceId: createAzureKubernetesCluster.outputs.resourceId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/3498e952-d568-435e-9b2c-8d77e338d7f7' // Azure Kubernetes Service RBAC Admin
    principalType: 'Group'
    principalId: aksAdminsGroupId
  }
  dependsOn: [
    createAzureKubernetesCluster
  ]
}

