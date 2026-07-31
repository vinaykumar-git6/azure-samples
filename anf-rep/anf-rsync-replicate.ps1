# =============================================================================
# ANF NFS rsync Replication — UAE North → Germany West Central
# Volumes are PRE-CREATED. This script handles:
#   init   — create relay VMs (one-time)
#   sync   — rsync replication cycle (run on schedule for RPO)
#   clean  — unmount and stop
#
# Usage:
#   .\anf-rsync-replicate.ps1 init     # first time: create relay VMs
#   .\anf-rsync-replicate.ps1 sync     # run rsync (Task Scheduler-friendly)
#   .\anf-rsync-replicate.ps1 clean    # unmount both relay VMs
# =============================================================================

param(
    [Parameter(Position=0)]
    [ValidateSet("init","sync","clean","peering","keys")]
    [string]$Mode = ""
)

$ErrorActionPreference = "Stop"

# =============================================================================
# ── VARIABLES ─────────────────────────────────────────────────────────────────
# =============================================================================

$SUBSCRIPTION = "<YOUR-SUBSCRIPTION-ID>"

# ── Source — UAE North ────────────────────────────────────────────────────────
$SRC_RESOURCE_GROUP  = "anf-mashreq"
$SRC_LOCATION        = "uaenorth"
$SRC_ANF_ACCOUNT     = "netapp-fs-uaenorth"
$SRC_ANF_POOL        = "fs-pool-demo"
$SRC_ANF_VOLUME      = "fs-naapp-demo-vol"
$SRC_ANF_MOUNT_IP    = "10.0.22.4"

# ── Destination — Germany West Central ───────────────────────────────────────
$DST_RESOURCE_GROUP  = "anf-mashreq"
$DST_LOCATION        = "germanywestcentral"
$DST_ANF_ACCOUNT     = "netapps-fs-germany"
$DST_ANF_POOL        = "fa-pool-demo"
$DST_ANF_VOLUME      = "demo-vol"
$DST_ANF_MOUNT_IP    = "10.0.251.4"

# ── Relay VM — UAE North ──────────────────────────────────────────────────────
$SRC_RELAY_RG        = "azure-vk-rg"
$SRC_RELAY_VM        = "relay-uaenorth"
$SRC_RELAY_VNET      = "aks-vk-vnet"          # fill in: VNet in UAE North that can reach ANF subnet
$SRC_RELAY_SUBNET    = "subnet-relay"          # fill in: subnet in that VNet
$SRC_RELAY_VM_SIZE   = "Standard_B2s"
$SRC_RELAY_ADMIN     = "azureuser"
$SRC_RELAY_SSH_KEY   = "$HOME\.ssh\id_rsa.pub"   # path to your public key

# ── Relay VM — Germany West Central ──────────────────────────────────────────
$DST_RELAY_RG        = "anf-mashreq"
$DST_RELAY_VM        = "relay-germany"
$DST_RELAY_VNET      = "anf-dest-vnet"          # fill in: VNet in Germany that can reach ANF subnet
$DST_RELAY_SUBNET    = "subnet-relay"          # fill in: subnet in that VNet
$DST_RELAY_VM_SIZE   = "Standard_D2as_v4"
$DST_RELAY_ADMIN     = "azureuser"
$DST_RELAY_SSH_KEY   = "$HOME\.ssh\id_rsa.pub"

# ── rsync / mount settings ────────────────────────────────────────────────────
$SRC_MOUNT_DIR         = "/mnt/anf-src"
$DST_MOUNT_DIR         = "/mnt/anf-dst"
$RSYNC_LOG             = "/var/log/anf-rsync.log"
$RSYNC_BANDWIDTH_LIMIT = 0         # KB/s total across all jobs; 0 = unlimited
$RSYNC_PARALLEL_JOBS   = 8         # number of concurrent rsync workers (parallelism)

# =============================================================================
# ── HELPERS ───────────────────────────────────────────────────────────────────
# =============================================================================

function Log($msg) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
}

function Bail($msg) {
    Write-Error "[ERROR] $msg"
    exit 1
}

# Run a shell command on the source relay VM via Azure control plane (no SSH/port 22 needed)
function Src-Cmd($cmd) {
    az vm run-command invoke `
        --resource-group $SRC_RELAY_RG `
        --name $SRC_RELAY_VM `
        --subscription $SUBSCRIPTION `
        --command-id RunShellScript `
        --scripts $cmd `
        --output json | ConvertFrom-Json | ForEach-Object { $_.value | ForEach-Object { Write-Host $_.message } }
    if ($LASTEXITCODE -ne 0) { Bail "run-command failed on UAE relay" }
}

# Run a shell command on the destination relay VM via Azure control plane (no SSH/port 22 needed)
function Dst-Cmd($cmd) {
    az vm run-command invoke `
        --resource-group $DST_RELAY_RG `
        --name $DST_RELAY_VM `
        --subscription $SUBSCRIPTION `
        --command-id RunShellScript `
        --scripts $cmd `
        --output json | ConvertFrom-Json | ForEach-Object { $_.value | ForEach-Object { Write-Host $_.message } }
    if ($LASTEXITCODE -ne 0) { Bail "run-command failed on Germany relay" }
}

function Get-RelayIPs {
    az account set --subscription $SUBSCRIPTION | Out-Null
    # Only private IP of Germany relay is needed (rsync crosses VMs over private network)
    $script:DST_RELAY_PRIVATE_IP = az vm show -d `
        --resource-group $DST_RELAY_RG --name $DST_RELAY_VM `
        --subscription $SUBSCRIPTION `
        --query privateIps -o tsv
    Log "Germany relay private IP: $($script:DST_RELAY_PRIVATE_IP)"
}

# =============================================================================
# ── INIT — create relay VMs (one-time) ───────────────────────────────────────
# =============================================================================

function New-RelayVM($rg, $location, $vm, $vnet, $subnet, $size, $admin, $sshKey) {
    # Try the preferred size first, then fall back through common small SKUs
    $sizeFallbacks = @(
        $size,
        "Standard_D2s_v3",
        "Standard_D2s_v4",
        "Standard_D2s_v5",
        "Standard_D2as_v4",
        "Standard_D2as_v5",
        "Standard_D2_v3",
        "Standard_D2_v4",
        "Standard_D2_v5",
        "Standard_E2s_v3",
        "Standard_F2s_v2"
    ) | Select-Object -Unique

    $created = $false
    foreach ($sku in $sizeFallbacks) {
        Log "Trying VM size '$sku' for '$vm' in $location..."
        az vm create `
            --resource-group $rg `
            --name $vm `
            --location $location `
            --image "Canonical:ubuntu-24_04-lts:server:latest" `
            --size $sku `
            --vnet-name $vnet `
            --subnet $subnet `
            --admin-username $admin `
            --ssh-key-values $sshKey `
            --public-ip-sku Standard `
            --nsg-rule SSH `
            --output none 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Log "VM '$vm' created with size '$sku'"
            $created = $true
            break
        }
        Log "Size '$sku' unavailable, trying next..."
    }
    if (-not $created) { Bail "Failed to create VM '$vm' — all SKUs exhausted. Check capacity in $location." }
}

# =============================================================================
# ── PEERING — global VNet peering + NSG rule (idempotent) ───────────────────
# =============================================================================

function Invoke-Peering {
    Log "=== Setting up global VNet peering: $SRC_RELAY_VNET ↔ $DST_RELAY_VNET ==="
    az account set --subscription $SUBSCRIPTION | Out-Null

    $srcVnetId = az network vnet show --resource-group $SRC_RELAY_RG --name $SRC_RELAY_VNET `
        --subscription $SUBSCRIPTION --query id -o tsv
    $dstVnetId = az network vnet show --resource-group $DST_RELAY_RG --name $DST_RELAY_VNET `
        --subscription $SUBSCRIPTION --query id -o tsv

    # Peering: UAE → Germany
    $existingSrc = az network vnet peering list --resource-group $SRC_RELAY_RG --vnet-name $SRC_RELAY_VNET `
        --subscription $SUBSCRIPTION --query "[?remoteVirtualNetwork.id=='$dstVnetId'].name" -o tsv
    if (-not $existingSrc) {
        Log "Creating peering UAE → Germany..."
        az network vnet peering create `
            --resource-group $SRC_RELAY_RG `
            --vnet-name $SRC_RELAY_VNET `
            --name "peer-uae-to-germany" `
            --remote-vnet $dstVnetId `
            --allow-vnet-access `
            --subscription $SUBSCRIPTION `
            --output none
        if ($LASTEXITCODE -ne 0) { Bail "Failed to create UAE → Germany peering" }
    } else { Log "Peering UAE → Germany already exists, skipping." }

    # Peering: Germany → UAE
    $existingDst = az network vnet peering list --resource-group $DST_RELAY_RG --vnet-name $DST_RELAY_VNET `
        --subscription $SUBSCRIPTION --query "[?remoteVirtualNetwork.id=='$srcVnetId'].name" -o tsv
    if (-not $existingDst) {
        Log "Creating peering Germany → UAE..."
        az network vnet peering create `
            --resource-group $DST_RELAY_RG `
            --vnet-name $DST_RELAY_VNET `
            --name "peer-germany-to-uae" `
            --remote-vnet $srcVnetId `
            --allow-vnet-access `
            --subscription $SUBSCRIPTION `
            --output none
        if ($LASTEXITCODE -ne 0) { Bail "Failed to create Germany → UAE peering" }
    } else { Log "Peering Germany → UAE already exists, skipping." }

    # ── NSG rule: allow SSH (port 22) from UAE relay subnet → Germany relay ──
    Log "Adding NSG rule to allow SSH from UAE relay subnet to Germany relay..."
    $dstNsg = az network nsg list --resource-group $DST_RELAY_RG --subscription $SUBSCRIPTION `
        --query "[?contains(name,'relay-germany')].name" -o tsv
    if ($dstNsg) {
        az network nsg rule create `
            --resource-group $DST_RELAY_RG `
            --nsg-name $dstNsg `
            --name "Allow-SSH-from-UAE" `
            --priority 200 `
            --source-address-prefixes "10.0.23.0/25" `
            --destination-port-ranges 22 `
            --protocol Tcp `
            --access Allow `
            --subscription $SUBSCRIPTION `
            --output none 2>&1 | Out-Null
        Log "NSG rule added"
    } else { Log "NSG not found for Germany relay — skipping NSG rule (add manually if needed)" }

    Log "=== Peering setup complete ==="
}

function Invoke-Init {
    if (-not $SRC_RELAY_VNET)   { Bail "SRC_RELAY_VNET is not set"   }
    if (-not $SRC_RELAY_SUBNET) { Bail "SRC_RELAY_SUBNET is not set" }
    if (-not $DST_RELAY_VNET)   { Bail "DST_RELAY_VNET is not set"   }
    if (-not $DST_RELAY_SUBNET) { Bail "DST_RELAY_SUBNET is not set" }

    az account set --subscription $SUBSCRIPTION | Out-Null

    # Skip VM creation — both relay VMs are already provisioned
    # New-RelayVM $SRC_RELAY_RG $SRC_LOCATION $SRC_RELAY_VM ...
    # New-RelayVM $DST_RELAY_RG $DST_LOCATION $DST_RELAY_VM ...

    Invoke-Peering

    Get-RelayIPs

    Log "Installing nfs-common + rsync on UAE relay..."
    Src-Cmd "apt-get update -qq && apt-get install -y nfs-common rsync 2>&1 | tail -3"

    Log "Installing nfs-common + rsync on Germany relay..."
    Dst-Cmd "apt-get update -qq && apt-get install -y nfs-common rsync 2>&1 | tail -3"

    Invoke-Keys

    Log "=== Relay VMs ready. Run: .\anf-rsync-replicate.ps1 sync ==="
}

# =============================================================================
# ── KEYS — upload private key to UAE relay, authorize public key on Germany ──
# =============================================================================

function Invoke-Keys {
    az account set --subscription $SUBSCRIPTION | Out-Null

    # 1) Generate a key pair in /root/.ssh on UAE relay — run-command runs as root,
    #    so rsync (also run via run-command) will automatically find the key there.
    Log "Generating SSH key pair on UAE relay (as root)..."
    Src-Cmd "mkdir -p /root/.ssh && chmod 700 /root/.ssh && [ -f /root/.ssh/id_rsa ] || { ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_rsa; echo 'New key generated'; }; echo 'Key ready'"

    # 2) Read back the public key as a single-line base64 string
    #    az vm run-command invoke puts stdout inside value[0].message between [stdout] and [stderr] markers
    Log "Reading public key from UAE relay..."
    $pubRaw = az vm run-command invoke `
        --resource-group $SRC_RELAY_RG --name $SRC_RELAY_VM `
        --subscription $SUBSCRIPTION --command-id RunShellScript `
        --scripts "base64 -w0 /root/.ssh/id_rsa.pub" `
        --output json | ConvertFrom-Json
    $msgText = $pubRaw.value[0].message
    $pubB64  = (($msgText -split '\[stdout\]')[1] -split '\[stderr\]')[0].Trim()
    if (-not $pubB64) { Bail "Could not read public key from UAE relay" }
    Log "Public key captured (base64 length: $($pubB64.Length))"

    # 3) Authorize that key on Germany relay under azureuser, and grant passwordless sudo for rsync
    #    (rsync SSHs as azureuser@<germany-ip>, then elevates via --rsync-path 'sudo rsync')
    Log "Authorizing UAE relay public key on Germany relay + configuring sudoers for rsync..."
    $authScript = "set -e; mkdir -p /home/${DST_RELAY_ADMIN}/.ssh; chmod 700 /home/${DST_RELAY_ADMIN}/.ssh; echo '$pubB64' | base64 -d >> /home/${DST_RELAY_ADMIN}/.ssh/authorized_keys; sort -u /home/${DST_RELAY_ADMIN}/.ssh/authorized_keys -o /home/${DST_RELAY_ADMIN}/.ssh/authorized_keys; chmod 600 /home/${DST_RELAY_ADMIN}/.ssh/authorized_keys; chown -R ${DST_RELAY_ADMIN}:${DST_RELAY_ADMIN} /home/${DST_RELAY_ADMIN}/.ssh; echo '${DST_RELAY_ADMIN} ALL=(ALL) NOPASSWD: /usr/bin/rsync' > /etc/sudoers.d/rsync-nopasswd; chmod 440 /etc/sudoers.d/rsync-nopasswd; echo 'authorized_keys + sudoers updated OK'"
    Dst-Cmd $authScript

    Log "=== SSH key exchange complete ==="
}

# =============================================================================
# ── SYNC — rsync replication cycle ───────────────────────────────────────────
# =============================================================================

function Invoke-Sync {
    Log "=== Starting rsync replication cycle ==="
    az account set --subscription $SUBSCRIPTION | Out-Null
    Get-RelayIPs

    # ── Step 1: ANF snapshot on source ──────────────────────────────────────
    # Snapshot creation skipped — use existing snapshot name below
    $snapshotName = "dr-snap-20260411061727"   # <-- update if using a different snapshot
    Log "Using existing snapshot: $snapshotName"

    # ── Step 2: Mount source on UAE relay ────────────────────────────────────
    Log "Mounting UAE ANF volume on UAE relay..."
    Src-Cmd "mkdir -p $SRC_MOUNT_DIR; mountpoint -q $SRC_MOUNT_DIR && umount -lf $SRC_MOUNT_DIR || true; mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp ${SRC_ANF_MOUNT_IP}:/${SRC_ANF_VOLUME} $SRC_MOUNT_DIR && echo 'UAE source mounted OK'"

    # ── Step 3: Mount destination on Germany relay ───────────────────────────
    Log "Mounting Germany ANF volume on Germany relay..."
    # chmod 777 so rsync receiver (running as azureuser via SSH) can write into the NFS mount
    Dst-Cmd "mkdir -p $DST_MOUNT_DIR; mountpoint -q $DST_MOUNT_DIR && umount -lf $DST_MOUNT_DIR || true; mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp ${DST_ANF_MOUNT_IP}:/${DST_ANF_VOLUME} $DST_MOUNT_DIR && chmod 777 $DST_MOUNT_DIR && echo 'Germany destination mounted OK'"

    # ── Step 4: PARALLEL rsync from snapshot (consistent point-in-time) ─────
    # rsync itself is single-threaded (1 CPU + 1 TCP stream). To use the WAN
    # link fully we partition the tree by top-level entry and run N rsync
    # workers concurrently via 'xargs -P', then do one fast reconcile pass that
    # handles root-level files and --delete across the whole tree.
    Log "Starting PARALLEL rsync ($RSYNC_PARALLEL_JOBS jobs): UAE snapshot → Germany..."
    $snapshotPath = "${SRC_MOUNT_DIR}/.snapshot/${snapshotName}/"
    $dstPrivateIP = $script:DST_RELAY_PRIVATE_IP
    $dstDest      = "${DST_RELAY_ADMIN}@${dstPrivateIP}:${DST_MOUNT_DIR}/"

    # Note: --bwlimit is per-rsync-process, so divide the total budget by job count.
    $rsyncOpts = "-az --delete --exclude=.snapshot --stats"
    if ($RSYNC_BANDWIDTH_LIMIT -gt 0) {
        $perJobBw  = [math]::Max(1, [int]($RSYNC_BANDWIDTH_LIMIT / $RSYNC_PARALLEL_JOBS))
        $rsyncOpts += " --bwlimit=$perJobBw"
    }

    # Single-quoted here-string => no PowerShell interpolation; inject values via .Replace.
    $syncScript = @'
set -e
export RSYNC_RSH="ssh -i /root/.ssh/id_rsa -o StrictHostKeyChecking=no"
export RP="sudo rsync"
export OPTS="__OPTS__"
export DST_DEST="__DST_DEST__"
JOBS=__JOBS__
SNAP="__SNAP__"
LOG="__LOG__"
echo "[rsync] Started at $(date -u) — $JOBS parallel jobs" | tee "$LOG"
cd "$SNAP"
# One rsync per top-level entry, up to $JOBS at a time. Each dir job recurses
# and applies --delete within its own subtree.
find . -mindepth 1 -maxdepth 1 -print0 \
  | xargs -0 -P "$JOBS" -I{} sh -c 'rsync $OPTS --rsync-path "$RP" "$1" "$DST_DEST"' _ {} 2>&1 | tee -a "$LOG"
# Reconcile pass: catches root-level files and deletions that per-entry jobs
# can't see. Fast — data is already present, so only metadata/deletes move.
echo "[rsync] Reconcile pass (root files + deletions)..." | tee -a "$LOG"
rsync $OPTS --rsync-path "$RP" "$SNAP" "$DST_DEST" 2>&1 | tee -a "$LOG"
echo "[rsync] Completed at $(date -u)" | tee -a "$LOG"
'@
    $syncScript = $syncScript.
        Replace('__OPTS__',     $rsyncOpts).
        Replace('__DST_DEST__', $dstDest).
        Replace('__JOBS__',     "$RSYNC_PARALLEL_JOBS").
        Replace('__SNAP__',     $snapshotPath).
        Replace('__LOG__',      $RSYNC_LOG)

    Src-Cmd $syncScript
    Log "rsync completed"

    # ── Step 5: Validate file count ──────────────────────────────────────────
    Log "Validating..."
    Src-Cmd "find $snapshotPath -type f 2>/dev/null | wc -l"
    Dst-Cmd "find $DST_MOUNT_DIR/ -type f 2>/dev/null | wc -l"
    Log "Validation complete (check counts above)"

    # ── Step 6: Clean unmount ────────────────────────────────────────────────
    Log "Unmounting..."
    Src-Cmd "umount -lf $SRC_MOUNT_DIR && echo 'UAE unmounted'"
    Dst-Cmd "umount -lf $DST_MOUNT_DIR && echo 'Germany unmounted'"

    Log "=== Replication cycle complete — Snapshot: $snapshotName ==="
}

# =============================================================================
# ── CLEAN — force unmount on both relays ─────────────────────────────────────
# =============================================================================

function Invoke-Clean {
    Get-RelayIPs
    Log "Force unmounting on both relays..."
    Src-Cmd "umount -lf $SRC_MOUNT_DIR 2>/dev/null && echo 'UAE unmounted' || echo 'UAE already unmounted'"
    Dst-Cmd "umount -lf $DST_MOUNT_DIR 2>/dev/null && echo 'Germany unmounted' || echo 'Germany already unmounted'"
    Log "Clean done"
}

# =============================================================================
# ── ENTRYPOINT ────────────────────────────────────────────────────────────────
# =============================================================================

# Windows Task Scheduler example (every hour):
# Action: powershell.exe -NonInteractive -File "C:\path\anf-rsync-replicate.ps1" -Mode sync

switch ($Mode) {
    "init"    { Invoke-Init    }
    "sync"    { Invoke-Sync    }
    "clean"   { Invoke-Clean   }
    "peering" { Invoke-Peering }
    "keys"    { Invoke-Keys    }
    default {
        Write-Host "Usage: .\anf-rsync-replicate.ps1 -Mode [init|sync|clean|peering|keys]"
        Write-Host "  init    — install dependencies on relay VMs (one-time)"
        Write-Host "  peering — create global VNet peering + NSG rule (idempotent)"
        Write-Host "  keys    — upload private key to UAE relay + authorize public key on Germany relay"
        Write-Host "  sync    — run rsync replication cycle (schedule with Task Scheduler for RPO)"
        Write-Host "  clean   — force unmount volumes on both relay VMs"
        exit 1
    }
}
