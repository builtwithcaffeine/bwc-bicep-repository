@description('Create a Dev Center project')
param projectName string

@description('The description of the Dev Center project')
param projectDescription string = ''

@description('The ID of the Dev Center to create the project in')
param devCenterId string

@description('The location of the Dev Center project')
param location string = ''

@description('The maximum number of dev boxes per user')
param maxDevBoxesPerUser int = 0

@description('The types of catalog items to sync')
param catalogItemSyncTypes array = []

@description('Tags to apply to resources.')
param tags object = {}

resource project 'Microsoft.DevCenter/projects@2024-08-01-preview' = {
  name: projectName
  location: location
  tags: tags
  properties: {
    devCenterId: devCenterId
    description: projectDescription
    maxDevBoxesPerUser: maxDevBoxesPerUser
    displayName: projectName
    catalogSettings: {
      catalogItemSyncTypes: catalogItemSyncTypes
    }
  }
}
