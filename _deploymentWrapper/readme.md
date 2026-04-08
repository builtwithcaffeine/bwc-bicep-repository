# Azure Deployment Wrapper

This folder contains a reusable deployment wrapper script and scope-specific Bicep examples for Azure IaC testing.

## Contents

```text
- Invoke-AzDeployment.ps1   # Wrapper script (what-if + deploy + auth + scope checks)
- example.spAuth.json       # Service principal auth JSON template (placeholder values)
- sub.main.bicep            # Subscription-scope example
- mg.main.bicep             # Management-group-scope example (policy assignment)
- tenant.main.bicep         # Tenant-scope example (create management group)
- modules/                  # Optional local modules
- powershell/               # Optional helper scripts/functions
```

## What the wrapper script does

`Invoke-AzDeployment.ps1` standardizes deployments by:

- validating input and scope-specific required arguments
- checking Azure CLI and Bicep CLI
- supporting user auth or service-principal auth
- printing identity and RBAC context
- generating a unique deployment name that includes a GUID
- running `what-if` before deployment
- prompting for confirmation before create

## Supported scopes

- `sub` (subscription)
- `mg` (management group)
- `tenant` (tenant)

## Important behavior

The wrapper uses `./main.bicep` by default.

You can override this with `-templateFile` when needed (for example: `./sub.main.bicep`, `./mg.main.bicep`, or `./tenant.main.bicep`).

If the selected template file is missing, the wrapper exits with a validation error before deployment.

## Prerequisites

- PowerShell 7+
- Azure CLI (`az`)
- Bicep CLI (`az bicep`)
- required RBAC at the selected deployment scope

## Usage examples

### Subscription scope

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'sub' -subscriptionId '<subscription-id>' -environmentType 'dev' -customerName 'contoso' -location 'westeurope' -deploy
```

### Management group scope

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'mg' -managementGroupId '<management-group-name>' -environmentType 'dev' -customerName 'contoso' -location 'westeurope' -deploy
```

### Tenant scope

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'tenant' -tenantId '<tenant-id>' -environmentType 'dev' -customerName 'contoso' -location 'westeurope' -deploy
```

### Service principal auth example

Credentials file format:

```json
{
  "spAppId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "spAppSecret": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "spTenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Run with service principal auth:

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'sub' -subscriptionId '<subscription-id>' -environmentType 'dev' -customerName 'contoso' -location 'westeurope' -deploy -servicePrincipalAuthentication -spAuthCredentialFile '.\example.spAuth.json'
```

### Custom template example

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'mg' -managementGroupId '<management-group-name>' -environmentType 'prod' -customerName 'fabrikam' -location 'westeurope' -templateFile '.\mg.main.bicep' -deploy
```

## Parameters

| Parameter                         | Description                                                            | Required        |
| --------------------------------- | ---------------------------------------------------------------------- | --------------- |
| `-targetScope`                    | `sub`, `mg`, or `tenant`                                               | ✅              |
| `-environmentType`                | `dev`, `acc`, or `prod`                                                | ✅              |
| `-customerName`                   | Customer or tenant label used by templates                             | ✅              |
| `-location`                       | Azure location for deployment metadata                                 | ✅              |
| `-deploy`                         | Executes deployment (`what-if` + create). If omitted, validation only. | ❌              |
| `-subscriptionId`                 | Required when `-targetScope sub`                                       | Scope-dependent |
| `-managementGroupId`              | Required when `-targetScope mg`                                        | Scope-dependent |
| `-tenantId`                       | Required when `-targetScope tenant`                                    | Scope-dependent |
| `-servicePrincipalAuthentication` | Use SP auth instead of interactive user auth                           | ❌              |
| `-spAuthCredentialFile`           | JSON credential file for SP auth                                       | ❌              |

Optional: `-templateFile` lets you override the default `./main.bicep` path.

Note: `-templateFile` is validated before any deployment action starts. If the file does not exist, the wrapper exits immediately.

## Scope sample notes

### `sub.main.bicep`

- target scope: `subscription`
- sample behavior: creates a resource group using AVM module `br/public:avm/res/resources/resource-group:0.4.3`

### `mg.main.bicep`

- target scope: `managementGroup`
- sample behavior: assigns built-in **Allowed locations** policy using AVM module `br/public:avm/ptn/authorization/policy-assignment:0.5.3`

### `tenant.main.bicep`

- target scope: `tenant`
- sample behavior: creates a management group via AVM module `br/public:avm/res/management/management-group:0.2.0`
- default parent management group name is the tenant root management group name (`tenant().tenantId`)

## Troubleshooting

### "Unable to fetch the latest release" warning

If you see:

`WARNING: Unable to fetch the latest release. Ensure you have internet connectivity.`

this may be GitHub API rate limiting (HTTP 403), not network failure.

### Scope mismatch errors

If you see scope mismatch errors, check that:

- the wrapper `-targetScope` and
- the active `main.bicep` `targetScope`

are aligned.

### Permissions

Ensure the identity used for deployment has sufficient RBAC rights at the intended scope.

## Security notes

- Do not commit service principal secrets.
- Store credential files securely.
- Prefer least-privilege RBAC roles where possible.
