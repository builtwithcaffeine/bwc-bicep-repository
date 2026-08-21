<#
.SYNOPSIS
Configure Azure Application Gateway custom status/error pages on a selected HTTP listener.

.DESCRIPTION
Uses Azure CLI from PowerShell to retrieve an Application Gateway via ARM, display an interactive
listener selection menu, and assign customErrorConfigurations for the 8 Application Gateway custom
status codes on the selected listener.

The status pages must be hosted at a publicly reachable HTTP/HTTPS base URL before Application
Gateway can use them. You can pass either the hosted base URL or a local status-code folder path.
When a local folder path is provided, the script validates the expected files and prompts for the
public base URL where that folder is hosted.

.EXAMPLE
.\Set-AppGatewayListenerCustomStatusCodes.ps1 `
  -SubscriptionId '00000000-0000-0000-0000-000000000000' `
  -ResourceGroupName 'rg-x-bwc-agw-dev-weu' `
  -ApplicationGatewayName 'agw-bwc-dev-weu' `
  -StatusCodePath 'https://storageaccount.z6.web.core.windows.net/generic'

.EXAMPLE
.\Set-AppGatewayListenerCustomStatusCodes.ps1 `
  -SubscriptionId '00000000-0000-0000-0000-000000000000' `
  -ResourceGroupName 'rg-x-bwc-agw-dev-weu' `
  -ApplicationGatewayName 'agw-bwc-dev-weu' `
  -StatusCodePath 'https://cdn.example.com/status-pages/star-wars' `
  -DryRun
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $SubscriptionId,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $ApplicationGatewayName,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [Alias('StatusCodeBaseUrl', 'BaseUrl')]
  [string] $StatusCodePath,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [string] $PublicBaseUrl,

  [Parameter()]
  [switch] $DryRun,

  [Parameter()]
  [string] $ApiVersion = '2024-05-01'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statusCodeFiles = [ordered]@{
  HttpStatus400 = '400-bad-request.html'
  HttpStatus403 = '403-forbidden.html'
  HttpStatus405 = '405-method-not-allowed.html'
  HttpStatus408 = '408-request-timeout.html'
  HttpStatus500 = '500-internal-server-error.html'
  HttpStatus502 = '502-bad-gateway.html'
  HttpStatus503 = '503-service-unavailable.html'
  HttpStatus504 = '504-gateway-timeout.html'
}

function Assert-AzureCliAvailable {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI 'az' was not found on PATH. Install Azure CLI and sign in before running this script."
  }
}

function ConvertTo-StatusPageUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string] $BaseUrl,

    [Parameter(Mandatory = $true)]
    [string] $FileName
  )

  $trimmedBaseUrl = $BaseUrl.Trim().TrimEnd('/')

  if ($trimmedBaseUrl -notmatch '^https?://') {
    throw "Status page base URL must be a public HTTP/HTTPS URL. Example: https://storage.z6.web.core.windows.net/generic"
  }

  if ($FileName -notmatch '\.html?$') {
    throw "Custom status page file '$FileName' must end with .htm or .html."
  }

  return "${trimmedBaseUrl}/${FileName}"
}

function Resolve-StatusCodeBaseUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string] $PathOrUrl,

    [Parameter()]
    [string] $HostedBaseUrl
  )

  $trimmedPathOrUrl = $PathOrUrl.Trim().TrimEnd('/', '\')

  if ($trimmedPathOrUrl -match '^https?://') {
    return $trimmedPathOrUrl
  }

  if (-not (Test-Path -Path $PathOrUrl -PathType Container)) {
    throw "StatusCodePath must be either a public HTTP/HTTPS base URL or an existing local folder. Could not find local folder '$PathOrUrl'."
  }

  foreach ($fileName in $statusCodeFiles.Values) {
    $filePath = Join-Path -Path $PathOrUrl -ChildPath $fileName
    if (-not (Test-Path -Path $filePath -PathType Leaf)) {
      throw "Local status-code folder '$PathOrUrl' is missing expected file '$fileName'."
    }
  }

  Write-Host "Validated local status-code folder: $PathOrUrl" -ForegroundColor Green
  Write-Host 'Application Gateway requires public HTTP/HTTPS URLs, not local file paths.' -ForegroundColor Yellow

  $baseUrl = $HostedBaseUrl
  if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    $baseUrl = Read-Host 'Enter the public base URL where this folder is hosted'
  }

  $baseUrl = $baseUrl.Trim().TrimEnd('/')
  if ($baseUrl -notmatch '^https?://') {
    throw "Public base URL must start with http:// or https://. Example: https://storage.z6.web.core.windows.net/star-wars"
  }

  return $baseUrl
}

function Invoke-AzCliJson {
  param(
    [Parameter(Mandatory = $true)]
    [string[]] $Arguments
  )

  $output = & az @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI command failed: az $($Arguments -join ' ')`n$output"
  }

  if ([string]::IsNullOrWhiteSpace($output)) {
    return $null
  }

  return $output | ConvertFrom-Json -Depth 100
}

function Get-ObjectPropertyValue {
  param(
    [Parameter(Mandatory = $true)]
    [object] $InputObject,

    [Parameter(Mandatory = $true)]
    [string] $PropertyName,

    [Parameter()]
    [object] $DefaultValue = $null
  )

  $property = $InputObject.PSObject.Properties[$PropertyName]
  if ($null -eq $property) {
    return $DefaultValue
  }

  return $property.Value
}

function Select-ApplicationGatewayListener {
  param(
    [Parameter(Mandatory = $true)]
    [object[]] $Listeners
  )

  if ($Listeners.Count -eq 0) {
    throw 'No HTTP listeners were found on the Application Gateway.'
  }

  Write-Host ''
  Write-Host 'Application Gateway listeners' -ForegroundColor Cyan
  Write-Host '-----------------------------' -ForegroundColor Cyan

  for ($i = 0; $i -lt $Listeners.Count; $i++) {
    $listener = $Listeners[$i]
    $properties = $listener.properties
    $protocol = Get-ObjectPropertyValue -InputObject $properties -PropertyName 'protocol' -DefaultValue 'Unknown'
    $listenerHostName = Get-ObjectPropertyValue -InputObject $properties -PropertyName 'hostName'
    $listenerHostNames = @(Get-ObjectPropertyValue -InputObject $properties -PropertyName 'hostNames' -DefaultValue @())
    $listenerCustomErrors = @(Get-ObjectPropertyValue -InputObject $properties -PropertyName 'customErrorConfigurations' -DefaultValue @())

    $hostName = if (-not [string]::IsNullOrWhiteSpace($listenerHostName)) { $listenerHostName } elseif ($listenerHostNames.Count -gt 0) { ($listenerHostNames -join ', ') } else { '<catch-all>' }
    $currentCustomErrors = $listenerCustomErrors.Count

    Write-Host ("[{0}] {1} | Protocol: {2} | Host: {3} | Custom errors: {4}" -f ($i + 1), $listener.name, $protocol, $hostName, $currentCustomErrors)
  }

  Write-Host '[Q] Quit'
  Write-Host ''

  while ($true) {
    $selection = Read-Host 'Select listener number to configure'

    if ($selection -match '^(q|quit|exit)$') {
      return $null
    }

    $selectionNumber = 0
    if ([int]::TryParse($selection, [ref] $selectionNumber) -and $selectionNumber -ge 1 -and $selectionNumber -le $Listeners.Count) {
      return @{
        Index = $selectionNumber - 1
        Listener = $Listeners[$selectionNumber - 1]
      }
    }

    Write-Warning "Invalid selection '$selection'. Choose a number between 1 and $($Listeners.Count), or Q to quit."
  }
}

function New-CustomErrorConfigurations {
  param(
    [Parameter(Mandatory = $true)]
    [string] $BaseUrl
  )

  $configs = @()

  foreach ($statusCode in $statusCodeFiles.Keys) {
    $configs += [ordered]@{
      statusCode = $statusCode
      customErrorPageUrl = ConvertTo-StatusPageUrl -BaseUrl $BaseUrl -FileName $statusCodeFiles[$statusCode]
    }
  }

  return $configs
}

function Test-CustomErrorConfigurationUrls {
  param(
    [Parameter(Mandatory = $true)]
    [object[]] $Configurations
  )

  Write-Host ''
  Write-Host 'Validating custom status page URLs...' -ForegroundColor Cyan

  foreach ($config in $Configurations) {
    try {
      $response = Invoke-WebRequest -Uri $config.customErrorPageUrl -Method Head -MaximumRedirection 0 -ErrorAction Stop
      if ([int]$response.StatusCode -ne 200) {
        throw "Expected HTTP 200, received HTTP $([int]$response.StatusCode)."
      }

      Write-Host ("- {0}: HTTP {1}" -f $config.statusCode, [int]$response.StatusCode) -ForegroundColor Green
    }
    catch {
      throw "Custom page URL validation failed for $($config.statusCode): $($config.customErrorPageUrl)`n$($_.Exception.Message)"
    }
  }
}

Assert-AzureCliAvailable

$resolvedStatusCodeBaseUrl = Resolve-StatusCodeBaseUrl -PathOrUrl $StatusCodePath -HostedBaseUrl $PublicBaseUrl

Write-Host "Setting Azure CLI subscription context to $SubscriptionId" -ForegroundColor Cyan
& az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
  throw "Failed to set Azure CLI subscription context to '$SubscriptionId'. Run 'az login' and verify subscription access."
}

$applicationGatewayResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/applicationGateways/$ApplicationGatewayName"
$applicationGatewayUrl = "https://management.azure.com${applicationGatewayResourceId}?api-version=$ApiVersion"

Write-Host "Loading Application Gateway '$ApplicationGatewayName' from resource group '$ResourceGroupName'..." -ForegroundColor Cyan
$applicationGateway = Invoke-AzCliJson -Arguments @('rest', '--method', 'get', '--url', $applicationGatewayUrl, '--output', 'json')

if (-not $applicationGateway.properties.httpListeners) {
  throw "Application Gateway '$ApplicationGatewayName' does not contain any HTTP listeners."
}

$listeners = @($applicationGateway.properties.httpListeners)
$selected = Select-ApplicationGatewayListener -Listeners $listeners

if ($null -eq $selected) {
  Write-Host 'No listener selected. No changes made.' -ForegroundColor Yellow
  return
}

$selectedIndex = [int] $selected.Index
$selectedListener = $selected.Listener
$customErrorConfigurations = New-CustomErrorConfigurations -BaseUrl $resolvedStatusCodeBaseUrl

Test-CustomErrorConfigurationUrls -Configurations $customErrorConfigurations

Write-Host ''
Write-Host "Selected listener: $($selectedListener.name)" -ForegroundColor Green
Write-Host "Status page base URL: $resolvedStatusCodeBaseUrl" -ForegroundColor Green
Write-Host ''
Write-Host 'Custom status code mappings to apply:' -ForegroundColor Cyan
foreach ($config in $customErrorConfigurations) {
  Write-Host ("- {0} => {1}" -f $config.statusCode, $config.customErrorPageUrl)
}
Write-Host ''

$confirmation = Read-Host "Apply these custom status pages to listener '$($selectedListener.name)'? [y/N]"
if ($confirmation -notmatch '^(y|yes)$') {
  Write-Host 'Cancelled. No changes made.' -ForegroundColor Yellow
  return
}

$selectedListenerProperties = $applicationGateway.properties.httpListeners[$selectedIndex].properties
$selectedListenerProperties | Add-Member -NotePropertyName customErrorConfigurations -NotePropertyValue $customErrorConfigurations -Force

$tempFile = Join-Path $env:TEMP ("appgw-custom-errors-{0}.json" -f ([guid]::NewGuid().ToString('N')))
try {
  $applicationGateway | ConvertTo-Json -Depth 100 | Set-Content -Path $tempFile -Encoding utf8

  if ($DryRun) {
    Write-Host "Dry run enabled. Updated Application Gateway payload written to: $tempFile" -ForegroundColor Yellow
    Write-Host 'No Azure changes were submitted.' -ForegroundColor Yellow
    return
  }

  if ($PSCmdlet.ShouldProcess($selectedListener.name, 'Set listener customErrorConfigurations and update Application Gateway')) {
    Write-Host 'Submitting Application Gateway update. This can take several minutes...' -ForegroundColor Cyan
    & az rest --method put --url $applicationGatewayUrl --body "@$tempFile" --headers 'Content-Type=application/json' --output none

    if ($LASTEXITCODE -ne 0) {
      throw "Failed to update Application Gateway '$ApplicationGatewayName'."
    }

    Write-Host "Custom status pages configured successfully for listener '$($selectedListener.name)'." -ForegroundColor Green
    Write-Host 'Note: Application Gateway displays these pages only for errors generated by Application Gateway itself. Backend-generated error bodies are passed through unchanged.' -ForegroundColor Yellow
  }
}
finally {
  if (-not $DryRun -and (Test-Path $tempFile)) {
    Remove-Item -Path $tempFile -Force
  }
}
