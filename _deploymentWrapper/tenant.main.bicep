targetScope = 'tenant'

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

@description('Parent management group name. Defaults to the tenant root management group name.')
param parentManagementGroupName string = tenant().tenantId

//
// Bicep Deployment Variables

var customerNameNormalized = toLower(replace(customerName, ' ', ''))
var managementGroupNameBase = 'mg-${customerNameNormalized}-${environmentType}-${locationShortCode}-${uniqueString(deployment().name)}'
var managementGroupName = length(managementGroupNameBase) <= 90
  ? managementGroupNameBase
  : substring(managementGroupNameBase, 0, 90)
var managementGroupDisplayName = 'MG :: ${customerName} :: ${environmentType} :: ${locationShortCode} :: ${deployedBy}'

module managementGroupModule 'br/public:avm/res/management/management-group:0.2.0' = {
  scope: managementGroup(parentManagementGroupName)
  params: {
    name: managementGroupName
    displayName: managementGroupDisplayName
    location: location
    enableTelemetry: false
    parentId: parentManagementGroupName
  }
}

output createdManagementGroupName string = managementGroupName
output createdManagementGroupResourceId string = managementGroupModule.outputs.resourceId
output deploymentLocation string = location
