param devcenters_dc6_bicep_devcenter_dev_name string = 'dc6-bicep-devcenter-dev'

resource devcenters_dc6_bicep_devcenter_dev_name_resource 'Microsoft.DevCenter/devcenters@2024-10-01-preview' = {
  name: devcenters_dc6_bicep_devcenter_dev_name
  location: 'westeurope'
  tags: {
    environmentType: 'dev'
    deployedBy: 'labadmin@builtwithcaffeine.cloud'
    deployedDate: '2025-01-20'
  }
  identity: {
    type: 'SystemAssigned'
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

resource devcenters_dc6_bicep_devcenter_dev_name_cat1 'Microsoft.DevCenter/devcenters/catalogs@2024-10-01-preview' = {
  parent: devcenters_dc6_bicep_devcenter_dev_name_resource
  name: 'cat1'
  properties: {
    adoGit: {
      uri: 'https://dev.azure.com/bwcdevops/GitOps/_git/sandbox'
      secretIdentifier: 'https://bwckvprod.vault.azure.net/secrets/authToken'
    }
    syncType: 'Scheduled'
  }
}

resource devcenters_dc6_bicep_devcenter_dev_name_acc 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = {
  parent: devcenters_dc6_bicep_devcenter_dev_name_resource
  name: 'acc'
  properties: {}
}

resource devcenters_dc6_bicep_devcenter_dev_name_dev 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = {
  parent: devcenters_dc6_bicep_devcenter_dev_name_resource
  name: 'dev'
  properties: {}
}

resource devcenters_dc6_bicep_devcenter_dev_name_prod 'Microsoft.DevCenter/devcenters/environmentTypes@2024-10-01-preview' = {
  parent: devcenters_dc6_bicep_devcenter_dev_name_resource
  name: 'prod'
  properties: {}
}

resource devcenters_dc6_bicep_devcenter_dev_name_Default 'Microsoft.DevCenter/devcenters/galleries@2024-10-01-preview' = {
  parent: devcenters_dc6_bicep_devcenter_dev_name_resource
  name: 'Default'
  properties: {
    galleryResourceId: devcenters_dc6_bicep_devcenter_dev_name_Default.id
  }
}
