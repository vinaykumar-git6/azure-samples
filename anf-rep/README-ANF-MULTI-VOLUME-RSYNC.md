# Scheduled Multi-Volume ANF Replication with rsync

This guide describes the recommended production approach for replicating any
number of Azure NetApp Files (ANF) NFS volumes from UAE North to Germany West
Central on a schedule.

The existing `anf-rsync-replicate.ps1` script demonstrates one volume pair.
The multi-volume design moves volume-specific values into configuration and
uses one coordinator to process every enabled pair.

## Architecture

```text
Azure Automation schedule
        |
        v
Extension-based Hybrid Runbook Worker on the UAE relay VM
        |
        v
Load volume-pairs.json
        |
        v
Acquire one global lock
        |
        v
For each enabled volume pair, sequentially:
  1. Create a fresh source snapshot
  2. Mount source and destination using unique paths
  3. Run parallel rsync workers over private SSH
  4. Run a final reconcile pass
  5. Validate the result
  6. Unmount in a finally block
        |
        v
Return an aggregate success or failure result
```

Use an extension-based Hybrid Runbook Worker instead of an Azure Automation
cloud sandbox. The worker has access to the private VNets, NFS endpoints, SSH
key, rsync, and local mount paths. Install it on the UAE relay VM or on a
dedicated automation VM in the same VNet.

## Incremental Behavior

The first rsync transfers all files. Later cycles compare the new source
snapshot with the existing destination and transfer only new or changed data.
Unchanged files are skipped.

Important: each scheduled cycle must create a new source snapshot. Reusing the
fixed snapshot currently configured in `anf-rsync-replicate.ps1` repeatedly
copies the same point-in-time view and does not include newer source changes.

The final rsync reconcile pass should use `--delete-delay` if the destination
must mirror source deletions. Omit deletion options if destination files must
never be automatically removed.

## Volume Configuration

Create `volume-pairs.json` beside the coordinator script:

```json
[
  {
    "name": "application",
    "enabled": true,
    "sourceResourceGroup": "anf-mashreq",
    "sourceAccount": "netapp-fs-uaenorth",
    "sourcePool": "fs-pool-demo",
    "sourceVolume": "fs-naapp-demo-vol",
    "sourceMountIp": "10.0.22.4",
    "destinationVolume": "demo-vol",
    "destinationMountIp": "10.0.251.4",
    "parallelJobs": 8,
    "bandwidthLimitKbps": 0
  },
  {
    "name": "documents",
    "enabled": true,
    "sourceResourceGroup": "anf-mashreq",
    "sourceAccount": "netapp-fs-uaenorth",
    "sourcePool": "fs-pool-demo",
    "sourceVolume": "documents-uae",
    "sourceMountIp": "10.0.22.4",
    "destinationVolume": "documents-germany",
    "destinationMountIp": "10.0.251.4",
    "parallelJobs": 4,
    "bandwidthLimitKbps": 0
  }
]
```

Add another object to replicate another volume. Set `enabled` to `false` to
temporarily exclude a pair without deleting its configuration.

The `name` value must be unique and should contain only letters, numbers, and
hyphens. It is used to build isolated resources such as:

```text
/mnt/anf-src-application
/mnt/anf-dst-application
/var/log/anf-rsync-application.log
dr-application-20260731120000
```

Do not store passwords, private keys, or other secrets in this JSON file.

## Coordinator Pattern

Refactor the current `Invoke-Sync` implementation into a function that handles
one configuration object. The outer coordinator then loops over all enabled
pairs:

```powershell
function Invoke-AllVolumeSyncs {
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationPath
    )

    $volumes = Get-Content -LiteralPath $ConfigurationPath -Raw |
        ConvertFrom-Json

    $failures = @()

    foreach ($volume in $volumes | Where-Object { $_.enabled }) {
        try {
            Invoke-VolumeSync -Volume $volume
        }
        catch {
            $failures += $volume.name
            Write-Error "[$($volume.name)] $($_.Exception.Message)"
        }
    }

    if ($failures.Count -gt 0) {
        throw "Replication failed for: $($failures -join ', ')"
    }
}
```

`Invoke-VolumeSync` should follow this lifecycle:

```powershell
function Invoke-VolumeSync {
    param([Parameter(Mandatory)]$Volume)

    $safeName = $Volume.name -replace '[^a-zA-Z0-9-]', '-'
    $sourceMount = "/mnt/anf-src-$safeName"
    $destinationMount = "/mnt/anf-dst-$safeName"
    $logFile = "/var/log/anf-rsync-$safeName.log"
    $snapshotName = "dr-$safeName-$(Get-Date -Format yyyyMMddHHmmss)"

    try {
        # 1. Create and wait for a fresh ANF snapshot.
        # 2. Mount the snapshot-bearing source volume read-only.
        # 3. Mount the destination volume read-write.
        # 4. Run the existing parallel rsync and reconcile logic.
        # 5. Validate rsync exit codes and expected results.
    }
    finally {
        # Always force-unmount both unique mount paths when mounted.
    }
}
```

Continue processing after an individual volume failure, but fail the overall
job at the end. This gives every volume an opportunity to replicate while still
making Azure Automation monitoring and alerts report a failed cycle.

## Processing Strategy

Process volume pairs sequentially at first. Each volume can still use the
existing top-level-directory parallelism inside rsync.

```text
application: 8 rsync workers, then complete
documents:   4 rsync workers, then complete
archive:     2 rsync workers, then complete
```

Running multiple volume pairs concurrently can overwhelm ANF throughput, relay
CPU, SSH connections, or cross-region bandwidth. Add volume-level concurrency
only after measuring those limits.

Remember that `--bwlimit` applies to each rsync process. Divide a total desired
bandwidth limit by `parallelJobs`, as the current script does.

## Prevent Overlapping Cycles

A new scheduled job must not start while the previous cycle is still running.
Hold one Linux `flock` for the complete coordinator execution:

```bash
flock -n /var/lock/anf-rsync.lock \
  /opt/anf/run-all-syncs.sh /opt/anf/volume-pairs.json
```

Exit without starting replication when the lock cannot be acquired. Do not
lock only the mount command; the lock must remain held until all volume pairs
finish.

Azure Automation job concurrency checks can provide an additional guard, but
the relay-side file lock is the authoritative protection for mounts and rsync.

## Snapshot Lifecycle

For every enabled source volume:

1. Create a uniquely named snapshot immediately before mounting.
2. Wait until Azure reports that snapshot creation succeeded.
3. Replicate from `.snapshot/<snapshot-name>/`, not the live write path.
4. Keep a small recovery window, such as the latest 24 to 72 hours.
5. Delete snapshots older than the configured retention period only after a
   successful cycle or through a separate cleanup job.

The Hybrid Worker VM managed identity should have only the permissions required
to read the relevant ANF resources and create, read, and delete their snapshots.
Avoid broad subscription-level roles.

## SSH and rsync

The UAE relay initiates SSH to the Germany relay over the peered private
network. Keep the private key only on the UAE relay. Install its public key in
`/home/azureuser/.ssh/authorized_keys` on the Germany relay.

For production:

- Store Germany's SSH host key in `/root/.ssh/known_hosts`.
- Remove `StrictHostKeyChecking=no`.
- Restrict the Germany NSG rule to the UAE relay subnet or IP.
- Restrict passwordless sudo to the required rsync command.
- Prefer a dedicated rsync service account and group permissions over
  `chmod 777` on the destination mount.

The per-volume transfer retains the current two-phase pattern:

1. Run parallel rsync workers for top-level entries.
2. Run one whole-tree reconcile pass for root files and deletions.

Check every rsync process exit code. A file-count comparison alone does not
detect different content or metadata.

## Azure Automation Setup

### Prerequisites

- An Azure Automation account with system-assigned managed identity enabled.
- An extension-based Hybrid Runbook Worker registered on the UAE relay or a
  dedicated VM with equivalent network access.
- PowerShell and the required Az modules installed for the selected runtime.
- `nfs-common`, `rsync`, `ssh`, and `flock` installed on the relay.
- Private connectivity between relays and from each relay to its ANF endpoint.
- The SSH key exchange completed using the existing `keys` mode.
- The runbook tested against non-production volumes before publication.

Do not use the retired agent-based Hybrid Runbook Worker.

### Authentication

At runbook startup, discard inherited contexts and use managed identity:

```powershell
Disable-AzContextAutosave -Scope Process
$context = (Connect-AzAccount -Identity).Context
$context = Set-AzContext -SubscriptionId '<YOUR-SUBSCRIPTION-ID>' `
    -DefaultProfile $context
```

Do not store Azure credentials in the runbook or volume configuration.

### Import and publish

Import the coordinator as a PowerShell runbook, test its draft on the Hybrid
Worker group, and publish it only after validation. Scheduled jobs execute the
published version.

### Create an hourly schedule

```powershell
$resourceGroup = "anf-mashreq"
$automationAccount = "anf-automation"
$runbookName = "Invoke-AnfReplication"
$scheduleName = "anf-replication-hourly"
$workerGroup = "anf-uae-workers"

New-AzAutomationSchedule `
    -ResourceGroupName $resourceGroup `
    -AutomationAccountName $automationAccount `
    -Name $scheduleName `
    -StartTime (Get-Date).AddHours(1) `
    -HourInterval 1 `
    -TimeZone "UTC"

Register-AzAutomationScheduledRunbook `
    -ResourceGroupName $resourceGroup `
    -AutomationAccountName $automationAccount `
    -RunbookName $runbookName `
    -ScheduleName $scheduleName `
    -RunOn $workerGroup `
    -Parameters @{
        ConfigurationPath = "/opt/anf/volume-pairs.json"
    }
```

Azure Automation recurring schedules have a minimum interval of one hour. For
a 15-minute RPO, use four hourly schedules staggered by 15 minutes or trigger
the runbook from a Logic App. Overlap protection remains mandatory.

## Validation

For every volume pair, record at least:

- Volume name and snapshot name.
- Start time, completion time, and duration.
- rsync exit code.
- Number of transferred files.
- Bytes transferred.
- Source and destination file counts.
- Validation result and error details.

For stronger assurance, periodically compare checksums on a sample or run a
maintenance-window verification using rsync checksum mode. Do not enable full
checksum comparison for every cycle without testing the CPU and NFS impact.

The Germany reader pod in `anf-germany-reader.yaml` is useful for a simple DR
read test, but it validates only the volume currently configured in that
manifest.

## Failure Handling

- Put mount cleanup in `finally` so failures do not leave stale mounts.
- Retry transient Azure control-plane operations with bounded retries and
  exponential backoff.
- Do not blindly retry permanent errors such as invalid configuration or NFS
  export-policy denial.
- Continue to the next volume after a pair fails.
- Throw an aggregate error after the loop if any pair failed.
- Alert on failed, stopped, or suspended Automation jobs.
- Never delete the last known-good snapshot as part of a failed cycle.

## Operational Checklist

Before enabling the schedule:

```text
[ ] Every source and destination volume already exists
[ ] Source and destination mappings have been reviewed
[ ] Export policies allow the relay VM subnets
[ ] VNet peering and NSG rules are connected and restricted
[ ] SSH authentication works using the private IP
[ ] SSH host-key verification is enabled
[ ] Hybrid Worker heartbeat is healthy
[ ] Managed identity has least-privilege ANF snapshot access
[ ] A fresh snapshot is created on every cycle
[ ] Global overlap lock has been tested
[ ] A failed volume does not prevent later volumes from running
[ ] Aggregate job failure and alerting have been tested
[ ] Snapshot retention and cleanup are configured
[ ] Initial full-copy duration fits the operational window
[ ] Incremental cycle duration fits the required RPO
```

## Recommended Repository Layout

```text
anf-rsync-replicate.ps1          Existing one-volume proof of concept
Invoke-AnfReplication.ps1       Azure Automation coordinator runbook
volume-pairs.json               Non-secret volume mapping configuration
README-ANF-MULTI-VOLUME-RSYNC.md
ANF-DR-SOP.md                    Existing end-to-end DR SOP
```

The coordinator and JSON files shown above describe the target implementation;
they are not yet present in this repository. The existing script must be
refactored before the multi-volume schedule is enabled.