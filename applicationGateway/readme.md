# Application Gateway

This template deploys an Azure Application Gateway WAF_v2 and its supporting
resource group, public IP, virtual network, NSG, WAF policy, and Log Analytics
workspace, and user-assigned managed identity.

## Deployment

Use `main.bicepparam` for example parameter values. Deployments are run through
`Invoke-AzDeployment.ps1`, which validates Azure CLI and Bicep, performs a
what-if preview, and optionally creates the subscription-scope deployment.

## AVM module versions

The template pins the following Azure Verified Modules versions. These are the
latest published patch tags available in the Microsoft Container Registry as of
2026-08-24:

| Module | Version |
| --- | --- |
| Resource group | `0.4.4` |
| User-assigned identity | `0.6.0` |
| Storage account | `0.33.0` |
| Log Analytics workspace | `0.16.1` |
| Network security group | `0.5.3` |
| Virtual network | `0.10.2` |
| Application Gateway WAF policy | `0.3.0` |
| Public IP address | `0.13.0` |
| Application Gateway | `0.10.0` |

The module references use the `br/public:avm` registry and should be reviewed
against the official [Bicep Registry Modules repository](https://github.com/Azure/bicep-registry-modules)
when upgrading.

## Child-resource naming standard

The default Application Gateway child resources use the listener name as their
shared identity. The listener name is composed from the lower-case listener
protocol and the configured host name:

| Child resource | Name format |
| --- | --- |
| Backend pool | `bep-<protocol>-<hostname>` |
| Backend settings | `bes-<protocol>-<hostname>` |
| HTTP listener | `<protocol>-<hostname>` |
| Routing rule | `rule-<protocol>-<hostname>` |
| Health probe | `probe-<protocol>-<hostname>` |
| Redirect configuration | `rdc-<purpose>` |
| Rewrite rule set | `rrs-<purpose>` |
| URL path map | `upm-<purpose>` |

For example, a default HTTP listener for `app.contoso.com` uses:

- Listener: `http-app.contoso.com`
- Backend pool: `bep-http-app.contoso.com`
- Backend settings: `bes-http-app.contoso.com`
- Routing rule: `rule-http-app.contoso.com`
- Health probe: `probe-http-app.contoso.com`

The backend address is populated and the health probe is created when
`defaultBackendFqdn` is not empty. The backend settings, listener, and routing
rule are always configured.
