# FortiGate Active/Passive HA Lab (External + Internal Standard Load Balancers)

This lab deploys a High Availability (Active/Passive) pair of FortiGate-VM Next-Generation
Firewalls in Azure, fronted by an external Standard Load Balancer (internet-facing) and an
internal Standard Load Balancer (east/west + outbound), based on Fortinet's official reference
architecture:

- [fortinet/azure-templates - Active-Passive-ELB-ILB](https://github.com/fortinet/azure-templates/tree/main/FortiGate/Active-Passive-ELB-ILB)

> This is a **lab / learning environment**. The NSG rules included are intentionally permissive
> (see [Security notes](#security-notes)) and should be tightened before any production use.

## Architecture

```
                         ┌───────────────────────────┐
        Internet ─────►  │  External Std LB (elb)    │
                         │  HA Ports rule (All/0/0)  │
                         └────────────┬──────────────┘
                                      │ beap-external
                    ┌─────────────────┴─────────────────┐
                    │                                     │
             ┌──────▼──────┐                       ┌──────▼──────┐
             │  FGT-A (P)  │◄──── HA Sync (port3) ─►│  FGT-B (S)  │
             │  port1..4   │                        │  port1..4   │
             └──────┬──────┘                       └──────┬──────┘
                    │                                     │
                    └─────────────────┬─────────────────┘
                                      │ beap-internal
                         ┌────────────┴──────────────┐
        VNET/UDR ◄─────  │  Internal Std LB (ilb)     │
                         │  HA Ports rule (All/0/0)  │
                         └───────────────────────────┘
```

- **External Load Balancer** — Standard SKU, public frontend IP, backend pool with both
  FortiGate external NICs, HA Ports load balancing rule (`protocol: All`, port `0`, floating IP
  enabled) plus a TCP/8008 health probe.
- **Internal Load Balancer** — Standard SKU, private frontend IP (`10.0.0.38`) on the internal
  subnet, same HA Ports pattern. Used as the next-hop target for User Defined Routes (UDR) on
  protected subnets/spokes (not created by this template — see [Extending the lab](#extending-the-lab)).
- **FortiGate HA (`config system ha`)** — Active/Passive (`mode a-p`), unicast heartbeat over
  `port3` (HA sync subnet), session pickup enabled, HA management interface on `port4`.

## Resources deployed

| Resource | Purpose |
| --- | --- |
| Resource Group | `rg-x-<customer>-shared-hub-<env>-<region>` |
| User-Assigned Managed Identity | Used by the FortiGate Azure SDN Connector |
| Network Security Group | Applied to all 4 subnets |
| Virtual Network (`/24`) | 4x `/27` subnets: external, internal, hasync, management |
| External Load Balancer | Internet-facing Standard LB with HA Ports rule |
| Internal Load Balancer | Private Standard LB with HA Ports rule |
| 2x FortiGate-VM (`Standard_D4ls_v5`) | `vm-<customer>-fgt-a-...` (zone 1), `vm-<customer>-fgt-b-...` (zone 2) |

## IP address plan

The private IP addresses below are statically assigned in [main.bicep](main.bicep) (`ipPlan`
variable) so that the cloud-init files below can reference deterministic addresses. If you
change the `ipPlan` variable, update both `customdata-fgt-a.conf` and `customdata-fgt-b.conf`
to match.

| Subnet | CIDR | Gateway | FGT-A (port) | FGT-B (port) |
| --- | --- | --- | --- | --- |
| snet-fortigate-external | 10.0.0.0/27 | 10.0.0.1 | 10.0.0.4 (port1) | 10.0.0.5 (port1) |
| snet-fortigate-internal | 10.0.0.32/27 | 10.0.0.33 | 10.0.0.36 (port2) | 10.0.0.37 (port2) |
| snet-fortigate-hasync | 10.0.0.64/27 | 10.0.0.65 | 10.0.0.68 (port3) | 10.0.0.69 (port3) |
| snet-fortigate-management | 10.0.0.96/27 | 10.0.0.97 | 10.0.0.100 (port4) | 10.0.0.101 (port4) |

Internal Load Balancer frontend (private, static): `10.0.0.38`

## Cloud-init / customData

- [`customdata-fgt-a.conf`](customdata-fgt-a.conf) — injected into the primary FortiGate (priority `255`).
- [`customdata-fgt-b.conf`](customdata-fgt-b.conf) — injected into the secondary FortiGate (priority `1`).

Both files are loaded at deployment time via `loadTextContent()` in `main.bicep` and passed to
the `customData` property of the AVM `compute/virtual-machine` module (Bicep automatically
base64-encodes the content — do not pre-encode it yourself).

Each file configures, based on the [official Fortinet default configuration](https://github.com/fortinet/azure-templates/tree/main/FortiGate/Active-Passive-ELB-ILB#default-configuration):

- `system sdn-connector` — Azure SDN connector using the VM's managed identity (`ha-status enable`).
- `router static` — default route via port1, route to the internal subnet via port2, and static
  routes for the Azure Load Balancer probe source `168.63.129.16` out of both port1 and port2.
- `system probe-response` — responds `OK` on TCP/8008 so the Azure Load Balancer health probes
  succeed on the active unit.
- `system interface` — static IP configuration for port1-port4.
- `system ha` — Active/Passive HA group `AzureHA`, heartbeat on port3, HA management on port4.

## Prerequisites

> **Install/upgrade Azure CLI + Bicep**

```powershell
winget install --id Microsoft.AzureCLI
az bicep install
az bicep version
```

> **Accept the FortiGate Marketplace terms** (one-time per subscription)

```powershell
az vm image terms accept --publisher fortinet --offer fortinet_fortigate-vm_v5 --plan fortinet_fg-vm_payg_2023
```

> **Register the EncryptionAtHost feature** (one-time per subscription)

```powershell
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
```

## Deploy

Update `main.bicepparam` (customer name, environment, region) and supply the admin password
(kept out of source control — pass it interactively or via a pipeline secret):

```powershell
az deployment sub create `
  --name 'iac-fortigate-ha' `
  --location uksouth `
  --template-file ./main.bicep `
  --parameters ./main.bicepparam `
  --parameters adminPassword=$(Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText)
```

> The `adminPassword` must satisfy Azure's Linux VM password complexity rules: 12+ characters,
> and at least 3 of uppercase, lowercase, numbers, and symbols (excluding `'` and `-`).

## Manual HA configuration

If the FortiGate custom data does not configure HA during initial provisioning, configure HA
manually from the console or SSH. A normal incremental Bicep redeployment does not rerun custom
data on an existing VM.

Before starting, verify the IP addresses assigned to the NICs in Azure. The values below use the
[IP address plan](#ip-address-plan). Use the actual NIC address if it differs.

1. On FGT-A, configure the primary unit. Replace `<shared-ha-password>` with a strong password
   and use the same value on FGT-B. Do not commit this password to the repository.

   ```fortios
   config system ha
       set group-id 0
       set group-name "AzureHA"
       set mode a-p
       set password a109e36947ad56de1dca1cc49f0ef8ac9ad9a7b1aa0df41fb3c4cb73c1ff01ea
       set hbdev "port3" 100
       set priority 255
       set override disable
       set session-pickup enable
       set session-pickup-connectionless enable
       set ha-mgmt-status enable
       config ha-mgmt-interfaces
           edit 1
               set interface "port4"
               set gateway 10.0.0.97
           next
       end
       set unicast-hb enable
       set unicast-hb-peerip 10.0.0.69
   end
   ```

2. On FGT-B, use the same configuration with its peer IP and lower priority.

   ```fortios
   config system ha
       set group-id 0
       set group-name "AzureHA"
       set mode a-p
       set password a109e36947ad56de1dca1cc49f0ef8ac9ad9a7b1aa0df41fb3c4cb73c1ff01ea
       set hbdev "port3" 100
       set priority 1
       set override disable
       set session-pickup enable
       set session-pickup-connectionless enable
       set ha-mgmt-status enable
       config ha-mgmt-interfaces
           edit 1
               set interface "port4"
               set gateway 10.0.0.97
           next
       end
       set unicast-hb enable
       set unicast-hb-peerip 10.0.0.68
   end
   ```

3. On FGT-A, verify that the cluster has formed and synchronized.

   ```fortios
   get system ha status
   ```

   A healthy cluster reports `number of member: 2`, lists FGT-A as `Primary` and FGT-B as
   `Secondary`, and reports both members as `in-sync`.

4. If the secondary remains out of sync, connect to it from FGT-A and restart synchronization.

   ```fortios
   execute ha manage 1 <admin-username>
   diagnose sys ha checksum recalculate
   execute ha synchronize start
   ```

   Exit back to FGT-A and rerun `get system ha status`.

## Post-deployment validation

1. Find the external Load Balancer's public IP: `az network public-ip show -g <rg> -n elb-...-pip --query ipAddress -o tsv`.
2. Browse to `https://<public-ip>` (or the management NIC's public/private IP) and sign in with
   `adminUser` / `adminPassword`.
3. On the primary unit, confirm HA sync: `get system ha status` — both units should show as
   `in-sync` with FGT-A as primary (priority 255).
4. Confirm the Azure Load Balancer probe is healthy: Azure Portal → Load Balancer → Insights →
   Health Probe Status.
5. Fail over: `diagnose sys ha reset-uptime` or power off the primary NIC/VM and confirm FGT-B
   is promoted and the Azure LB backend pool shifts traffic.

## Extending the lab

This template intentionally stops at the firewall pair + load balancers, matching the "hub" in
a hub-spoke topology. To build a complete inspection path you would still need to:

- Create spoke VNets/peerings and User Defined Routes (UDR) pointing protected subnets at the
  Internal Load Balancer frontend (`10.0.0.38`) as a "Virtual Appliance" next hop.
- Configure FortiGate VIPs + firewall policies for inbound (DNAT) services on the external LB.
- Configure outbound SNAT firewall policies on the internal→external path.
- Optionally configure the Fabric Connector role assignment (`Reader` on the subscription) for
  the managed identity so the SDN connector can resolve Azure resources/failover public IPs.

See the [official Fortinet documentation](https://github.com/fortinet/azure-templates/tree/main/FortiGate/Active-Passive-ELB-ILB)
for full guidance on East-West routing, inbound/outbound NAT, and IPSEC configuration.

## Security notes

- The NSG applied to all 4 subnets currently includes an `AllowAllInbound` rule (priority 1000,
  `*`/`*`/`*`) inherited from the single-VM `vm-fortigate` module pattern. This is fine for a
  short-lived lab but **must be restricted** (management source IP ranges, remove the
  catch-all allow) before any long-lived or production use.
- `adminPassword` is a `@secure()` parameter — never commit a real password into
  `main.bicepparam`; pass it at deploy time instead.
