# BuiltWithCaffeine Bicep Repository

Reusable Azure Infrastructure-as-Code templates built with [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/overview).

This repository contains deployment examples and reusable patterns for deploying Azure services at different scopes, including tenant, management group, and subscription.

## What is in this repository?

The repository is organized by workload or Azure service. Most folders contain:

- `main.bicep` - the entrypoint template
- `main.bicepparam` - example parameter values when applicable
- `Invoke-AzDeployment.ps1` - a PowerShell deployment wrapper used to validate prerequisites and run the deployment
- `modules/` - reusable Bicep modules for the workload
- `powershell/` - supporting PowerShell functions or helpers when needed

## Common deployment pattern

Many templates in this repository use a local `Invoke-AzDeployment.ps1` script to:

- validate required input values
- confirm Azure CLI and Bicep CLI availability
- authenticate using either user login or a service principal
- validate the selected Bicep template file (defaults to `./main.bicep`)
- run a `what-if` preview before deployment
- execute the Bicep deployment with consistent metadata and a unique deployment name

Example flow:

1. Open a PowerShell terminal in the template folder.
2. Review the local `readme.md` if the folder provides one.
3. Run the local `Invoke-AzDeployment.ps1` script with the parameters required by that workload.
4. Review the `what-if` output.
5. Confirm the deployment when prompted.

## Deployment examples

### Subscription scope

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'sub' -subscriptionId '<subscription-id>' -environmentType 'dev' -customerName 'bwc' -location 'westeurope' -deploy
```

### Management group scope

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'mg' -managementGroupId '<management-group-id>' -environmentType 'dev' -customerName 'bwc' -location 'westeurope' -deploy
```

### Tenant scope

```powershell
.\Invoke-AzDeployment.ps1 -targetScope 'tenant' -tenantId '<tenant-id>' -environmentType 'dev' -customerName 'bwc' -location 'westeurope' -deploy
```

## Identity and RBAC validation

Before any deployment starts, the wrapper script runs an identity check that provides visibility into who is deploying and what permissions they have.

### Identity detection

- **User accounts** — displays the signed-in email, display name, and identity type.
- **Service principals** — displays the application display name and skips group membership checks (not applicable to SPs).

### RBAC assignment listing

The script queries Azure for all role assignments associated with the signed-in identity (including inherited and group-based assignments) and prints the unique role names. This gives a quick summary of what the identity is authorized to do.

### Scoped group membership check

For user accounts, the script performs an additional check for **Owner** and **Contributor** roles at the target deployment scope:

- **Subscription scope** — checks role assignments scoped to `/subscriptions/<id>`.
- **Management group scope** — checks role assignments scoped to `/providers/Microsoft.Management/managementGroups/<id>`.
- **Tenant scope** — checks role assignments scoped to the tenant root (`/`).

For each role, it detects:

- **Direct assignments** — the identity itself holds the role at that scope.
- **Group-based assignments** — the identity is a member of a group that holds the role. The script enumerates groups with Owner or Contributor at the scope and checks whether the signed-in user is a member.

This helps confirm the identity has sufficient permissions before the deployment begins, reducing failed deployments due to missing RBAC.

## Recommended starting points

- Start with `_deploymentWrapper/` if you want to understand the standard deployment workflow used across the repository.
- Review workload-specific folders for service examples and module structure.
- Use the included `main.bicepparam` files, where present, as reference input for your own environments.

## Notes

- Deployment scope varies by template. Some templates are intended for subscription scope, while others support management group or tenant scope.
- RBAC requirements depend on the target scope and resource types being deployed.
- Do not commit service principal secrets or environment-specific sensitive values to source control.

## Contributing

When adding new templates to this repository, keep the structure consistent:

- use a clear folder per workload
- provide a `main.bicep` entrypoint
- include supporting modules in `modules/`
- document usage and prerequisites in a local `readme.md`
- keep deployment scripts aligned with the documented parameters
