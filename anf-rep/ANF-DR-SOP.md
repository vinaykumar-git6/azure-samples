# Azure NetApp Files — Cross-Region DR Replication SOP
## UAE North → Germany West Central

**Author:** Vinay Kumar  
**Date:** April 11, 2026  
**Subscription:** `<YOUR-SUBSCRIPTION-ID>`

---

## Overview

This document is a step-by-step Standard Operating Procedure (SOP) for setting up and running **cross-region Disaster Recovery (DR) replication** of Azure NetApp Files (ANF) volumes from **UAE North** to **Germany West Central** using `rsync` over private VNet peering, via relay VMs.

It also covers deploying AKS workloads on both regions that read/write to ANF shares, validating the replication end-to-end.

---

## Architecture Diagram

```
┌─────────────────────────────────┐          ┌──────────────────────────────────┐
│         UAE North               │          │       Germany West Central        │
│                                 │          │                                  │
│  AKS Cluster: aks-vk-with-cilium│          │  AKS Cluster: anf-aks-test       │
│  ┌──────────────────────┐       │          │  ┌──────────────────────┐        │
│  │ Pod: anf-uae-logger  │       │          │  │ Pod: anf-germany-    │        │
│  │ Writes every 10 min  │       │          │  │ reader               │        │
│  │ → /mnt/anf/          │       │          │  │ Reads /mnt/anf/      │        │
│  └──────┬───────────────┘       │          │  └──────┬───────────────┘        │
│         │ NFS mount             │          │         │ NFS mount              │
│  ┌──────▼───────────────┐       │          │  ┌──────▼───────────────┐        │
│  │ ANF Volume           │       │          │  │ ANF Volume           │        │
│  │ netapp-fs-uaenorth   │       │          │  │ netapps-fs-germany   │        │
│  │ fs-naapp-demo-vol    │       │          │  │ demo-vol             │        │
│  │ Mount: 10.0.22.4     │       │          │  │ Mount: 10.0.251.4    │        │
│  └──────────────────────┘       │          │  └──────────────────────┘        │
│                                 │          │                                  │
│  ┌──────────────────────┐       │  VNet    │  ┌──────────────────────┐        │
│  │ Relay VM             │◄──────┼─Peering─►│  │ Relay VM             │        │
│  │ relay-uaenorth       │       │          │  │ relay-germany        │        │
│  │ 10.0.23.x (private)  │──rsync over SSH──►  │ 10.0.250.4 (private) │        │
│  └──────────────────────┘       │          │  └──────────────────────┘        │
│  VNet: aks-vk-vnet              │          │  VNet: anf-dest-vnet             │
│  RG:   azure-vk-rg              │          │  RG:   anf-mashreq               │
└─────────────────────────────────┘          └──────────────────────────────────┘
```

---

## Resource Inventory

| Resource | UAE North | Germany West Central |
|---|---|---|
| **Resource Group** | `azure-vk-rg` / `anf-mashreq` | `anf-mashreq` |
| **ANF Account** | `netapp-fs-uaenorth` | `netapps-fs-germany` |
| **ANF Pool** | `fs-pool-demo` | `fa-pool-demo` |
| **ANF Volume** | `fs-naapp-demo-vol` | `demo-vol` |
| **ANF Mount IP** | `10.0.22.4` | `10.0.251.4` |
| **VNet** | `aks-vk-vnet` | `anf-dest-vnet` (10.0.248.0/23) |
| **Relay VM** | `relay-uaenorth` | `relay-germany` |
| **Relay Subnet** | `subnet-relay` (10.0.23.0/25) | `subnet-relay` (10.0.250.0/25) |
| **Relay Public IP** | `<UAE-RELAY-PUBLIC-IP>` | `<GERMANY-RELAY-PUBLIC-IP>` |
| **Relay Private IP** | (dynamic) | `10.0.250.4` |
| **AKS Cluster** | `aks-vk-with-cilium` | `anf-aks-test` |
| **ACR** | `<UAE-ACR-NAME>.azurecr.io` | `<GERMANY-ACR-NAME>` |
| **Snapshot used** | `dr-snap-20260411061727` | — |

---

## Part 1 — UAE North: AKS Pod Writing to ANF

### 1.1 What it does
A pod running on the UAE AKS cluster continuously mounts the UAE ANF NFS share and writes a timestamped log line every **10 minutes**. This simulates application I/O that needs to be replicated to Germany.

### 1.2 Manifest file
**File:** `anf-uae-logger.yaml`

**Resources created:**
- `Namespace`: `anf-demo`
- `PersistentVolume`: `anf-uae-pv` — static NFS binding to `10.0.22.4:/fs-naapp-demo-vol`
- `PersistentVolumeClaim`: `anf-uae-pvc` — binds to the above PV
- `Deployment`: `anf-uae-logger` — alpine pod, writes `"<hostname> Hello from UAE North AKS Cluster - <timestamp>"` to `/mnt/anf/uae-north.log` every 600 seconds

### 1.3 Image note
Standard `busybox` and `alpine` images fail to pull because the AKS cluster restricts to attached ACR. Use `<UAE-ACR-NAME>.azurecr.io/alpine:3.19` (ACR-mirrored image).

### 1.4 Deploy

```bash
az aks get-credentials --resource-group azure-vk-rg --name aks-vk-with-cilium --overwrite-existing
kubectl apply -f anf-uae-logger.yaml
kubectl get pods -n anf-demo -w
kubectl logs -f deployment/anf-uae-logger -n anf-demo
```

---

## Part 2 — DR Replication Script Setup

### 2.1 Overview
The replication is handled by `anf-rsync-replicate.ps1` — a PowerShell script that:
1. Sets up global VNet peering between UAE and Germany VNets
2. Configures SSH key exchange between the relay VMs
3. Mounts both ANF volumes on respective relay VMs
4. Runs `rsync` from a UAE ANF snapshot to the Germany ANF volume via private IP

### 2.2 Key design decisions

| Decision | Reason |
|---|---|
| **Relay VMs instead of direct pod-to-pod rsync** | AKS pods can't directly expose NFS cross-region; VMs can mount NFS and run rsync |
| **`az vm run-command invoke` instead of SSH** | Port 22 is blocked from the local machine to Azure VMs; run-command goes through the Azure control plane |
| **VNet Peering** | Relay VMs are in different VNets; rsync uses private IPs, so peering is required |
| **SSH key generated ON relay VM** | `run-command` executes as `root`; keys must be at `/root/.ssh/` not `/home/azureuser/.ssh/` |
| **`--rsync-path 'sudo rsync'`** | rsync SSH receiver runs as `azureuser` but needs to write to NFS root owned by root |
| **`--exclude='.snapshot'`** | ANF auto-creates a read-only `.snapshot` dir; `--delete` would fail trying to remove it |
| **Snapshot-based sync** | Ensures a consistent point-in-time copy; avoids mid-write file corruption |

---

## Part 3 — Relay VM Setup (One-Time)

### 3.1 Relay VM details

Both relay VMs were created manually (CLI capacity constraints required `--zone 1` for Germany):

**UAE Relay:**
```bash
# Already existed: relay-uaenorth in azure-vk-rg
# VNet: aks-vk-vnet, Subnet: subnet-relay (10.0.23.0/25)
```

**Germany Relay:**
```bash
az vm create \
  --resource-group anf-mashreq \
  --name relay-germany \
  --image Ubuntu2204 \
  --size Standard_D2s_v3 \
  --vnet-name anf-dest-vnet \
  --subnet subnet-relay \
  --admin-username azureuser \
  --generate-ssh-keys \
  --zone 1
```

> **Note:** `Standard_B2s` and `Standard_D2as_v4` are not available in Germany West Central. Use `Standard_D2s_v3` with `--zone 1`.

### 3.2 Run init

```powershell
.\anf-rsync-replicate.ps1 init
```

This command:
1. Calls `Invoke-Peering` (see Part 4)
2. Calls `Get-RelayIPs` to fetch Germany relay's private IP
3. Installs `nfs-common` and `rsync` on both relay VMs
4. Calls `Invoke-Keys` (see Part 5)

---

## Part 4 — VNet Peering (One-Time)

### 4.1 Why needed
Relay VMs are in different VNets. rsync uses the Germany relay's **private IP** (`10.0.250.4`) over SSH. Without VNet peering, TCP port 22 is unreachable across VNets.

### 4.2 Run manually (idempotent)

```powershell
.\anf-rsync-replicate.ps1 peering
```

### 4.3 What it does
1. Creates peering `peer-uae-to-germany`: `aks-vk-vnet` → `anf-dest-vnet`
2. Creates peering `peer-germany-to-uae`: `anf-dest-vnet` → `aks-vk-vnet`
3. Adds NSG rule `Allow-SSH-from-UAE` on Germany relay NSG:
   - Source: `10.0.23.0/25` (UAE relay subnet)
   - Destination port: `22`
   - Protocol: TCP
   - Priority: 200

Both peerings are checked for existence before creating (idempotent — safe to re-run).

---

## Part 5 — SSH Key Exchange Between Relay VMs (One-Time)

### 5.1 Why needed
rsync transfers data from UAE relay to Germany relay via SSH. The UAE relay must have a private key, and Germany relay must trust the corresponding public key.

### 5.2 Run manually (idempotent)

```powershell
.\anf-rsync-replicate.ps1 keys
```

### 5.3 What it does

**Step 1 — Generate key pair on UAE relay (as root):**
```bash
# run via az vm run-command invoke on relay-uaenorth
mkdir -p /root/.ssh && chmod 700 /root/.ssh
ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_rsa   # skipped if key already exists
```

**Step 2 — Read public key back from UAE relay:**
The script calls `run-command` with `base64 -w0 /root/.ssh/id_rsa.pub` and parses the stdout from the JSON response.

**Step 3 — Authorize public key on Germany relay:**
```bash
# run via az vm run-command invoke on relay-germany
mkdir -p /home/azureuser/.ssh && chmod 700 /home/azureuser/.ssh
echo "<base64-pubkey>" | base64 -d >> /home/azureuser/.ssh/authorized_keys
sort -u /home/azureuser/.ssh/authorized_keys -o /home/azureuser/.ssh/authorized_keys
chmod 600 /home/azureuser/.ssh/authorized_keys
chown -R azureuser:azureuser /home/azureuser/.ssh
```

**Step 4 — Configure passwordless sudo for rsync on Germany relay:**
```bash
echo "azureuser ALL=(ALL) NOPASSWD: /usr/bin/rsync" > /etc/sudoers.d/rsync-nopasswd
chmod 440 /etc/sudoers.d/rsync-nopasswd
```
This is required because rsync receiver needs to write to the NFS mount created by root.

> **Key lesson:** `az vm run-command invoke` runs as **root** on the VM. Keys must live at `/root/.ssh/`, not `/home/azureuser/.ssh/`. The rsync SSH connection uses `azureuser@<ip>` so the public key goes in azureuser's `authorized_keys`.

---

## Part 6 — Running a Replication Sync

### 6.1 Run sync

```powershell
.\anf-rsync-replicate.ps1 sync
```

### 6.2 What happens step by step

| Step | Action |
|---|---|
| 1 | Fetch Germany relay's private IP |
| 2 | Skip snapshot creation — use existing snapshot `dr-snap-20260411061727` |
| 3 | Mount UAE ANF volume on `relay-uaenorth` at `/mnt/anf-src` |
| 4 | Mount Germany ANF volume on `relay-germany` at `/mnt/anf-dst` (then `chmod 777` the mount point) |
| 5 | Run rsync from UAE snapshot path → Germany mount via `azureuser@10.0.250.4` |
| 6 | Validate: print file counts on both sides |
| 7 | Unmount both volumes cleanly |

### 6.3 rsync command used (on UAE relay as root)

```bash
rsync -avz --delete --exclude='.snapshot' --stats \
  --log-file=/var/log/anf-rsync.log \
  --rsync-path 'sudo rsync' \
  -e 'ssh -i /root/.ssh/id_rsa -o StrictHostKeyChecking=no' \
  /mnt/anf-src/.snapshot/dr-snap-20260411061727/ \
  azureuser@10.0.250.4:/mnt/anf-dst/
```

### 6.4 Common errors and fixes

| Error | Cause | Fix |
|---|---|---|
| `Permission denied (publickey)` | Key placed in wrong user's `.ssh` | Run `.\anf-rsync-replicate.ps1 keys` |
| `change_dir failed: Permission denied (13)` | Mount point owned by root, rsync receiver is azureuser | `chmod 777` mount point + `--rsync-path 'sudo rsync'` |
| `rmdir(.snapshot) failed: Read-only file system` | ANF `.snapshot` dir is read-only system directory | Add `--exclude='.snapshot'` to rsync |
| `ConnectionResetError(10054)` | Azure run-command transient failure | Re-run the script |
| `AvailabilityZoneNotSupported` | Germany West Central has no AKS zones | Remove `--zones` from AKS commands |
| `VM size not allowed` | SKU not available in region/subscription | Use `Standard_D2ads_v6` for AKS in Germany |

### 6.5 Force clean unmount

If mounts are stuck:
```powershell
.\anf-rsync-replicate.ps1 clean
```

---

## Part 7 — Script Mode Reference

```
.\anf-rsync-replicate.ps1 <mode>

  init    — Install nfs-common + rsync on relay VMs, run peering + keys (one-time)
  peering — Create global VNet peering UAE ↔ Germany + NSG rule (idempotent)
  keys    — Generate SSH key on UAE relay, authorize on Germany relay (idempotent)
  sync    — Run rsync replication cycle (schedule this for your RPO)
  clean   — Force unmount volumes on both relay VMs
```

### Scheduling sync for RPO

To run every hour via Windows Task Scheduler:
```
Program: powershell.exe
Arguments: -NonInteractive -File "C:\...\anf-rsync-replicate.ps1" sync
```

---

## Part 8 — Germany AKS Cluster (anf-aks-test)

### 8.1 Purpose
A test AKS cluster in Germany West Central to validate that replicated data is readable from a Kubernetes workload — simulating a DR failover scenario.

### 8.2 Create the cluster

```powershell
.\create-anf-aks.ps1
```

### 8.3 What the script creates

| Step | Resource | Detail |
|---|---|---|
| 1 | Subnet `subnet-aks` | `10.0.248.0/24` inside `anf-dest-vnet` |
| 2 | ACR `<GERMANY-ACR-NAME>` | Basic SKU, `anf-mashreq` RG |
| 3 | Managed identity `id-anf-aks-ctrl` | AKS control plane identity |
| 4 | Managed identity `id-anf-aks-kubelet` | Kubelet / node pool identity |
| 5 | Role: Network Contributor | Control-plane identity → VNet (required for Azure CNI) |
| 6 | Role: AcrPull | Kubelet identity → ACR (required to pull images) |
| 7 | Role: Managed Identity Operator | Control-plane → kubelet identity |
| 8 | AKS cluster `anf-aks-test` | Azure CNI + Calico, `Standard_D2ads_v6`, 1 system node |
| 9 | User node pool `userpool` | 1 node, same SKU, mode=User |
| 10 | kubeconfig | Merged into `~/.kube/config` |

### 8.4 Networking details

| Setting | Value |
|---|---|
| Network plugin | `azure` (Azure CNI — pods get VNet IPs) |
| Network policy | `calico` |
| AKS subnet | `10.0.248.0/24` (within `anf-dest-vnet` 10.0.248.0/23) |
| Service CIDR | `172.16.0.0/16` (isolated from VNet space) |
| DNS service IP | `172.16.0.10` |

### 8.5 Lessons learned for Germany West Central

- No availability zones supported for AKS — omit `--zones`
- Reserved labels like `agentpool` cannot be set via `--nodepool-labels` — omit
- Allowed 2-vCPU SKUs: `Standard_D2ads_v6`, `Standard_D2as_v6`, `Standard_D2pds_v5`

---

## Part 9 — Germany AKS Pod Reading ANF Share

### 9.1 Purpose
Deploys a reader pod on the Germany AKS cluster that mounts the Germany ANF volume and prints all file contents to stdout every 60 seconds. This validates that rsync-replicated files are actually readable from the Germany side.

### 9.2 Deploy

```bash
az aks get-credentials --resource-group anf-mashreq --name anf-aks-test --overwrite-existing
kubectl apply -f anf-germany-reader.yaml
kubectl get pod anf-germany-reader -n anf-demo -w
kubectl logs -f anf-germany-reader -n anf-demo
```

### 9.3 Expected output (after a successful sync)

```
=== ANF Germany volume reader started at Sat Apr 11 07:00:00 UTC 2026 ===
=== Mount point: /mnt/anf ===

──────────────────────────────────────────────
  Scan at Sat Apr 11 07:00:01 UTC 2026
──────────────────────────────────────────────
  Total files found: 1

┌── FILE: /mnt/anf/uae-north.log ──────────────────────────
anf-uae-logger-abc123 Hello from UAE North AKS Cluster - Sat Apr 11 06:50:00 UTC 2026
anf-uae-logger-abc123 Hello from UAE North AKS Cluster - Sat Apr 11 07:00:00 UTC 2026
└─────────────────────────────────────────────
```

### 9.4 Manifest resources

| Resource | Name | Namespace |
|---|---|---|
| PersistentVolume | `anf-germany-pv` | cluster-wide |
| PersistentVolumeClaim | `anf-germany-pvc` | `anf-demo` |
| Pod | `anf-germany-reader` | `anf-demo` |

---

## Part 10 — End-to-End Validation Checklist

```
[ ] UAE AKS pod is running and writing to ANF every 10 minutes
      kubectl get pods -n anf-demo --context <uae-context>
      kubectl logs -f deployment/anf-uae-logger -n anf-demo

[ ] VNet peering is Connected in both directions
      az network vnet peering list --resource-group azure-vk-rg --vnet-name aks-vk-vnet -o table
      az network vnet peering list --resource-group anf-mashreq --vnet-name anf-dest-vnet -o table

[ ] SSH key exchange is complete
      .\anf-rsync-replicate.ps1 keys   # safe to re-run

[ ] Sync completes without error
      .\anf-rsync-replicate.ps1 sync

[ ] File counts match (check sync output)
      Source count: N files
      Destination count: N files   ← must match

[ ] Germany reader pod shows replicated files
      kubectl logs -f anf-germany-reader -n anf-demo --context <germany-context>
```

---

## File Reference

| File | Purpose |
|---|---|
| `anf-rsync-replicate.ps1` | Main DR replication script (all modes) |
| `anf-uae-logger.yaml` | K8s manifests: UAE pod writing to ANF |
| `anf-germany-reader.yaml` | K8s manifests: Germany pod reading ANF |
| `create-anf-aks.ps1` | Creates Germany AKS cluster, ACR, identities, node pools |
| `ANF-DR-SOP.md` | This document |
