
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

> **Check Bicep Version**

```
az bicep version
```

## Azure Pre-requisites

### Accept Fortinet Marketplace EULA

Before deploying, you must accept the Marketplace terms for the FortiGate PAYG image:

> **Register Fortigate Market Place Offering**

``` bash
az vm image terms accept --publisher fortinet --offer fortinet_fortigate-vm --plan fortinet_fg-vm_payg_80_g2
```

> **Register EncyptionAtHost Feature**

``` bash
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
```

> **Deploy Azure Bicep**

The template uses FortiGate 8.0.2 Gen2 with Trusted Launch and a 30-GB data
disk. It supplies initial interface and route configuration using the static
addresses defined in the template and enables the local NTP server on port1.
The `timeZone` parameter defaults to `Europe/London`; set it to
`Europe/Amsterdam` to use Amsterdam time.
Configure firewall policies, workload routes and logging destinations separately;
attaching the disk alone does not verify that logs are being recorded.

Separate NSGs are attached to the external and internal subnets. The external
NSG retains the sandbox rules, allowing inbound traffic from any source,
including HTTPS, SSH and NTP on UDP 123. The internal NSG allows all inbound
and outbound traffic to preserve the previous behavior without an NSG. Restrict
access before deploying to an exposed network.

On an incremental redeployment, the previously named NSG is not deleted after
the external subnet is associated with the new external NSG.

The Gen2 image and initial configuration apply to a new VM. Redeploying over an
existing Gen1 VM does not replace its image or rerun initial configuration;
plan a replacement and preserve any existing configuration and disks first.
The data disk incurs additional Azure charges.

``` bash
az deployment sub create --name 'iac-fortigate' --location uksouth --template-file ./infra/main.bicep --parameters ./infra/main.bicepparam
```
