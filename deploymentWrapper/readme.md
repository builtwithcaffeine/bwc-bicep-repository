# Azure Deployment Wrapper

``` text
 - Invoke-AzDeployment.ps1 # Deployment Wrapper
 - powershell # Required for PowerShell Functions
 - modules # Required for any Custom Bicep Modules
```

## Invoke-AzDeployment.ps1

### - User Driven Deployment

Using this option, You will be prompted for you're User Account credentials

``` powershell
.\Invoke-AzDeployment.ps1 -targetScope 'sub' -subscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -location 'westeurope' -environmentType 'dev' -deploy
```

### - Service Principal Deployment

To use a Service Principal for authentication, create a JSON file with the following structure:

``` json
    {
        "spAppId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "spAppSecret": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "spTenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    }
```

Then, reference this file when executing the deployment script:

``` powershell
.\Invoke-AzDeployment.ps1 -targetScope 'sub' -subscriptionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -location 'westeurope' -environmentType 'dev' -deploy -servicePrincipalAuthentication -spAuthCredentialFile C:\spAuth\auth.txt
```

## Parameters

| Parameter                        | Description                                                       | Required |
|----------------------------------|-------------------------------------------------------------------|----------|
| `-targetScope`                   | The deployment scope (e.g., `sub`, `mgmt`, `tenant`)             | ✅        |
| `-subscriptionId`                | The target Azure Subscription ID                                 | ✅        |
| `-location`                      | Azure region for deployment                                      | ✅        |
| `-environmentType`               | Deployment environment (`dev`, `acc`, `prod`)                    | ✅        |
| `-deploy`                        | Flag to execute the deployment                                   | ✅        |
| `-servicePrincipalAuthentication`| Use Service Principal authentication (optional)                  | ❌        |
| `-spAuthCredentialFile`          | Path to Service Principal credentials JSON file (required if using `-servicePrincipalAuthentication`) | ❌        |

## Notes
- If using User-Driven Deployment, you must have the necessary Azure permissions to execute the deployment.

- If using Service Principal Deployment, ensure the Service Principal has the correct RBAC permissions for the target subscription.

- The credential file should be stored securely and not committed to source control.

## Troubleshooting

### Authentication Issues
- Ensure you are logged into the correct Azure subscription using `az login`.
- If using a Service Principal, verify the credentials in the JSON file.

### Permission Denied Errors
- Confirm the user or Service Principal has the required **Owner** or **Contributor** role on the subscription.


<details closed>
<summary><h2>Role Based Permissions</h2></summary>

This section covers the implementation of role-based permissions (RBAC) within your environment. It explains how to assign and manage user roles to control access to various resources and services.


> Create Deployment Security Group

``` powershell
$groupName = 'sec-bicep-iac-deployment-rw'
$groupDescription = 'Allow User Bicep deployment permissions for the tenant'
az ad group create --display-name $groupName --mail-nickname $groupName --description $groupDescription
```

### Assign Security Group at Tenant Root Scope

``` powershell
$groupName = 'sec-bicep-iac-deployment-rw'
$groupId = az ad group show --group $groupName --query 'id' -o 'tsv'
az role assignment create --assignee $groupId --scope "/" --role "Owner"
```

### Assign Security Group at Management Group Scope

``` powershell
$managementGroupId = "<ManagementGroupId>"
$groupName = 'sec-bicep-iac-deployment-rw'
$groupId = az ad group show --group $groupName --query 'id' -o 'tsv'
az role assignment create --assignee $groupId --scope "/providers/Microsoft.Management/managementGroups/$managementGroupId" --role "Owner"
```

### Assign Security Group at Subscription Scope

``` powershell
$subscriptionId = az account show --query 'id' --output 'tsv'
$groupName = 'sec-bicep-iac-deployment-rw'
$groupId = az ad group show --group $groupName --query 'id' -o 'tsv'
az role assignment create --assignee $groupId --scope "/subscriptions/$subscriptionId" --role "Owner"
```

### Assign Signed-In User at Tenant Root Scope

``` powershell
$userId = az ad signed-in-user show --query 'id' -o 'tsv'
az role assignment create --assignee $userId --scope "/" --role "Owner"
```

#### Assign Signed-In User at Management Group Scope

``` powershell
$managementGroupId = "<ManagementGroupId>"
$userId = az ad signed-in-user show --query 'id' -o 'tsv'
az role assignment create --assignee $userId --scope "/providers/Microsoft.Management/managementGroups/$managementGroupId" --role "Owner"
```

### Assign Signed-In User at Subscription Scope

``` powershell
$subscriptionId = az account show --query 'id' --output 'tsv'
$userId = az ad signed-in-user show --query 'id' -o 'tsv'
az role assignment create --assignee $userId --scope "/subscriptions/$subscriptionId" --role "Owner"
```

</details>

<details closed>
<summary><h2>TargetScopes Explained</h2></summary>

This section explains the concept of target scopes in the context of Azure deployments and resource management. It describes how to define the scope for resources, enabling you to manage access, policies, and configurations at different levels of the Azure environment.

### Tenant

The **Tenant** scope is the broadest scope, applying deployments across the entire Azure Active Directory tenant.

- **Scope**: `/providers/Microsoft.Management/tenant/{tenantId}`
- **Usage**: Use this scope for global deployments that need to apply across the entire tenant.

### Management Group

The **Management Group** scope targets resources at the management group level, which is a container for managing access and policies across multiple subscriptions.

- **Scope**: `/providers/Microsoft.Management/managementGroups/{managementGroupId}`
- **Usage**: Use this scope for large-scale deployments affecting multiple subscriptions under a management group.

### Subscription

The **Subscription** scope allows deployment of resources across the entire subscription.

- **Scope**: `/subscriptions/{subscriptionId}`
- **Usage**: Use this scope for deployments that involve resources across multiple resource groups within the same subscription.

### Resource Group

The **Resource Group** scope is the most common deployment scope. Resources deployed to this scope are created within a specific resource group.

- **Scope**: `/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}`
- **Usage**: Use this scope when you want to deploy resources to a specific resource group.

</details>