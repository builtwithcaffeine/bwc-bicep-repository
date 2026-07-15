
## Local Pre-requisites

> **Update WinGet Source**
```
winget source update
```

<p>

> **Install Azure CLI**

```
winget install --id Microsoft.AzureCLI
```

<p>

> **Install Microsoft Bicep (Azure CLI Extension)**

```
az bicep install
```

> Check **Bicep Version**

```
az bicep version
```

## Azure Pre-requisites

### Accept Fortinet Marketplace EULA

Before deploying, you must accept the Marketplace terms for the FortiGate PAYG image:

> **Register Fortigate Market Place Offering**

``` bash
az vm image terms accept --publisher fortinet --offer fortinet_fortigate-vm_v5 --plan fortinet_fg-vm_payg_2023
```

> **Register EncyptionAtHost Feature**

``` bash
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
```

> **Deploy Azure Bicep**

``` bash
az deployment sub create --name 'iac-fortigate' --location uksouth --template-file ./infra/main.bicep --parameters ./infra/main.bicepparam
```
