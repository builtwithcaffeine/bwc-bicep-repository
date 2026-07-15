import { managedIdentityAllType } from 'br/public:avm/utl/types/avm-common-types:0.7.0'
import { lockType } from 'br/public:avm/utl/types/avm-common-types:0.7.0'
import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.7.0'

// ============ //
// Parameters   //
// ============ //

@description('Required. Name of the Azure Monitor Workspace.')
@minLength(4)
@maxLength(44)
param name string

@description('Required. Location for all resources.')
param location string

@description('Optional. Tags of the resource.')
param tags object = {}

@description('Optional. Enables or disables public network access to the Azure Monitor Workspace.')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Optional. Flag that indicates whether to enable access using resource permissions.')
param enableAccessUsingResourcePermissions bool = false

@description('Optional. The managed service identities assigned to this resource.')
param managedIdentities managedIdentityAllType?

@description('Optional. The lock settings of the service.')
param lock lockType?

@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

// =========== //
// Variables   //
// =========== //

var formattedUserAssignedIdentities = reduce(
  map((managedIdentities.?userAssignedResourceIds ?? []), id => { '${id}': {} }),
  {},
  (cur, next) => union(cur, next)
)

var identity = !empty(managedIdentities)
  ? {
      type: (managedIdentities.?systemAssigned ?? false)
        ? (!empty(formattedUserAssignedIdentities) ? 'SystemAssigned,UserAssigned' : 'SystemAssigned')
        : (!empty(formattedUserAssignedIdentities) ? 'UserAssigned' : 'None')
      userAssignedIdentities: !empty(formattedUserAssignedIdentities) ? formattedUserAssignedIdentities : null
    }
  : null

var builtInRoleNames = {
  Contributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  'Monitoring Contributor': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749f88d5-cbae-40b8-bcfc-e573ddc772fa')
  'Monitoring Data Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b0d8363b-8ddd-447d-831f-62ca05bff136')
  'Monitoring Reader': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
  Owner: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
  Reader: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  'Role Based Access Control Administrator': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
  )
  'User Access Administrator': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
  )
}

// =========== //
// Resources   //
// =========== //

resource monitorWorkspace 'Microsoft.Monitor/accounts@2025-10-03' = {
  name: name
  location: location
  tags: tags
  identity: identity
  properties: {
    metrics: {
      enableAccessUsingResourcePermissions: enableAccessUsingResourcePermissions
    }
    publicNetworkAccess: publicNetworkAccess
  }
}

resource monitorWorkspace_lock 'Microsoft.Authorization/locks@2020-05-01' = if (!empty(lock ?? {}) && lock.?kind != 'None') {
  name: lock.?name ?? 'lock-${name}'
  properties: {
    level: lock.?kind ?? 'CanNotDelete'
    notes: lock.?kind == 'CanNotDelete'
      ? 'Cannot delete resource or child resources.'
      : 'Cannot delete or modify the resource or child resources.'
  }
  scope: monitorWorkspace
}

resource monitorWorkspace_roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (roleAssignment, index) in (roleAssignments ?? []): {
    name: roleAssignment.?name ?? guid(monitorWorkspace.id, roleAssignment.principalId, roleAssignment.roleDefinitionIdOrName)
    properties: {
      roleDefinitionId: builtInRoleNames[?roleAssignment.roleDefinitionIdOrName] ?? contains(
          roleAssignment.roleDefinitionIdOrName,
          '/providers/Microsoft.Authorization/roleDefinitions/'
        )
        ? roleAssignment.roleDefinitionIdOrName
        : subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAssignment.roleDefinitionIdOrName)
      principalId: roleAssignment.principalId
      description: roleAssignment.?description
      principalType: roleAssignment.?principalType
      condition: roleAssignment.?condition
      conditionVersion: roleAssignment.?condition != null ? (roleAssignment.?conditionVersion ?? '2.0') : null
      delegatedManagedIdentityResourceId: roleAssignment.?delegatedManagedIdentityResourceId
    }
    scope: monitorWorkspace
  }
]

// =========== //
// Outputs     //
// =========== //

@description('The resource ID of the monitor workspace.')
output resourceId string = monitorWorkspace.id

@description('The name of the monitor workspace.')
output name string = monitorWorkspace.name

@description('The location the resource was deployed into.')
output location string = monitorWorkspace.location

@description('The name of the resource group the monitor workspace was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The principal ID of the system assigned identity of the monitor workspace.')
output systemAssignedMIPrincipalId string? = monitorWorkspace.?identity.?principalId
