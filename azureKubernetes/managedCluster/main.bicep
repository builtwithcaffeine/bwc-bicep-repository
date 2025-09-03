targetScope = 'subscription'

//
// Imported Parameters

param subscriptionId string = subscription().subscriptionId

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

// Helm Chart: Ingress NGINX

@description('The name of the Helm repository. For deploying the NGINX Ingress controller, it is set to ingress-nginx.')
param ingressHelmRepo string = 'ingress-nginx'

@description('The URL of the Helm repository. This is the source URL for the ingress-nginx Helm repository.')
param ingressHelmRepoURL string = 'https://kubernetes.github.io/ingress-nginx'

@description('The specific Helm chart to be used from the repository, pointed to deploy the ingress-nginx chart in the ingress-nginx repository.')
param ingressHelmApp string = 'ingress-nginx/ingress-nginx'

@description('The name to assign to the deployed Helm application, identifying the NGINX Ingress controller within the Kubernetes cluster.')
param ingressHelmAppName string = 'internal-ingress'

@description('Additional parameters for the Helm deployment command, such as namespace creation and naming.')
param ingressHelmAppParams string = '--namespace internal-ingress --create-namespace --set fullnameOverride=ingress-nginx'

@description('Base64 encoded values for the Helm chart, which can include configuration settings for the NGINX Ingress controller.')
var ingressHelmValuesBase64Encoded = loadFileAsBase64('yaml/internalIngress.yaml')

// External DNS Variables
@description('The name of the Helm repository. For deploying the External DNS, it is set to external-dns.')
param externalDNSHelmRepo string = 'external-dns'

@description('The URL of the Helm repository. This is the source URL for the externalDNS-nginx Helm repository.')
param externalDNSHelmRepoURL string = 'https://charts.bitnami.com/bitnami'

@description('The specific Helm chart to be used from the repository, pointed to deploy the externalDNS-nginx chart in the externalDNS-nginx repository.')
param externalDNSHelmApp string = 'external-dns/external-dns'

@description('The name to assign to the deployed Helm application, identifying the NGINX externalDNS controller within the Kubernetes cluster.')
param externalDNSHelmAppName string = 'external-dns'

//@description('Additional parameters for the Helm deployment command, such as namespace creation and naming.')
//var externalDNSHelmAppParams = '--namespace external-dns --create-namespace --version 6.11.1 --set provider=azure-private-dns --set txtOwnerId=${customerName}-ebase-aks --set policy=sync --set azure.resourceGroup=rg-e21-sharedservices --set azure.tenantId=${tenant().tenantId} --set azure.subscriptionId=${sharedSubscriptionId} --set azure.useManagedIdentityExtension=true --set azure.userAssignedIdentityID=${aksCluster.outputs.kubeletidentityClientId} --set domainFilters[0]=energy21.cloud'

// Cert Manager Variables

@description('The name of the Helm repository. For deploying the NGINX Ingress controller, it is set to ingress-nginx.')
param certManagerHelmRepo string = 'jetstack'

@description('The URL of the Helm repository. This is the source URL for the ingress-nginx Helm repository.')
param certManagerHelmRepoURL string = 'https://charts.jetstack.io'

@description('The specific Helm chart to be used from the repository, pointed to deploy the ingress-nginx chart in the ingress-nginx repository.')
param certManagerHelmApp string = 'jetstack/cert-manager'

@description('The name to assign to the deployed Helm application, identifying the NGINX Ingress controller within the Kubernetes cluster.')
param certManagerHelmAppName string = 'certmgr'

@description('Additional parameters for the Helm deployment command, such as namespace creation and naming.')
param certManagerHelmAppParams string = '--namespace cert-manager --create-namespace --set installCRDs=true'

@description('Base64 encoded values for the Helm chart, which can include configuration settings for the NGINX Ingress controller.')
var certManagerHelmValuesBase64Encoded = loadFileAsBase64('yaml/certManager.yaml')

@description('Base64 encoded manifest for the ClusterIssuer resource for cert-manager, which is used to issue certificates from Let\'s Encrypt.')
var clusterIssuerManifest = loadFileAsBase64('yaml/clusterIssuer-letsencrypt.yaml')

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

// Create Aks Managed Identity: Controller
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

// Create Aks Managed Identity: RunAs
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
    disableRunCommand: false
    enableKeyvaultSecretsProvider: true
    enableSecretRotation: true
    enableContainerInsights: true
    monitoringWorkspaceResourceId: createLogAnalyticsWorkspace.outputs.resourceId
    disableLocalAccounts: true
    enablePrivateCluster: false
    publicNetworkAccess: 'Enabled'
    enableOidcIssuerProfile: true
    enableWorkloadIdentity: true
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
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
    ]
    agentPools: [
      {
        name: 'user'
        mode: 'User'
        count: 2
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

// Create Aks Managed Identity: CertManager
module createManagedIdentityCertMgrAks 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity-aks-certmgmr'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-aks-${customerName}-${environmentType}-${locationShortCode}-certmgmr'
    location: location
    federatedIdentityCredentials: [
      {
        name: 'certmgr-aks-${customerName}-${environmentType}-${locationShortCode}'
        issuer: createAzureKubernetesCluster.outputs.oidcIssuerUrl!
        subject: 'system:serviceaccount:cert-manager:certmgr-cert-manager'
        audiences: [
          'api://AzureADTokenExchange'
        ]
      }
    ]
    tags: tags
  }
  dependsOn: [
    createAzureKubernetesCluster
  ]
}

@description('Assign DNS Zone Contributor role to the Cert Manager Managed Identity for the DNS Zone in Shared Services RG')
module assignCertMgrAksRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'assign-certmgr-aks-rbac'
  scope: resourceGroup('rg-builtwithcaffeine-hub-weu')
  params: {
    resourceId: '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg-builtwithcaffeine-hub-weu/providers/Microsoft.Network/dnszones/az.builtwithcaffeine.cloud'
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/befefa01-2a29-4197-83a8-272ff33ce314' // DNS Zone Contributor
    principalType: 'ServicePrincipal'
    principalId: createManagedIdentityCertMgrAks.outputs.principalId
  }
  dependsOn: [
    createManagedIdentityCertMgrAks
  ]
}

// Assign Entra Id Security Group: Azure Kubernetes Service Cluster Admin
module aksClusterRoleAssignmentEntraGroup 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'aks-cluster-role-assignment-entra-id'
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

// Assign Managed Identity - Azure Kubernetes Service Cluster Admin
module aksClusterRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'aks-cluster-role-assignment-aks-run'
  scope: resourceGroup(resourceGroupName)
  params: {
    resourceId: createAzureKubernetesCluster.outputs.resourceId
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/3498e952-d568-435e-9b2c-8d77e338d7f7' // Azure Kubernetes Service RBAC Admin
    principalType: 'ServicePrincipal'
    principalId: createManagedIdentityRunAks.outputs.principalId
  }
  dependsOn: [
    createAzureKubernetesCluster
  ]
}

// Deploy Nginx Ingress Controller using Helm Chart
module InstallInternalNginxIngress 'modules/aks-helm-install/main.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'aks-install-internal-ingress'
  params: {
    aksName: createAzureKubernetesCluster.outputs.name
    location: location
    newOrExistingManagedIdentity: 'existing'
    managedIdentityName: createManagedIdentityRunAks.outputs.name
    existingManagedIdentitySubId: subscriptionId
    existingManagedIdentityResourceGroupName: resourceGroupName
    helmRepo: ingressHelmRepo
    helmRepoURL: ingressHelmRepoURL
    helmApp: ingressHelmApp
    helmAppName: ingressHelmAppName
    helmAppParams: ingressHelmAppParams
    helmAppValues: ingressHelmValuesBase64Encoded
  }
  dependsOn: [
    createAzureKubernetesCluster
  ]
}

// Deploy External DNS using Helm Chart
// module InstallExternalDNS 'modules/aks-helm-install/main.bicep' = {
//   scope: resourceGroup(resourceGroupName)
//   name: 'aks-install-external-dns'
//   params: {
//     aksName: createAzureKubernetesCluster.outputs.name
//     location: location
//     newOrExistingManagedIdentity: 'existing'
//     managedIdentityName: createManagedIdentityRunAks.outputs.name
//     existingManagedIdentitySubId: subscriptionId
//     existingManagedIdentityResourceGroupName: resourceGroupName
//     helmRepo: externalDNSHelmRepo
//     helmRepoURL: externalDNSHelmRepoURL
//     helmApp: externalDNSHelmApp
//     helmAppName: externalDNSHelmAppName
//     //helmAppParams: externalDNSHelmAppParams
//   }
//   dependsOn: [
//     createAzureKubernetesCluster
//   ]
// }

module installCertManager 'modules/aks-helm-install/main.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'aks-install-cert-manager'
  params: {
    aksName: createAzureKubernetesCluster.outputs.name
    location: location
    newOrExistingManagedIdentity: 'existing'
    managedIdentityName: createManagedIdentityRunAks.outputs.name
    existingManagedIdentitySubId: subscriptionId
    existingManagedIdentityResourceGroupName: resourceGroupName
    helmRepo: certManagerHelmRepo
    helmRepoURL: certManagerHelmRepoURL
    helmApp: certManagerHelmApp
    helmAppName: certManagerHelmAppName
    helmAppParams: certManagerHelmAppParams
    helmAppValues: certManagerHelmValuesBase64Encoded
  }
  dependsOn: [
    createAzureKubernetesCluster
  ]
}

module installClusterIssuers 'modules/aks-clusterIssuer-apply/main.bicep' = {
  scope: resourceGroup(resourceGroupName)
  name: 'aks-install-clusterIssuer'
  params: {
    location: location
    aksName: createAzureKubernetesCluster.outputs.name
    newOrExistingManagedIdentity: 'existing'
    managedIdentityName: createManagedIdentityRunAks.outputs.name
    aksManagedId: createManagedIdentityCertMgrAks.outputs.clientId
    existingManagedIdentitySubId: subscriptionId
    existingManagedIdentityResourceGroupName: resourceGroupName
    kubeManifest: clusterIssuerManifest
  }
  dependsOn: [
    installCertManager
  ]
}
