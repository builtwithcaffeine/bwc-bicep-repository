# Application Gateway diagnostics

Read-only troubleshooting and audit scripts for existing Application Gateway
deployments. Neither script modifies Azure resources. Both require Azure CLI
and read access to the target resources; sign in with `az login` first.

## Invoke-AppGwDiagnostics.ps1

A read-only troubleshooting script for collecting the configuration and
current health of a single Application Gateway. It reports frontend ports,
listeners, routing rules, backend pools, backend settings, probes, the WAF
policy, backend health, and the gateway subnet NSG. Backend targets are
classified as IP address, FQDN, Virtual machine, VMSS, or App Services where
Azure exposes enough information to identify the target. Redirect rules are
shown with their redirect type, target listener, and path or query-string
behavior, so HTTP-to-HTTPS routing can be verified directly. The gateway
summary includes autoscale minimum and maximum capacity. Listener output shows
any listener-specific WAF policy and the effective policy inherited from the
gateway when no listener override is present.

Run it from this directory after signing in with Azure CLI:

```powershell
.\Invoke-AppGwDiagnostics.ps1 `
	-SubscriptionId '<subscription-id>' `
	-ResourceGroupName '<resource-group-name>' `
	-ApplicationGatewayName '<application-gateway-name>'
```

The script writes a timestamped JSON report to the current directory. Use
`-OutputPath` to choose another location. Review the report before sharing it
with support and remove any environment-specific information that should not be
distributed.

## Invoke-AppGwAudit.ps1

Audits one or more Application Gateways' resource usage against documented
Azure limits (frontend IP configurations, ports, listeners, backend pools and
instances, routing rules, backend HTTP settings, URL path maps and rules, and
health probes), with a console table, optional JSON export, and an optional
interactive HTML report.

```powershell
.\Invoke-AppGwAudit.ps1 `
	-SubscriptionId '<subscription-id>' `
	-Report `
	-OutputPath '.\appgw-audit.html'
```

Omit `-ResourceGroupName` and `-ApplicationGatewayName` to audit every
Application Gateway in the subscription, or supply either to narrow the scope.
Use `-WarningThreshold` (0-1, default `0.75`) to adjust when a metric is
flagged as a warning before it reaches its limit.

The HTML report renders each Application Gateway as a header followed by 11
expandable resource sections. Gateways that failed to audit, or that have
CRITICAL or WARNING metrics, are sorted to the top and their affected sections
are expanded automatically. Use the search box to filter gateways by name or
resource group, and print the page to export a shareable PDF copy.
