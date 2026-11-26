@description('Name of the Azure Kubernetes Fleet.')
param fleetName string

@description('Azure region where the Fleet is deployed.')
param location string

@description('Managed identity type for the Fleet.')
@allowed([
  'None'
  'SystemAssigned'
])
param identityType string = 'SystemAssigned'

@description('Tags to apply to the Fleet.')
param tags object = {}

type FleetMember = {
  name: string
  clusterResourceId: string
  group: string
}

@description('Existing AKS clusters to register as Fleet members. Each member must have a group for the update strategy.')
@minLength(0)
param members FleetMember[]

type FleetGate = {
  type: 'Approval'
  displayName: string?
}

type FleetUpdateGroup = {
  name: string
  maxConcurrency: string?
  beforeGates: FleetGate[]?
  afterGates: FleetGate[]?
}

type FleetUpdateStage = {
  name: string
  groups: FleetUpdateGroup[]
  maxConcurrency: string?
  afterStageWaitInSeconds: int?
  beforeGates: FleetGate[]?
  afterGates: FleetGate[]?
}

@description('Name of the Fleet Update Strategy.')
param updateStrategyName string = 'default'

@description('Ordered stages and groups for the Fleet Update Strategy. Group names must match the groups assigned to Fleet members.')
@minLength(0)
param updateStages FleetUpdateStage[]

resource fleet 'Microsoft.ContainerService/fleets@2026-06-01' = {
  name: fleetName
  location: location
  identity: {
    type: identityType
  }
  tags: tags
}

resource fleetMembers 'Microsoft.ContainerService/fleets/members@2026-06-01' = [for member in members: {
  parent: fleet
  name: member.name
  properties: {
    clusterResourceId: member.clusterResourceId
    group: member.group
  }
}]

resource fleetUpdateStrategy 'Microsoft.ContainerService/fleets/updateStrategies@2026-06-01' = if (!empty(updateStages)) {
  parent: fleet
  name: updateStrategyName
  properties: {
    strategy: {
      stages: updateStages
    }
  }
  dependsOn: [
    fleetMembers
  ]
}

@description('Resource ID of the Fleet.')
output fleetResourceId string = fleet.id

@description('Resource IDs of the registered Fleet members.')
output fleetMemberResourceIds array = [for i in range(0, length(members)): fleetMembers[i].id]

@description('Resource ID of the Fleet Update Strategy, or null when no stages are supplied.')
output updateStrategyResourceId string? = !empty(updateStages) ? fleetUpdateStrategy.id : null
