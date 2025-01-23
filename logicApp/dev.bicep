param sites_logicappbwcdev_name string = 'logicappbwcdev'
param serverfarms_ASP_rgbwcdevelopment_9ffa_externalid string = '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg-bwc-development/providers/Microsoft.Web/serverfarms/ASP-rgbwcdevelopment-9ffa'

resource sites_logicappbwcdev_name_resource 'Microsoft.Web/sites@2024-04-01' = {
  name: sites_logicappbwcdev_name
  location: 'West Europe'
  tags: {
    'hidden-link: /app-insights-resource-id': '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg-bwc-development/providers/Microsoft.Insights/components/logicappbwcdev'
  }
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${sites_logicappbwcdev_name}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${sites_logicappbwcdev_name}.scm.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: serverfarms_ASP_rgbwcdevelopment_9ffa_externalid
    reserved: false
    isXenon: false
    hyperV: false
    dnsConfiguration: {}
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 1
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    ipMode: 'IPv4'
    vnetBackupRestoreEnabled: false
    customDomainVerificationId: '41519282DA788F7795F29A7C067669799BE53E90862D0E571E00D18A99051349'
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    endToEndEncryptionEnabled: false
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

resource sites_logicappbwcdev_name_ftp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: sites_logicappbwcdev_name_resource
  name: 'ftp'
  location: 'West Europe'
  tags: {
    'hidden-link: /app-insights-resource-id': '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg-bwc-development/providers/Microsoft.Insights/components/logicappbwcdev'
  }
  properties: {
    allow: false
  }
}

resource sites_logicappbwcdev_name_scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: sites_logicappbwcdev_name_resource
  name: 'scm'
  location: 'West Europe'
  tags: {
    'hidden-link: /app-insights-resource-id': '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg-bwc-development/providers/Microsoft.Insights/components/logicappbwcdev'
  }
  properties: {
    allow: false
  }
}

resource sites_logicappbwcdev_name_web 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: sites_logicappbwcdev_name_resource
  name: 'web'
  location: 'West Europe'
  tags: {
    'hidden-link: /app-insights-resource-id': '/subscriptions/b67e1026-b589-41e2-b41f-73f8803f71a0/resourceGroups/rg-bwc-development/providers/Microsoft.Insights/components/logicappbwcdev'
  }
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'Default.asp'
      'index.htm'
      'index.html'
      'iisstart.htm'
      'default.aspx'
      'index.php'
    ]
    netFrameworkVersion: 'v6.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: 'REDACTED'
    scmType: 'None'
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    alwaysOn: false
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: false
      }
    ]
    loadBalancing: 'LeastRequests'
    experiments: {
      rampUpRules: []
    }
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
    publicNetworkAccess: 'Enabled'
    cors: {
      supportCredentials: false
    }
    localMySqlEnabled: false
    managedServiceIdentityId: 20764
    ipSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
    http20Enabled: false
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    ftpsState: 'FtpsOnly'
    preWarmedInstanceCount: 1
    functionAppScaleLimit: 0
    functionsRuntimeScaleMonitoringEnabled: true
    minimumElasticInstanceCount: 1
    azureStorageAccounts: {}
  }
}

resource sites_logicappbwcdev_name_sites_logicappbwcdev_name_azurewebsites_net 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
  parent: sites_logicappbwcdev_name_resource
  name: '${sites_logicappbwcdev_name}.azurewebsites.net'
  location: 'West Europe'
  properties: {
    siteName: 'logicappbwcdev'
    hostNameType: 'Verified'
  }
}
