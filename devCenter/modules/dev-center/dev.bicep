param devcenters_dc01_bicep_devcenter_dev_name string = 'dc01-bicep-devcenter-dev'
param galleries_gal01_externalid string = '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg01-bicep-devcenter-dev-weu/providers/Microsoft.Compute/galleries/gal01'

resource devcenters_dc01_bicep_devcenter_dev_name_resource 'Microsoft.DevCenter/devcenters@2024-10-01-preview' = {
  name: devcenters_dc01_bicep_devcenter_dev_name
  location: 'westeurope'
  tags: {
    environmentType: 'dev'
    deployedBy: 'labadmin@builtwithcaffeine.cloud'
    deployedDate: '2025-01-20'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg01-bicep-devcenter-dev-weu/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id01-bicep-devcenter-dev': {}
    }
  }
  properties: {
    projectCatalogSettings: {
      catalogItemSyncEnableStatus: 'Disabled'
    }
    networkSettings: {
      microsoftHostedNetworkEnableStatus: 'Disabled'
    }
    devBoxProvisioningSettings: {
      installAzureMonitorAgentEnableStatus: 'Disabled'
    }
  }
}

resource devcenters_dc01_bicep_devcenter_dev_name_acc 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = {
  parent: devcenters_dc01_bicep_devcenter_dev_name_resource
  name: 'acc'
  properties: {}
}

resource devcenters_dc01_bicep_devcenter_dev_name_dev 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = {
  parent: devcenters_dc01_bicep_devcenter_dev_name_resource
  name: 'dev'
  properties: {}
}

resource devcenters_dc01_bicep_devcenter_dev_name_prod 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = {
  parent: devcenters_dc01_bicep_devcenter_dev_name_resource
  name: 'prod'
  properties: {}
}

resource devcenters_dc01_bicep_devcenter_dev_name_Default 'Microsoft.DevCenter/devcenters/galleries@2024-10-01-preview' = {
  parent: devcenters_dc01_bicep_devcenter_dev_name_resource
  name: 'Default'
  properties: {
    galleryResourceId: devcenters_dc01_bicep_devcenter_dev_name_Default.id
  }
}

resource devcenters_dc01_bicep_devcenter_dev_name_gal01 'Microsoft.DevCenter/devcenters/galleries@2024-10-01-preview' = {
  parent: devcenters_dc01_bicep_devcenter_dev_name_resource
  name: 'gal01'
  properties: {
    galleryResourceId: galleries_gal01_externalid
  }
}

resource devcenters_dc01_bicep_devcenter_dev_name_devbox1 'Microsoft.DevCenter/devcenters/devboxdefinitions@2024-10-01-preview' = {
  parent: devcenters_dc01_bicep_devcenter_dev_name_resource
  name: 'devbox1'
  location: 'westeurope'
  properties: {
    imageReference: {
      id: '${devcenters_dc01_bicep_devcenter_dev_name_Default.id}/images/microsoftwindowsdesktop_windows-ent-cpc_win11-24h2-ent-cpc'
    }
    sku: {
      name: 'general_i_8c32gb256ssd_v2'
    }
    hibernateSupport: 'Disabled'
  }
}
