targetScope = 'subscription'

//
param customerName string
param environmentType string
param location string
param locationShortCode string
param deployedBy string

param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

//
param resourceGroupName string = 'rg-x-${customerName}-aum-${environmentType}-${locationShortCode}'

//
module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.1' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  name: 'create-managed-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-azurepolicy-aum'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module assignManagedIdentity 'br/public:avm/res/authorization/role-assignment/sub-scope:0.1.0' = {
  name: 'assign-managed-identity'
  params: {
    roleDefinitionIdOrName: 'Contributor'
    principalId: createManagedIdentity.outputs.principalId
  }
  dependsOn: [
    createManagedIdentity
  ]
}

module createPolicyAssignmentLinux './modules/ptn/authentication/policy-assignment/sub-main.bicep' = {
  name: 'create-policy-assignment-linux'
  params: {
    subscriptionId: subscription().subscriptionId
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15'
    // Configure periodic checking for missing system updates on azure virtual machines
    name: '[iac] Configure Periodic Assessment | Linux'
    userAssignedIdentityId: createManagedIdentity.outputs.resourceId
    identity: 'UserAssigned'
    parameters: {
      assessmentMode: {
        value: 'AutomaticByPlatform'
      }
      osType: {
        value: 'Linux'
      }
      locations: {
        value: []
      }
      tagValues: {
        value: {}
      }
      tagOperator: {
        value: 'Any'
      }
    }
  }
  dependsOn: [
    assignManagedIdentity
  ]
}

module createRemediationPolicyAssignmentLinux './modules/ptn/policy-insights/remediation/modules/sub-main.bicep' = {
  name: 'create-remediation-policy-assignment-linux'
  params: {
    name: '[iac] Remediation Policy | Periodic Assessment | Linux'
    policyAssignmentId: createPolicyAssignmentLinux.outputs.resourceId
  }
  dependsOn: [
    createPolicyAssignmentLinux
  ]
}

module createPolicyAssignmentWindows './modules/ptn/authentication/policy-assignment/sub-main.bicep' = {
  name: 'create-policy-assignment-windows'
  params: {
    subscriptionId: subscription().subscriptionId
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15'
    // Configure periodic checking for missing system updates on azure virtual machines
    name: '[iac] Configure Periodic Assessment | Windows'
    userAssignedIdentityId: createManagedIdentity.outputs.resourceId
    identity: 'UserAssigned'
    parameters: {
      assessmentMode: {
        value: 'AutomaticByPlatform'
      }
      osType: {
        value: 'Windows'
      }
      locations: {
        value: []
      }
      tagValues: {
        value: {}
      }
      tagOperator: {
        value: 'Any'
      }
    }

  }
  dependsOn: [
    assignManagedIdentity
  ]
}

module createRemediationPolicyAssignment './modules/ptn/policy-insights/remediation/modules/sub-main.bicep' = {
  name: 'create-remediation-policy-assignment'
  params: {
    name: '[iac] Remediation Policy | Periodic Assessment | Windows'
    policyAssignmentId: createPolicyAssignmentWindows.outputs.resourceId
  }
  dependsOn: [
    createPolicyAssignmentWindows
  ]
}


