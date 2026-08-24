# Requires -Version 7.0

<##
.SYNOPSIS
    Audits Application Gateway resource usage against documented limits.

.DESCRIPTION
    Collects read-only Application Gateway configuration and reports resource
    usage, utilization percentage, and status. Backend targets include literal
    IP/FQDN addresses and NIC-backed VM or VMSS targets.

    The script does not modify Azure resources. Use -OutputPath to save a JSON
    report suitable for further analysis or support cases.

.PARAMETER SubscriptionId
    Azure subscription containing the Application Gateway resources.

.PARAMETER ResourceGroupName
    Optional resource group filter.

.PARAMETER ApplicationGatewayName
    Optional Application Gateway name filter.

.PARAMETER WarningThreshold
    Utilization ratio at which a metric becomes WARNING. Defaults to 0.75.

.PARAMETER OutputPath
  Optional path for the JSON or HTML audit report.

.PARAMETER Report
  Writes a self-contained HTML report instead of JSON output.

.EXAMPLE
    .\Invoke-AppGwAudit.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000'

.EXAMPLE
    .\Invoke-AppGwAudit.ps1 `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ResourceGroupName 'rg-example-agw-shared-dev-weu' `
        -ApplicationGatewayName 'agw-example-shared-dev-weu-01' `
        -OutputPath '.\appgw-audit.json'

.NOTES
    Requires Azure CLI and read access to the selected resources.
#>

[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
  [string] $SubscriptionId,

  [Parameter(Mandatory = $false)]
  [string] $ResourceGroupName,

  [Parameter(Mandatory = $false)]
  [string] $ApplicationGatewayName,

  [Parameter(Mandatory = $false)]
  [ValidateRange(0, 1)]
  [decimal] $WarningThreshold = 0.75,

  [Parameter(Mandatory = $false)]
  [string] $OutputPath,

  [Parameter(Mandatory = $false)]
  [switch] $Report
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command -Name 'az' -ErrorAction SilentlyContinue)) {
  throw 'Azure CLI (az) is not installed or is not available on PATH.'
}

$null = az account show --only-show-errors --output none 2>&1
if ($LASTEXITCODE -ne 0) {
  throw "Not signed in to Azure CLI. Run 'az login' and try again."
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

function Get-ResourceProperties {
  param (
    [Parameter(Mandatory = $true)]
    [object] $Resource
  )

  $properties = Get-ObjectPropertyValue -Object $Resource -Name 'properties'
  if ($null -ne $properties) {
    return $properties
  }

  # Azure CLI commonly flattens child-resource properties in its output.
  return $Resource
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

function Get-PublicIpAddressValue {
  param (
    [AllowNull()]
    [string] $PublicIpResourceId
  )

  if (-not $PublicIpResourceId) {
    return $null
  }

  try {
    $publicIp = Invoke-AzJson -Arguments @('network', 'public-ip', 'show', '--ids', $PublicIpResourceId) -Description 'public IP address'
    $publicIpProperties = Get-ResourceProperties $publicIp
    return Get-ObjectPropertyValue -Object $publicIpProperties -Name 'ipAddress'
  } catch {
    return $null
  }
}

function Format-AsPercentage {
  param (
    [int] $Current,
    [int] $Maximum
  )

  if ($Maximum -eq 0) {
    return 'N/A'
  }

  return '{0:P0}' -f ([decimal]$Current / $Maximum)
}

function Get-UsageReport {
  param (
    [int] $Current,
    [int] $Maximum,
    [decimal] $WarningThreshold
  )

  $ratio = if ($Maximum -eq 0) { 0 } else { [decimal]$Current / $Maximum }
  $status = if ($Current -gt $Maximum) {
    'CRITICAL'
  } elseif ($ratio -ge $WarningThreshold) {
    'WARNING'
  } else {
    'OK'
  }

  return [pscustomobject]@{
    Current = $Current
    Maximum = $Maximum
    Usage = Format-AsPercentage -Current $Current -Maximum $Maximum
    Status = $status
  }
}

function Write-UsageReport {
  param (
    [Parameter(Mandatory = $true)]
    [string] $GatewayName,

    [Parameter(Mandatory = $true)]
    [hashtable] $Usage,

    [Parameter(Mandatory = $true)]
    [hashtable] $Limits,

    [Parameter(Mandatory = $true)]
    [decimal] $WarningThreshold
  )

  $rows = @(
    foreach ($metric in $Limits.Keys) {
      $report = Get-UsageReport -Current $Usage[$metric] -Maximum $Limits[$metric] -WarningThreshold $WarningThreshold
      [pscustomobject]@{
        Resource = $metric
        Current = $report.Current
        Maximum = $report.Maximum
        Usage = $report.Usage
        Status = $report.Status
      }
    }
  )

  Write-Host ""
  Write-Host "Resource Usage Report: $GatewayName" -ForegroundColor Yellow
  $rows | Sort-Object @{ Expression = { switch ($_.Status) { 'CRITICAL' { 1 } 'WARNING' { 2 } default { 3 } } } }, Resource |
    Format-Table -AutoSize | Out-Host

  foreach ($row in $rows) {
    if ($row.Status -eq 'CRITICAL') {
      Write-Host "CRITICAL: $($row.Resource) is above its limit." -ForegroundColor Red
    } elseif ($row.Status -eq 'WARNING') {
      Write-Host "WARNING: $($row.Resource) is at $($row.Usage) of its limit." -ForegroundColor Yellow
    }
  }

  return $rows
}

function ConvertTo-HtmlSafe {
  param (
    [AllowNull()]
    [object] $Value
  )

  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Write-HtmlReport {
  param (
    [Parameter(Mandatory = $true)]
    [object[]] $Reports,

    [Parameter(Mandatory = $true)]
    [string] $Path,

    [Parameter(Mandatory = $false)]
    [string] $SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string] $ApplicationGatewayName
  )

  $resourceOrder = @(
    'FrontendIPConfigurations', 'FrontendPorts', 'Listeners', 'ActiveListeners',
    'BackendPools', 'BackendInstancesPerPool', 'RequestRoutingRules',
    'BackendHTTPSettings', 'URLPathMaps', 'URLPathRules', 'HealthProbes'
  )
  $resourceLabels = @{
    FrontendIPConfigurations = 'Frontend IP configurations'
    FrontendPorts = 'Frontend ports'
    Listeners = 'Listeners'
    ActiveListeners = 'Active listeners'
    BackendPools = 'Backend pools'
    BackendInstancesPerPool = 'Backend instances per pool'
    RequestRoutingRules = 'Request routing rules'
    BackendHTTPSettings = 'Backend HTTP settings'
    URLPathMaps = 'URL path maps'
    URLPathRules = 'URL path rules'
    HealthProbes = 'Health probes'
  }

  # Reports use OrderedDictionary, and only failed gateways carry an 'error' key - use
  # .Contains() (a method call) rather than dot-access, which throws under strict mode
  # when the key is absent.
  $erroredReports = @($Reports | Where-Object { $_.Contains('error') })
  $allUsageRows = @($Reports | Where-Object { -not $_.Contains('error') } | ForEach-Object { $_.usage })
  $criticalCount = @($allUsageRows | Where-Object { $_.Status -eq 'CRITICAL' }).Count
  $warningCount = @($allUsageRows | Where-Object { $_.Status -eq 'WARNING' }).Count

  # Surface the gateways that need attention first: errors, then critical, then warning, then healthy.
  $sortedReports = $Reports | Sort-Object -Property @(
    @{ Expression = {
      if ($_.Contains('error')) { return 0 }
      $statuses = @($_.usage.Status)
      if ($statuses -contains 'CRITICAL') { return 1 }
      if ($statuses -contains 'WARNING') { return 2 }
      return 3
    }
  },
  'name'
)

$gatewaySections = @(
  foreach ($report in $sortedReports) {
    $gatewayName = ConvertTo-HtmlSafe $report.name
    $resourceGroupLabel = ConvertTo-HtmlSafe $report.resourceGroup
    $searchKey = ConvertTo-HtmlSafe ("$($report.name) $($report.resourceGroup)".ToLowerInvariant())

    if ($report.Contains('error')) {
      "<section class=`"gateway-card`" data-search=`"$searchKey`" data-status=`"critical`"><div class=`"gateway-heading`"><div><p class=`"eyebrow`">APPLICATION GATEWAY</p><h2>$gatewayName</h2><p class=`"gateway-meta`"><span>Resource Group</span> $resourceGroupLabel</p></div><span class=`"status critical`">Audit failed</span></div><div class=`"error-banner`">$(ConvertTo-HtmlSafe $report.error)</div></section>"
      continue
    }

    $gatewayStatuses = @($report.usage.Status)
    $gatewayStatus = if ($gatewayStatuses -contains 'CRITICAL') { 'critical' } elseif ($gatewayStatuses -contains 'WARNING') { 'warning' } else { 'ok' }
    $gatewayLabel = switch ($gatewayStatus) { 'critical' { 'Action required' } 'warning' { 'Review recommended' } default { 'Healthy' } }

    $sectionMarkup = @()
    foreach ($resourceName in $resourceOrder) {
      $usage = @($report.usage | Where-Object { $_.Resource -eq $resourceName })[0]
      $items = @($report.details.$resourceName)
      $statusClass = if ($usage) { ([string]$usage.Status).ToLowerInvariant() } else { 'ok' }
      $displayName = $resourceLabels[$resourceName]
      $summary = if ($usage) { "$displayName ($($usage.Current)/$($usage.Maximum), $($usage.Usage))" } else { $displayName }
      # Auto-expand sections that need attention; keep healthy sections collapsed to reduce noise.
      $open = if ($statusClass -ne 'ok') { ' open' } else { '' }
      $detailRows = @()
      foreach ($item in $items) {
        $cells = @($item.PSObject.Properties | ForEach-Object { "<td>$(ConvertTo-HtmlSafe $_.Value)</td>" })
        $detailRows += "<tr>$($cells -join '')</tr>"
      }
      $headers = if ($items.Count -gt 0) { @($items[0].PSObject.Properties | ForEach-Object { "<th>$(ConvertTo-HtmlSafe $_.Name)</th>" }) -join '' } else { '<th>Details</th>' }
      $body = if ($detailRows.Count -gt 0) { $detailRows -join '' } else { '<tr><td class="empty" colspan="99">No configuration entries found.</td></tr>' }
      $sectionMarkup += "<details class=`"resource-section`" data-status=`"$statusClass`"$open><summary><span class=`"summary-title`"><span class=`"chevron`">›</span>$summary</span><span class=`"status $statusClass`">$($usage.Status)</span></summary><div class=`"table-wrap`"><table><thead><tr>$headers</tr></thead><tbody>$body</tbody></table></div></details>"
    }
    "<section class=`"gateway-card`" data-search=`"$searchKey`" data-status=`"$gatewayStatus`"><div class=`"gateway-heading`"><div><p class=`"eyebrow`">APPLICATION GATEWAY</p><h2>$gatewayName</h2><p class=`"gateway-meta`"><span>Resource Group</span> $resourceGroupLabel <span class=`"separator`">•</span> <span>Location</span> $(ConvertTo-HtmlSafe $report.location) <span class=`"separator`">•</span> <span>WAF</span> $(if ($report.wafPolicyConfigured) { 'Configured' } else { 'Not configured' })</p></div><span class=`"status $gatewayStatus`">$gatewayLabel</span></div>$($sectionMarkup -join '')</section>"
  }
)

$scopeParts = [System.Collections.Generic.List[string]]::new()
if ($SubscriptionId) { $scopeParts.Add("Subscription: $(ConvertTo-HtmlSafe $SubscriptionId)") }
$scopeParts.Add("Resource group: $(if ($ResourceGroupName) { ConvertTo-HtmlSafe $ResourceGroupName } else { 'All' })")
$scopeParts.Add("Gateway: $(if ($ApplicationGatewayName) { ConvertTo-HtmlSafe $ApplicationGatewayName } else { 'All' })")
$scopeLine = $scopeParts -join ' &nbsp;•&nbsp; '

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Application Gateway Resource Audit</title>
  <style>
    :root { color-scheme: dark; font-family: Segoe UI, Inter, Arial, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; min-width: 320px; padding: clamp(1rem, 4vw, 3.5rem); background: radial-gradient(circle at 10% 0%, #173044 0, #0b1220 38rem, #070b14 100%); color: #e2e8f0; }
    main { max-width: 1600px; margin: auto; }
    h1 { margin: 0; color: #f8fafc; font-size: clamp(1.7rem, 3vw, 2.5rem); letter-spacing: -.03em; }
    h2 { margin: .2rem 0; color: #f8fafc; font-size: clamp(1.1rem, 2vw, 1.4rem); letter-spacing: -.02em; }
    .subtitle { color: #94a3b8; margin: .5rem 0 .25rem; }
    .scope { color: #64748b; font-size: .85rem; margin: 0 0 1.5rem; }
    .toolbar { display: flex; flex-wrap: wrap; gap: .75rem; align-items: center; margin: 1rem 0; }
    .toolbar input { flex: 1; min-width: 220px; padding: .6rem .85rem; border: 1px solid #334155; border-radius: .5rem; background: #0f172a; color: #f8fafc; font-size: .9rem; }
    .toolbar input::placeholder { color: #64748b; }
    .overview { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .8rem; margin: 1.5rem 0; }
    .overview-card { padding: 1rem 1.15rem; background: rgba(15, 23, 42, .8); border: 1px solid #26364c; border-radius: .7rem; box-shadow: 0 12px 30px rgba(0, 0, 0, .18); }
    .overview-card.alert { border-color: #7f1d1d; background: rgba(69, 10, 10, .35); }
    .overview-label { display: block; color: #94a3b8; font-size: .78rem; text-transform: uppercase; letter-spacing: .08em; }
    .overview-value { display: block; margin-top: .35rem; color: #f8fafc; font-size: 1.5rem; font-weight: 700; }
    .gateway-card { margin: 1.5rem 0; padding: clamp(1rem, 2vw, 1.5rem); background: rgba(15, 23, 42, .82); border: 1px solid #2c4058; border-radius: .9rem; box-shadow: 0 18px 45px rgba(0, 0, 0, .22); }
    .gateway-card[data-status="critical"] { border-color: #7f1d1d; }
    .gateway-card[data-status="warning"] { border-color: #713f12; }
    .gateway-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; padding-bottom: .9rem; border-bottom: 1px solid #26364c; }
    .eyebrow { margin: 0 0 .35rem; color: #22d3ee; font-size: .72rem; font-weight: 700; letter-spacing: .14em; }
    .gateway-meta { display: flex; flex-wrap: wrap; gap: .35rem; color: #cbd5e1; margin: .55rem 0 0; font-size: .86rem; }
    .gateway-meta span { color: #64748b; font-weight: 600; }
    .gateway-meta .separator { color: #475569; }
    .error-banner { margin-top: 1rem; padding: .9rem 1rem; background: rgba(127, 29, 29, .25); border: 1px solid #7f1d1d; border-radius: .5rem; color: #fecaca; font-size: .9rem; }
    .resource-section { margin: .75rem 0; border: 1px solid #26364c; border-radius: .55rem; background: rgba(8, 15, 28, .72); overflow: hidden; transition: border-color .2s ease, box-shadow .2s ease; }
    .resource-section[open] { border-color: #3b6b89; box-shadow: 0 8px 22px rgba(0, 0, 0, .16); }
    .resource-section[data-status="critical"] { border-color: #7f1d1d; }
    .resource-section[data-status="warning"] { border-color: #713f12; }
    summary { display: flex; align-items: center; justify-content: space-between; gap: 1rem; cursor: pointer; padding: .85rem 1rem; color: #dbeafe; font-weight: 650; list-style: none; }
    summary::-webkit-details-marker { display: none; }
    summary:hover { background: rgba(30, 64, 85, .28); }
    summary:focus-visible { outline: 2px solid #22d3ee; outline-offset: -2px; }
    .summary-title { display: flex; align-items: center; gap: .55rem; }
    .chevron { display: inline-block; color: #22d3ee; font-size: 1.45rem; line-height: .7; transition: transform .2s ease; }
    details[open] .chevron { transform: rotate(90deg); }
    .table-wrap { overflow-x: auto; border-top: 1px solid #26364c; }
    table { width: 100%; border-collapse: collapse; white-space: nowrap; }
    th, td { padding: .7rem .85rem; text-align: left; border-bottom: 1px solid #1e2d40; }
    th { color: #67e8f9; background: #142235; font-size: .75rem; text-transform: uppercase; letter-spacing: .06em; }
    td { color: #cbd5e1; font-size: .88rem; }
    tr:last-child td { border-bottom: 0; }
    tr:hover td { background: rgba(34, 211, 238, .05); }
    .status { flex: 0 0 auto; padding: .25rem .6rem; border-radius: 999px; font-size: .72rem; font-weight: 800; letter-spacing: .05em; text-transform: uppercase; }
    .status.ok { color: #86efac; background: rgba(20, 83, 45, .7); }
    .status.warning { color: #fde68a; background: rgba(113, 63, 18, .75); }
    .status.critical { color: #fecaca; background: rgba(127, 29, 29, .8); }
    .empty { padding: 1rem; text-align: center; color: #94a3b8; }
    .no-results { display: none; padding: 2rem; text-align: center; color: #94a3b8; }
    @media (max-width: 900px) { .overview { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
    @media (max-width: 700px) { .overview { grid-template-columns: 1fr; } .gateway-heading { flex-direction: column; } summary { align-items: flex-start; } }
    @media print {
      body { background: #fff; color: #000; padding: 0; }
      .toolbar { display: none; }
      .gateway-card, .overview-card { box-shadow: none; background: #fff; border-color: #ccc; }
      th { background: #eee; color: #000; }
      td, .gateway-meta, .subtitle, .scope { color: #000; }
      details > *:not(summary) { display: block !important; }
      .chevron { display: none !important; }
      .resource-section { break-inside: avoid; }
    }
  </style>
</head>
<body>
<main>
  <h1>Application Gateway Resource Audit</h1>
  <p class="subtitle">Read-only report generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')</p>
  <p class="scope">$scopeLine</p>
  <section class="overview">
    <div class="overview-card"><span class="overview-label">Gateways audited</span><span class="overview-value">$($Reports.Count)</span></div>
    <div class="overview-card$(if ($erroredReports.Count -gt 0) { ' alert' })"><span class="overview-label">Gateways with errors</span><span class="overview-value">$($erroredReports.Count)</span></div>
    <div class="overview-card$(if ($criticalCount -gt 0) { ' alert' })"><span class="overview-label">Critical issues</span><span class="overview-value">$criticalCount</span></div>
    <div class="overview-card"><span class="overview-label">Warnings</span><span class="overview-value">$warningCount</span></div>
  </section>
  <div class="toolbar">
    <input type="search" id="gatewaySearch" placeholder="Filter by gateway name or resource group...">
  </div>
  $($gatewaySections -join '')
  <p class="no-results" id="noResults">No gateways match your search.</p>
</main>
<script>
  const searchInput = document.getElementById('gatewaySearch');
  const noResults = document.getElementById('noResults');
  const cards = [...document.querySelectorAll('.gateway-card')];
  searchInput.addEventListener('input', () => {
    const term = searchInput.value.trim().toLowerCase();
    let visibleCount = 0;
    cards.forEach((card) => {
      const matches = term.length === 0 || (card.dataset.search || '').includes(term);
      card.hidden = !matches;
      if (matches) { visibleCount++; }
    });
    noResults.style.display = visibleCount === 0 ? 'block' : 'none';
  });
</script>
</body>
</html>
"@

$parent = Split-Path -Path $Path -Parent
if ($parent -and -not (Test-Path -Path $parent)) {
  New-Item -Path $parent -ItemType Directory -Force | Out-Null
}
$html | Set-Content -Path $Path -Encoding utf8
}

$listArguments = @('network', 'application-gateway', 'list', '--subscription', $SubscriptionId)
if ($ResourceGroupName) {
  $listArguments += @('--resource-group', $ResourceGroupName)
}

$appGateways = @(Invoke-AzJson -Arguments $listArguments -Description 'Application Gateway list')
if ($ApplicationGatewayName) {
  $appGateways = @($appGateways | Where-Object { $_.name -eq $ApplicationGatewayName })
}

if ($appGateways.Count -eq 0) {
  throw 'No matching Application Gateways were found.'
}

$limits = @{
  FrontendIPConfigurations = 4
  FrontendPorts = 100
  Listeners = 200
  ActiveListeners = 100
  BackendPools = 100
  BackendInstancesPerPool = 1200
  RequestRoutingRules = 400
  BackendHTTPSettings = 100
  URLPathMaps = 100
  URLPathRules = 100
  HealthProbes = 100
}

$auditReports = @(
  $gatewayIndex = 0
  foreach ($gateway in $appGateways) {
    $gatewayIndex++
    Write-Progress -Activity 'Auditing Application Gateways' -Status $gateway.name -PercentComplete (($gatewayIndex / $appGateways.Count) * 100)
    $resourceGroup = if ($gateway.resourceGroup) { $gateway.resourceGroup } else { $ResourceGroupName }

    try {
      # Azure CLI's list output already contains full nested properties in practice;
      # only fall back to a per-gateway show call if that assumption doesn't hold.
      $listProperties = Get-ResourceProperties $gateway
      $config = if ($null -ne (Get-ObjectPropertyValue -Object $listProperties -Name 'requestRoutingRules')) {
        $gateway
      } else {
        $showArguments = @(
          'network', 'application-gateway', 'show',
          '--subscription', $SubscriptionId,
          '--resource-group', $resourceGroup,
          '--name', $gateway.name
        )
        Invoke-AzJson -Arguments $showArguments -Description "Application Gateway '$($gateway.name)'"
      }
      $gatewayProperties = Get-ResourceProperties $config

      $routingRules = @($gatewayProperties.requestRoutingRules)
      $backendPools = @($gatewayProperties.backendAddressPools)
      $pathMaps = @($gatewayProperties.urlPathMaps)
      $activeListenerNames = @(
        $routingRules |
          ForEach-Object { Get-ResourceProperties $_ } |
          ForEach-Object { Get-ResourceNameFromId (Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $_ -Name 'httpListener') -Name 'id') } |
          Where-Object { $_ } |
          Select-Object -Unique
      )
      $firewallPolicy = Get-ObjectPropertyValue -Object $gatewayProperties -Name 'firewallPolicy'

      # Single pass over backend pools avoids recomputing properties per collection.
      $backendTargetCounts = [System.Collections.Generic.List[int]]::new()
      $backendPoolDetails = [System.Collections.Generic.List[object]]::new()
      $backendInstanceDetails = [System.Collections.Generic.List[object]]::new()
      foreach ($pool in $backendPools) {
        $poolProperties = Get-ResourceProperties $pool
        $addresses = @($poolProperties.backendAddresses)
        $ipConfigurations = @($poolProperties.backendIPConfigurations)
        $backendTargetCounts.Add($addresses.Count + $ipConfigurations.Count)

        $backendPoolDetails.Add([pscustomobject][ordered]@{
            Name = $pool.name
            FqdnTargets = @($addresses | ForEach-Object { $_.fqdn } | Where-Object { $_ }) -join ', '
            IpTargets = @($addresses | ForEach-Object { $_.ipAddress } | Where-Object { $_ }) -join ', '
            NetworkInterfaceTargets = @($ipConfigurations | ForEach-Object { $_.id } | Where-Object { $_ }) -join ', '
          })

        foreach ($address in $addresses) {
          if ($address.fqdn) {
            $backendInstanceDetails.Add([pscustomobject][ordered]@{ Pool = $pool.name; TargetType = 'FQDN'; Target = $address.fqdn })
          } elseif ($address.ipAddress) {
            $backendInstanceDetails.Add([pscustomobject][ordered]@{ Pool = $pool.name; TargetType = 'IP address'; Target = $address.ipAddress })
          }
        }
        foreach ($ipConfiguration in $ipConfigurations) {
          $ipConfigurationId = Get-ObjectPropertyValue -Object $ipConfiguration -Name 'id'
          if (-not $ipConfigurationId) { continue }
          $networkInterfaceName = Get-ResourceIdSegmentValue -ResourceId $ipConfigurationId -Segment 'networkInterfaces'
          $backendInstanceDetails.Add([pscustomobject][ordered]@{ Pool = $pool.name; TargetType = 'Network interface'; Target = $networkInterfaceName })
        }
      }
      $maximumBackendTargets = if ($backendTargetCounts.Count -gt 0) { ($backendTargetCounts | Measure-Object -Maximum).Maximum } else { 0 }

      $listenerDetails = @(
        foreach ($listener in @($gatewayProperties.httpListeners)) {
          $listenerProperties = Get-ResourceProperties $listener
          [pscustomobject][ordered]@{
            Name = $listener.name
            Protocol = $listenerProperties.protocol
            HostName = Get-ObjectPropertyValue -Object $listenerProperties -Name 'hostName'
            FrontendPort = Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'frontendPort'
            FrontendIP = Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'frontendIPConfiguration'
            SslCertificate = Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'sslCertificate'
            WafPolicy = if (Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'firewallPolicy') { Get-ResourceReferenceName -Object $listenerProperties -PropertyName 'firewallPolicy' } else { if ((Get-ObjectPropertyValue -Object $firewallPolicy -Name 'id')) { Get-ResourceNameFromId $firewallPolicy.id } else { $null } }
          }
        }
      )
      $routingRuleDetails = @(
        foreach ($rule in $routingRules) {
          $ruleProperties = Get-ResourceProperties $rule
          [pscustomobject][ordered]@{
            Name = $rule.name
            Priority = $ruleProperties.priority
            RuleType = $ruleProperties.ruleType
            Listener = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'httpListener'
            BackendPool = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'backendAddressPool'
            BackendSettings = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'backendHttpSettings'
            Redirect = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'redirectConfiguration'
            UrlPathMap = Get-ResourceReferenceName -Object $ruleProperties -PropertyName 'urlPathMap'
          }
        }
      )
      $backendSettingsDetails = @(
        foreach ($settings in @($gatewayProperties.backendHttpSettingsCollection)) {
          $settingsProperties = Get-ResourceProperties $settings
          [pscustomobject][ordered]@{
            Name = $settings.name
            Protocol = $settingsProperties.protocol
            Port = $settingsProperties.port
            HostName = Get-ObjectPropertyValue -Object $settingsProperties -Name 'hostName'
            Probe = Get-ResourceReferenceName -Object $settingsProperties -PropertyName 'probe'
            CookieBasedAffinity = Get-ObjectPropertyValue -Object $settingsProperties -Name 'cookieBasedAffinity'
          }
        }
      )
      $frontendPortDetails = @($gatewayProperties.frontendPorts | ForEach-Object {
          $portProperties = Get-ResourceProperties $_
          [pscustomobject][ordered]@{ Name = $_.name; Port = $portProperties.port }
        })
      $frontendIpDetails = @($gatewayProperties.frontendIPConfigurations | ForEach-Object {
          $ipProperties = Get-ResourceProperties $_
          $publicIpId = Get-ObjectPropertyValue -Object (Get-ObjectPropertyValue -Object $ipProperties -Name 'publicIPAddress') -Name 'id'
          $publicIpName = Get-ResourceNameFromId $publicIpId
          $publicIpAddress = Get-PublicIpAddressValue -PublicIpResourceId $publicIpId
          [pscustomobject][ordered]@{
            Name = $_.name
            PublicIPAddress = if ($publicIpAddress) { "$publicIpName ($publicIpAddress)" } else { $publicIpName }
            PrivateIPAddress = Get-ObjectPropertyValue -Object $ipProperties -Name 'privateIPAddress'
          }
        })
      $pathMapDetails = @($pathMaps | ForEach-Object {
          $mapProperties = Get-ResourceProperties $_
          [pscustomobject][ordered]@{ Name = $_.name; DefaultBackendPool = Get-ResourceReferenceName -Object $mapProperties -PropertyName 'defaultBackendAddressPool'; DefaultBackendSettings = Get-ResourceReferenceName -Object $mapProperties -PropertyName 'defaultBackendHttpSettings'; PathRules = @((Get-ObjectPropertyValue -Object $mapProperties -Name 'pathRules')).Count }
        })
      $pathRuleCountsPerMap = [System.Collections.Generic.List[int]]::new()
      $pathRuleDetails = @(
        foreach ($map in $pathMaps) {
          $mapProperties = Get-ResourceProperties $map
          $rules = @((Get-ObjectPropertyValue -Object $mapProperties -Name 'pathRules'))
          $pathRuleCountsPerMap.Add($rules.Count)
          foreach ($pathRule in $rules) {
            [pscustomobject][ordered]@{ PathMap = $map.name; Name = $pathRule.name; Paths = @($pathRule.paths) -join ', '; BackendPool = Get-ResourceReferenceName -Object $pathRule -PropertyName 'backendAddressPool'; BackendSettings = Get-ResourceReferenceName -Object $pathRule -PropertyName 'backendHttpSettings' }
          }
        }
      )
      # Azure enforces path-based rules as a per-map limit (100), not an aggregate total.
      $maximumPathRulesPerMap = if ($pathRuleCountsPerMap.Count -gt 0) { ($pathRuleCountsPerMap | Measure-Object -Maximum).Maximum } else { 0 }
      $probeDetails = @($gatewayProperties.probes | ForEach-Object {
          $probeProperties = Get-ResourceProperties $_
          [pscustomobject][ordered]@{ Name = $_.name; Protocol = $probeProperties.protocol; Host = Get-ObjectPropertyValue -Object $probeProperties -Name 'host'; Path = $probeProperties.path; Interval = $probeProperties.interval; Timeout = $probeProperties.timeout; UnhealthyThreshold = $probeProperties.unhealthyThreshold }
        })

      $usage = @{
        FrontendIPConfigurations = @($gatewayProperties.frontendIPConfigurations).Count
        FrontendPorts = @($gatewayProperties.frontendPorts).Count
        Listeners = @($gatewayProperties.httpListeners).Count
        ActiveListeners = $activeListenerNames.Count
        BackendPools = $backendPools.Count
        BackendInstancesPerPool = [int]$maximumBackendTargets
        RequestRoutingRules = $routingRules.Count
        BackendHTTPSettings = @($gatewayProperties.backendHttpSettingsCollection).Count
        URLPathMaps = $pathMaps.Count
        URLPathRules = [int]$maximumPathRulesPerMap
        HealthProbes = @($gatewayProperties.probes).Count
      }

      $reportRows = Write-UsageReport -GatewayName $gateway.name -Usage $usage -Limits $limits -WarningThreshold $WarningThreshold

      [ordered]@{
        resourceGroup = $resourceGroup
        name = $gateway.name
        location = $config.location
        sku = $gatewayProperties.sku
        wafPolicyConfigured = [bool](Get-ObjectPropertyValue -Object $firewallPolicy -Name 'id')
        usage = $reportRows
        details = [ordered]@{
          FrontendIPConfigurations = $frontendIpDetails
          FrontendPorts = $frontendPortDetails
          Listeners = $listenerDetails
          ActiveListeners = @($listenerDetails | Where-Object { $activeListenerNames -contains $_.Name })
          BackendPools = $backendPoolDetails
          BackendInstancesPerPool = @($backendInstanceDetails)
          RequestRoutingRules = $routingRuleDetails
          BackendHTTPSettings = $backendSettingsDetails
          URLPathMaps = $pathMapDetails
          URLPathRules = $pathRuleDetails
          HealthProbes = $probeDetails
        }
      }
    } catch {
      Write-Warning "Skipping '$($gateway.name)' in '$resourceGroup': $($_.Exception.Message)"
      [ordered]@{
        resourceGroup = $resourceGroup
        name = $gateway.name
        error = $_.Exception.Message
      }
    }
  }
  Write-Progress -Activity 'Auditing Application Gateways' -Completed
)

if ($Report) {
  if (-not $OutputPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path -Path (Get-Location) -ChildPath "appgw-audit-$timestamp.html"
  }
  Write-HtmlReport -Reports $auditReports -Path $OutputPath -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -ApplicationGatewayName $ApplicationGatewayName
  Write-Host "HTML audit report written to: $OutputPath" -ForegroundColor Green
} elseif ($OutputPath) {
  $parent = Split-Path -Path $OutputPath -Parent
  if ($parent -and -not (Test-Path -Path $parent)) {
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
  }

  $auditReports | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding utf8
  Write-Host "JSON audit report written to: $OutputPath" -ForegroundColor Green
}

Write-Host 'Audit complete. No Azure resources were modified.' -ForegroundColor Green
