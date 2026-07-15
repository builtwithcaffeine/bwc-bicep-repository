targetScope = 'subscription'

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

@description('Azure Metadata Tags')
param tags object = {
  environmentType: environmentType
  deployedBy: deployedBy
  deployedDate: utcNow('yyyy-MM-dd')
}

//
// Bicep Deployment Variables

var tenantId = subscription().tenantId
var resourceGroupName = 'rg-x-${customerName}-iac-sql-${environmentType}-${locationShortCode}'
var sqlAdminGroupName = 'sec-${customerName}-sql-administrators-${environmentType}'
var sqlServerName = 'sql-${customerName}-iac-${environmentType}-${locationShortCode}'
var sqlDatabaseName = 'sqldb-${customerName}-iac-${environmentType}-${locationShortCode}'

//
//

var sqlScriptContent = loadTextContent('sql-scripts/sample-sales-schema.sql')

//
// Azure Verified Modules - No Hard Coded Values below this line!

module createResourceGroup 'br/public:avm/res/resources/resource-group:0.4.3' = {
  name: 'create-resource-group'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

module createSqlManagedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.0' = {
  name: 'create-sql-managed-identity'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'id-${sqlServerName}'
    location: location
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createEntraSqlAdminSecurityGroup 'modules/microsoft-graph/groups/main.bicep' = {
  name: 'create-entra-sql-admin-security-group'
  scope: resourceGroup(resourceGroupName)
  params: {
    groupName: sqlAdminGroupName
    displayName: 'SQL Administrators - ${customerName} ${environmentType}'
    mailEnabled: false
    securityEnabled: true
    mailNickname: sqlAdminGroupName

    memberIds: [
      createSqlManagedIdentity.outputs.principalId
    ]
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createSqlServer 'br/public:avm/res/sql/server:0.21.1' = {
  name: 'create-sql-server'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: sqlServerName
    location: location
    minimalTlsVersion: '1.2'
    administrators: {
      azureADOnlyAuthentication: true
      principalType: 'Group'
      administratorType: 'ActiveDirectory'
      tenantId: tenantId
      login: createEntraSqlAdminSecurityGroup.outputs.displayName
      sid: createEntraSqlAdminSecurityGroup.outputs.groupId
    }
    firewallRules: [
      {
        name: 'AllowAllWindowsAzureIps'
        startIpAddress: '0.0.0.0'
        endIpAddress: '0.0.0.0'
      }
    ]
    tags: tags
  }
  dependsOn: [
    createResourceGroup
  ]
}

module createSqlDatabase 'br/public:avm/res/sql/server/database:0.2.1' = {
  name: 'create-sql-database'
  scope: resourceGroup(resourceGroupName)
  params: {
    serverName: createSqlServer.outputs.name
    name: sqlDatabaseName
    location: location
    catalogCollation: 'DATABASE_DEFAULT'
    availabilityZone: -1
    maxSizeBytes: 2147483648 // 2 GB
    zoneRedundant: false
    sku: {
      name: 'Standard'
      tier: 'Standard'
      capacity: 10
    }
    tags: tags
  }
}

module deploymentScript 'br/public:avm/res/resources/deployment-script:0.5.2' = {
  name: 'execute-sql-deployment-script'
  scope: resourceGroup(resourceGroupName)
  params: {
    name: 'ds-${sqlServerName}'
    location: location
    kind: 'AzurePowerShell'
    azPowerShellVersion: '12.1'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    managedIdentities: {
      userAssignedResourceIds: [
        createSqlManagedIdentity.outputs.resourceId
      ]
    }
    environmentVariables: [
      {
        name: 'SQL_SERVER_FQDN'
        value: '${createSqlServer.outputs.name}${environment().suffixes.sqlServerHostname}'
      }
      {
        name: 'SQL_DATABASE_NAME'
        value: createSqlDatabase.outputs.name
      }
      {
        name: 'SQL_SCRIPT'
        value: sqlScriptContent
      }
      {
        name: 'SQL_TOKEN_RESOURCE'
        value: 'https://${substring(environment().suffixes.sqlServerHostname, 1)}/'
      }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'
      Write-Host "Acquiring access token for Azure SQL..."
      $tokenObj = Get-AzAccessToken -ResourceUrl $env:SQL_TOKEN_RESOURCE
      if ($tokenObj.Token -is [System.Security.SecureString]) {
        $accessToken = [System.Net.NetworkCredential]::new('', $tokenObj.Token).Password
      } else {
        $accessToken = $tokenObj.Token
      }

      $serverFqdn   = $env:SQL_SERVER_FQDN
      $databaseName = $env:SQL_DATABASE_NAME
      $sqlScript    = $env:SQL_SCRIPT

      Write-Host "Connecting to $serverFqdn / $databaseName ..."
      $conn = New-Object System.Data.SqlClient.SqlConnection
      $conn.ConnectionString = "Server=tcp:$serverFqdn,1433;Initial Catalog=$databaseName;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
      $conn.AccessToken = $accessToken
      $conn.Open()

      $batches = [System.Text.RegularExpressions.Regex]::Split($sqlScript, '(?im)^\s*GO\s*$')
      $batchNumber = 0
      foreach ($batch in $batches) {
        $trimmed = $batch.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        $batchNumber++
        Write-Host "Executing batch $batchNumber ..."
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $trimmed
        $cmd.CommandTimeout = 300
        [void]$cmd.ExecuteNonQuery()
      }

      $conn.Close()
      Write-Host "Completed $batchNumber batches successfully."
      $DeploymentScriptOutputs = @{
        status        = 'Sample sales schema deployed'
        batchesRun    = $batchNumber
        serverFqdn    = $serverFqdn
        databaseName  = $databaseName
      }
    '''
    tags: tags
  }
  dependsOn: [
    createSqlDatabase
  ]
}
