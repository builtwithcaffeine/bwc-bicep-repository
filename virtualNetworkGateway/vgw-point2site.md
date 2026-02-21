# Virtual Network Gateway  - Point To Site Configuration

## Initial Setup

Address Pool:
Tunnel Type: `OpenVPN (SSL)`
Authentication `Azure Active Directory`


### Active Directory Configuration

If you've not created the Enterprise Application `Azure VPN`, you can use this link: [Azure VPN](https://login.microsoftonline.com/common/oauth2/authorize?client_id=41b23e61-6c1e-4545-b367-cd054e0ed4b4&response_type=code&redirect_uri=https://portal.azure.com&nonce=1234&prompt=admin_consent)

<br>

> **Azure CLI Query for TenantId:**  \
> `az account show --query tenantId -o tsv`

<br>

Tenant Id: `https://login.microsoftonline.com/{TenantID/`

Audience: `41b23e61-6c1e-4545-b367-cd054e0ed4b4` [Default Azure VPN Enterprise Application]

Issuer: `https://sts.windows.net/{TenantID}/`

<details>
<summary>Pwsh - Collect Tenant Details</summary>
<br>

``` pwsh
$azTenantId = az account show --query tenantId -o tsv
Write-Output "TenantId: https://login.microsoftonline.com/$azTenantId/"
Write-Output "Issuer: https://sts.windows.net/$azTenantId/"
```


</details>

Once this has been setup, You cna download the zip for the Point to Site configuration.

> [!NOTE]
> Remember! to add the user in question to the Enterprise App.

<br>

> [!TIP]
> If you have an Entra P1/P2 Tenant, you can use group configuration, otherwise its: *User Assigned Direct*
