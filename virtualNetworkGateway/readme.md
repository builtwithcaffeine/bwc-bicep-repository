


# Virtual Network Gateway (Hub VPN Gateway)

Subscription-scoped Bicep template that deploys a hub Virtual Network with a Point-to-Site/Site-to-Site capable VPN Gateway, diagnostics wired to a Log Analytics workspace, and optional Entra ID (AAD) SSO for P2S VPN clients.

## Resources Deployed

| Resource | Name Pattern |
| --- | --- |
| Resource Group | `rg-x-<customerName>-shared-hub-<environmentType>-<locationShortCode>` |
| Virtual Network (with `GatewaySubnet`) | `vnet-<customerName>-shared-hub-<environmentType>-<locationShortCode>` |
| Log Analytics Workspace | `log-<customerName>-shared-hub-<environmentType>-<locationShortCode>` |
| Virtual Network Gateway (VPN, RouteBased) | `vng-<customerName>-shared-hub-<environmentType>-<locationShortCode>` |

## Key Parameters (`main.bicep`)

| Parameter | Description | Default |
| --- | --- | --- |
| `customerName` | Customer name, used in resource naming and tags | `bwc` |
| `environmentType` | `dev`, `acc` or `prod` | `dev` |
| `location` / `locationShortCode` | Azure region and its short code used in naming | `westeurope` / `weu` |
| `virtualNetworkAddressPrefixes` | Address prefix(es) for the hub VNet | *(required)* |
| `gatewaySubnetAddressPrefix` | Address prefix for the required `GatewaySubnet` | *(required)* |
| `vpnGatewaySkuName` | `Basic`, `VpnGw1AZ`-`VpnGw5AZ` | `VpnGw1AZ` |
| `vpnGatewayGeneration` | `Generation1` or `Generation2` (Gen2 requires `VpnGw2AZ`+) | `Generation1` |
| `vpnGatewayClusterMode` | `activePassiveNoBgp`, `activePassiveBgp`, `activeActiveNoBgp`, `activeActiveBgp` | `activePassiveNoBgp` |
| `publicIpAvailabilityZones` | Zones for the gateway public IP(s), ignored for `Basic` SKU | `[1, 2, 3]` |
| `enableVirtualNetworkGatewayEntraSSO` | Enables Entra ID SSO for P2S VPN clients | *(required)* |
| `vpnClientAddressPoolPrefix` | P2S client address pool (must not overlap VNet/on-prem ranges) | *(required if SSO enabled)* |
| `vpnClientAadAudience` | Entra ID Enterprise App audience for the Azure VPN Client | *(required if SSO enabled)* |
| `logAnalyticsWorkspaceRetentionDays` | Log Analytics retention in days | `30` |

> Entra ID SSO uses the tenant's `sts.windows.net` issuer and login endpoint automatically - only the Enterprise Application audience needs to be supplied. The legacy "Azure VPN" app is used by default; Microsoft's newer client app (`c632b3df-fb67-4d84-bdcf-b95ad541b5c8`) requires its own admin consent in the tenant before it can be used as `vpnClientAadAudience`.

## Deploying with `Invoke-AzDeployment.ps1`

`main.bicep` uses `targetScope = 'subscription'`, so this module only supports `-targetScope sub` (the `mg`/`tenant` options in the wrapper script don't apply here).

```powershell
.\Invoke-AzDeployment.ps1 -targetScope sub -subscriptionId <subId> -environmentType dev -customerName bwc -location westeurope -deploy
```

The script will:

1. Check the installed Azure CLI/Bicep CLI versions and offer to update them.
2. Authenticate to Azure (user login by default, or `-servicePrincipalAuthentication` with `-spAuthCredentialFile`).
3. Resolve `location` to its short code and validate the signed-in identity's RBAC assignments.
4. Run `az deployment sub what-if`, prompt for confirmation, then run `az deployment sub create`.

By default the script deploys with `./main.bicepparam` (via `-paramFile`, defaults to `./main.bicepparam`) plus inline `--parameters` overrides for `location`, `locationShortCode`, `customerName`, `environmentType` and `deployedBy` - the inline overrides always win over whatever is set in the `.bicepparam` file for those five values.

Deploying without the wrapper script, directly via Azure CLI:

```
az deployment sub create --name 'iac-bwc-vng-infra' --location 'westeurope' --template-file .\main.bicep --parameters .\main.bicepparam
```

## Multi-Customer Deployments

`main.bicep` is fully parametrized (VNet/subnet address space, VPN Gateway SKU/generation/cluster mode, P2S VPN client address pool, Entra ID (AAD) audience, Log Analytics retention, etc.) so it can be reused across customers without editing the template.

Copy `main.bicepparam` per customer (e.g. `contoso.bicepparam`) and override the values that differ:

```powershell
# Via the wrapper script (customerName/location/environmentType still passed as script args)
.\Invoke-AzDeployment.ps1 -targetScope sub -subscriptionId <subId> -environmentType dev -customerName contoso -location westeurope -paramFile .\contoso.bicepparam -deploy

# Or directly with Azure CLI
az deployment sub create --name 'iac-contoso-vng-infra' --location 'westeurope' --template-file .\main.bicep --parameters .\contoso.bicepparam
```
