# Requires -Version 7.0

<##
.SYNOPSIS
    Collects read-only diagnostic information for an Azure Application Gateway.

.DESCRIPTION
    Displays the Application Gateway listeners, frontend ports, routing rules,
    backend pools, backend settings, probes, WAF policy, and backend health.
    A sanitized JSON report can be written for support investigations.

    This script does not modify Azure resources.

.PARAMETER SubscriptionId
    Azure subscription containing the Application Gateway.

.PARAMETER ResourceGroupName
    Resource group containing the Application Gateway.

.PARAMETER ApplicationGatewayName
    Name of the Application Gateway.

.PARAMETER OutputPath
    Optional path for the sanitized JSON diagnostic report. By default, a report
    is written to the current directory.

.EXAMPLE
    .\Invoke-AppGwDiagnostics.ps1 `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-example-agw-shared-dev-weu' `
        -ApplicationGatewayName 'agw-example-shared-dev-weu-01'

.NOTES
    Requires Azure CLI, Azure CLI Bicep is not required.
    The signed-in identity needs read access to the Application Gateway and its subnet.
#>

[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
  [string] $SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string] $ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string] $ApplicationGatewayName,

  [Parameter(Mandatory = $false)]
  [string] $OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command -Name 'az' -ErrorAction SilentlyContinue)) {
  throw "Azure CLI (az) is not installed or is not available on PATH."
}

$null = az account show --only-show-errors --output none 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "Not signed in to Azure CLI. Run 'az login' and try again."
}

if (-not $OutputPath) {
  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $OutputPath = Join-Path -Path (Get-Location) -ChildPath "appgw-diagnostics-$ApplicationGatewayName-$timestamp.json"
}

function Invoke-AzJson {
  param (
    [Parameter(Mandatory = $true)]
    [string[]] $Arguments,

    [Parameter(Mandatory = $true)]
    [string] $Description
  )

  $json = & az @Arguments --only-show-errors --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    $errorDetail = ($json | Select-Object -First 5) -join ' | '
    throw "Failed to retrieve $Description. Azure CLI returned exit code $LASTEXITCODE. $errorDetail"
  }

  if (-not $json) {
    return $null
  }

  return ($json -join [Environment]::NewLine) | ConvertFrom-Json
}

function Get-ResourceNameFromId {
  param (
    [AllowNull()]
    [string] $ResourceId
  )

  if ([string]::IsNullOrWhiteSpace($ResourceId)) {
    return $null
  }

  return ($ResourceId.TrimEnd('/') -split '/')[-1]
}

function Get-ResourceProperties {
  param (
    [Parameter(Mandatory = $true)]
    [object] $Resource
  )

  if ($Resource.PSObject.Properties['properties']) {
    return $Resource.properties
  }

  # Azure CLI commonly flattens child-resource properties in its output.
  return $Resource
}

function Get-ObjectPropertyValue {
  param (
    [AllowNull()]
    [object] $Object,

    [Parameter(Mandatory = $true)]
    [string] $Name
  )

  if ($null -eq $Object) {
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Get-ResourceReferenceName {
  param (
    [AllowNull()]
    [object] $Object,

    [Parameter(Mandatory = $true)]
    [string] $PropertyName
  )

  $reference = Get-ObjectPropertyValue -Object $Object -Name $PropertyName
  return Get-ResourceNameFromId (Get-ObjectPropertyValue -Object $reference -Name 'id')
}

function Get-ResourceIdSegmentValue {
  param (
    [AllowNull()]
    [string] $ResourceId,

    [Parameter(Mandatory = $true)]
    [string] $Segment
  )

  if ($ResourceId -and $ResourceId -match "/$Segment/([^/]+)") {
    return $Matches[1]
  }

  return $null
}

function Write-Section {
  param (
    [Parameter(Mandatory = $true)]
    [string] $Title
  )

  Write-Host ""
  Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Write-TableOrNone {
  param (
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [object[]] $Rows
  )

  if ($Rows.Count -eq 0) {
    Write-Host '(none)'
  } else {
    $Rows | Format-Table -AutoSize | Out-Host
  }
}

$commonArguments = @('--subscription', $SubscriptionId, '--resource-group', $ResourceGroupName, '--name', $ApplicationGatewayName)
$gateway = Invoke-AzJson -Arguments (@('network', 'application-gateway', 'show') + $commonArguments) -Description 'Application Gateway configuration'
# Azure CLI returns the Application Gateway resource properties at the root of
# the response. Child resources retain their nested .properties objects.
$properties = $gateway

$frontendPorts = @($properties.frontendPorts)
$frontendConfigurations = @($properties.frontendIPConfigurations)
$listeners = @($properties.httpListeners)
$routingRules = @($properties.requestRoutingRules)
$redirectConfigurations = @($properties.redirectConfigurations)
$backendPools = @($properties.backendAddressPools)
$backendSettings = @($properties.backendHttpSettingsCollection)
$probes = @($properties.probes)
$gatewayWafPolicyName = Get-ResourceNameFromId (Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $properties -Name 'firewallPolicy') -Name 'id')

Write-Section 'Application Gateway'
[pscustomobject]@{
  ResourceGroup = $ResourceGroupName
  Name = $gateway.name
  Sku = $properties.sku.name
  Location = $gateway.location
  OperationalState = $properties.operationalState
  ProvisioningState = $properties.provisioningState
  WafPolicy = $gatewayWafPolicyName
  AutoscaleMinCapacity = $properties.autoscaleConfiguration.minCapacity
  AutoscaleMaxCapacity = $properties.autoscaleConfiguration.maxCapacity
} | Format-Table -AutoSize | Out-Host

Write-Section 'Frontend Ports'
Write-TableOrNone -Rows @($frontendPorts | ForEach-Object {
    $portProperties = Get-ResourceProperties $_
    [pscustomobject]@{
      Name = $_.name
      Port = $portProperties.port
    }
  })

Write-Section 'HTTP Listeners'
Write-TableOrNone -Rows @($listeners | ForEach-Object {
    $listenerProperties = Get-ResourceProperties $_
    [pscustomobject]@{
      Name = $_.name
      Protocol = $listenerProperties.protocol
      HostName = $listenerProperties.hostName
      FrontendIP = Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'frontendIPConfiguration'
      FrontendPort = Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'frontendPort'
      ListenerWafPolicy = Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'firewallPolicy'
      EffectiveWafPolicy = if (Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'firewallPolicy') { Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'firewallPolicy' } else { $gatewayWafPolicyName }
    }
  })

Write-Section 'Routing Rules'
Write-TableOrNone -Rows @($routingRules | ForEach-Object {
    $ruleProperties = Get-ResourceProperties $_
    [pscustomobject]@{
      Name = $_.name
      Priority = $ruleProperties.priority
      RuleType = $ruleProperties.ruleType
      Listener = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'httpListener'
      BackendPool = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'backendAddressPool'
      BackendConfig = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'backendHttpSettings'
      UrlPathMap = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'urlPathMap'
      Redirect = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'redirectConfiguration'
    }
  })

Write-Section 'Redirect Configurations'
Write-TableOrNone -Rows @($redirectConfigurations | ForEach-Object {
    $redirectProperties = Get-ResourceProperties $_
    [pscustomobject]@{
      Name = $_.name
      Type = $redirectProperties.redirectType
      TargetListener = Get-ResourceReferenceName -Object $redirectProperties -PropertyName 'targetListener'
      TargetUrl = Get-ObjectPropertyValue -Object $redirectProperties -Name 'targetUrl'
      IncludePath = $redirectProperties.includePath
      IncludeQueryString = $redirectProperties.includeQueryString
    }
  })

Write-Section 'Backend Pools'
$nicCache = @{}
Write-TableOrNone -Rows @(
  foreach ($pool in $backendPools) {
    $poolProperties = Get-ResourceProperties $pool
    $targets = @(
      foreach ($address in @($poolProperties.backendAddresses)) {
        if ($address.fqdn) {
          [pscustomobject]@{
            TargetType = if ($address.fqdn -match '\.azurewebsites\.net$') { 'App Services' } else { 'FQDN' }
            Target = $address.fqdn
            Address = $address.fqdn
            NetworkInterface = $null
          }
        } elseif ($address.ipAddress) {
          [pscustomobject]@{
            TargetType = 'IP address'
            Target = $address.ipAddress
            Address = $address.ipAddress
            NetworkInterface = $null
          }
        }
      }

      foreach ($ipConfiguration in @($poolProperties.backendIPConfigurations)) {
        $ipConfigurationId = Get-ObjectPropertyValue -Object $ipConfiguration -Name 'id'
        if (-not $ipConfigurationId) { continue }

        $networkInterfaceId = ($ipConfigurationId -split '/ipConfigurations/')[0]
        try {
          if (-not $nicCache.ContainsKey($networkInterfaceId)) {
            $nicCache[$networkInterfaceId] = Invoke-AzJson -Arguments @('network', 'nic', 'show', '--ids', $networkInterfaceId) -Description 'backend network interface'
          }
          $networkInterface = $nicCache[$networkInterfaceId]
          $networkInterfaceProperties = Get-ResourceProperties $networkInterface
          $virtualMachineReference = Get-ObjectPropertyValue -Object $networkInterfaceProperties -Name 'virtualMachine'
          $virtualMachineId = Get-ObjectPropertyValue -Object $virtualMachineReference -Name 'id'
          $virtualMachineName = Get-ResourceNameFromId $virtualMachineId
          $virtualMachineScaleSetName = Get-ResourceIdSegmentValue -ResourceId $virtualMachineId -Segment 'virtualMachineScaleSets'
          $ipConfigurationName = Get-ResourceNameFromId $ipConfigurationId
          $privateIp = $null
          foreach ($nicIpConfiguration in @($networkInterfaceProperties.ipConfigurations)) {
            if ($nicIpConfiguration.name -eq $ipConfigurationName) {
              $privateIp = Get-ObjectPropertyValue -Object (Get-ResourceProperties $nicIpConfiguration) -Name 'privateIPAddress'
              break
            }
          }

          [pscustomobject]@{
            TargetType = if ($virtualMachineScaleSetName) { 'VMSS' } elseif ($virtualMachineName) { 'Virtual machine' } else { 'Network interface' }
            Target = if ($virtualMachineScaleSetName) { $virtualMachineScaleSetName } elseif ($virtualMachineName) { $virtualMachineName } else { $networkInterface.name }
            Address = if ($privateIp) { $privateIp } else { $ipConfigurationName }
            NetworkInterface = $networkInterface.name
          }
        } catch {
          [pscustomobject]@{
            TargetType = 'Backend IP configuration'
            Target = $ipConfigurationId
            Address = $null
            NetworkInterface = $null
          }
        }
      }
    )

    if ($targets.Count -eq 0) {
      [pscustomobject]@{
        Name = $pool.name
        TargetType = $null
        Target = '<empty>'
        Address = $null
        NetworkInterface = $null
      }
    } else {
      foreach ($target in $targets) {
        [pscustomobject]@{
          Name = $pool.name
          TargetType = $target.TargetType
          Target = $target.Target
          Address = $target.Address
          NetworkInterface = $target.NetworkInterface
        }
      }
    }
  }
)

Write-Section 'Backend Settings'
Write-TableOrNone -Rows @($backendSettings | ForEach-Object {
    $settingsProperties = Get-ResourceProperties $_
    [pscustomobject]@{
      Name = $_.name
      Protocol = $settingsProperties.protocol
      Port = $settingsProperties.port
      HostName = Get-ObjectPropertyValue -Object $settingsProperties -Name 'hostName'
      Probe = Get-ResourceReferenceName -Object $settingsProperties -PropertyName 'probe'
      Affinity = Get-ObjectPropertyValue -Object $settingsProperties -Name 'cookieBasedAffinity'
    }
  })

Write-Section 'Health Probes'
Write-TableOrNone -Rows @($probes | ForEach-Object {
    $probeProperties = Get-ResourceProperties $_
    [pscustomobject]@{
      Name = $_.name
      Protocol = $probeProperties.protocol
      Host = Get-ObjectPropertyValue -Object $probeProperties -Name 'host'
      Path = $probeProperties.path
      IntervalSeconds = $probeProperties.interval
      TimeoutSeconds = $probeProperties.timeout
      UnhealthyThreshold = $probeProperties.unhealthyThreshold
    }
  })

$backendHealth = $null
try {
  $backendHealth = Invoke-AzJson -Arguments (@('network', 'application-gateway', 'show-backend-health') + $commonArguments) -Description 'Application Gateway backend health'

  Write-Section 'Backend Health'
  $healthRows = @(
    foreach ($pool in @($backendHealth.backendAddressPools)) {
      foreach ($httpSettings in @($pool.backendHttpSettingsCollection)) {
        foreach ($server in @($httpSettings.servers)) {
          [pscustomobject]@{
            BackendPool = Get-ResourceNameFromId $pool.backendAddressPool.id
            BackendConfig = Get-ResourceNameFromId $httpSettings.backendHttpSettings.id
            Address = $server.address
            Health = $server.health
            Details = $server.healthProbeLog
          }
        }
      }
    }
  )
  Write-TableOrNone -Rows $healthRows
} catch {
  Write-Warning "Backend health could not be retrieved: $($_.Exception.Message)"
}

$subnet = $null
$subnetProperties = $null
$nsg = $null
$gatewayIpConfiguration = Get-ResourceProperties @($properties.gatewayIPConfigurations)[0]
$subnetId = Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $gatewayIpConfiguration -Name 'subnet') -Name 'id'
if ($subnetId) {
  try {
    $subnet = Invoke-AzJson -Arguments @('network', 'vnet', 'subnet', 'show', '--ids', $subnetId) -Description 'Application Gateway subnet'
    $subnetProperties = Get-ResourceProperties $subnet
    $networkSecurityGroupId = Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $subnetProperties -Name 'networkSecurityGroup') -Name 'id'
    if ($networkSecurityGroupId) {
      $nsg = Invoke-AzJson -Arguments @('network', 'nsg', 'show', '--ids', $networkSecurityGroupId) -Description 'Application Gateway subnet NSG'

      Write-Section 'Gateway Subnet NSG Rules'
      Write-TableOrNone -Rows @($nsg.securityRules | ForEach-Object {
          $ruleProperties = Get-ResourceProperties $_
          [pscustomobject]@{
            Name = $_.name
            Priority = $ruleProperties.priority
            Direction = $ruleProperties.direction
            Access = $ruleProperties.access
            Protocol = $ruleProperties.protocol
            Source = $ruleProperties.sourceAddressPrefix
            Ports = $ruleProperties.destinationPortRange
          }
        })
    }
  } catch {
    Write-Warning "Gateway subnet or NSG could not be retrieved: $($_.Exception.Message)"
  }
}

$report = [ordered]@{
  collectedAt = (Get-Date).ToUniversalTime().ToString('o')
  subscriptionId = $SubscriptionId
  resourceGroupName = $ResourceGroupName
  applicationGatewayName = $ApplicationGatewayName
  applicationGateway = [ordered]@{
    name = $gateway.name
    location = $gateway.location
    sku = $properties.sku
    autoscaleConfiguration = $properties.autoscaleConfiguration
    operationalState = $properties.operationalState
    provisioningState = $properties.provisioningState
    firewallPolicyResourceId = $properties.firewallPolicy.id
    frontendPorts = $frontendPorts
    frontendIPConfigurations = $frontendConfigurations | ForEach-Object {
      $frontendIpProperties = Get-ResourceProperties $_
      [ordered]@{
        name = $_.name
        publicIPAddressResourceId = Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $frontendIpProperties -Name 'publicIPAddress') -Name 'id'
      }
    }
    gatewayIPConfigurations = $properties.gatewayIPConfigurations
    httpListeners = $listeners
    requestRoutingRules = $routingRules
    redirectConfigurations = $redirectConfigurations
    backendAddressPools = $backendPools
    backendHttpSettingsCollection = $backendSettings
    probes = $probes
  }
  backendHealth = $backendHealth
  subnet = if ($subnet) { [ordered]@{
    id = $subnet.id
    name = $subnet.name
    addressPrefix = Get-ObjectPropertyValue -Object $subnetProperties -Name 'addressPrefix'
    networkSecurityGroupResourceId = Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $subnetProperties -Name 'networkSecurityGroup') -Name 'id'
  } } else { $null }
  networkSecurityGroup = if ($nsg) { [ordered]@{
    id = $nsg.id
    name = $nsg.name
    securityRules = $nsg.securityRules
  } } else { $null }
}

$parent = Split-Path -Path $OutputPath -Parent
if ($parent -and -not (Test-Path -Path $parent)) {
  New-Item -Path $parent -ItemType Directory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 50 | Set-Content -Path $OutputPath -Encoding utf8

Write-Host ""
Write-Host "Diagnostic report written to: $OutputPath" -ForegroundColor Green
Write-Host "No Azure resources were modified." -ForegroundColor Green
