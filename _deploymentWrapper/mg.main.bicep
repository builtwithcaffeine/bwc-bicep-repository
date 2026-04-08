targetScope = 'managementGroup'

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

var allowedLocations = [
  'westeurope'
  'northeurope'
]

var allowedLocationsPolicyDefinitionId = '/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c'
var assignmentNameBase = 'pa${customerName}${environmentType}allowedlocations'
var assignmentDisplayName = '[Policy] - ${customerName} - Allowed Locations - ${environmentType}'
var assignmentName = length(assignmentNameBase) <= 24 ? assignmentNameBase : substring(assignmentNameBase, 0, 24)

var policyParameters = {
  listOfAllowedLocations: {
    value: allowedLocations
  }
}

module policyAssignment 'br/public:avm/ptn/authorization/policy-assignment:0.5.3' = {
  params: {
    name: assignmentName
    policyDefinitionId: allowedLocationsPolicyDefinitionId
    displayName: assignmentDisplayName
    description: 'Restricts deployments to allowed locations at management group scope.'
    metadata: tags
    parameters: policyParameters
    enableTelemetry: false
  }
}
