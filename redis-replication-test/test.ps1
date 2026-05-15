# ==========================
# VARIABLES (UPDATE THESE)
# ==========================
$SUBSCRIPTION_ID = "7d1e8453-2920-4f6d-9a6e-bc7005c10a22"
# $WORKSPACE_RESOURCE_ID = "<log-analytics-workspace-resource-id>"  # e.g. /subscriptions/.../Microsoft.OperationalInsights/workspaces/<name>

# ==========================
# LOGIN & CONTEXT
# ==========================
#az login
#az account set --subscription $SUBSCRIPTION_ID

# ==========================
# GET ALL LOCKS IN SUBSCRIPTION
# ==========================
$locks = az lock list --query "[].{name:name, id:id}" -o json | ConvertFrom-Json

# ==========================
# REMOVE ALL LOCKS
# ==========================
foreach ($lock in $locks) {
    Write-Host "Removing lock: $($lock.name)"
    az lock delete --ids $lock.id
}

Write-Host "✅ Completed: All locks removed from resources"

# ==========================
# REMOVE DIAGNOSTIC SETTINGS
# ==========================
$WORKSPACE_RESOURCE_ID = "<log-analytics-workspace-resource-id>"  # e.g. /subscriptions/.../Microsoft.OperationalInsights/workspaces/<name>

$resources = az resource list --query "[].id" -o tsv
foreach ($resource in $resources) {
    $diag_settings = az monitor diagnostic-settings list --resource $resource --query "[].name" -o tsv

    foreach ($diag in $diag_settings) {
        $workspace = az monitor diagnostic-settings show `
            --resource $resource `
            --name $diag `
            --query "workspaceId" -o tsv

        if ($workspace -eq $WORKSPACE_RESOURCE_ID) {
            Write-Host "Deleting diagnostic setting: $diag from $resource"
            az monitor diagnostic-settings delete `
                --resource $resource `
                --name $diag
        }
    }
}
