# ==========================
# VARIABLES (UPDATE THESE)
# ==========================
SUBSCRIPTION_ID="7d1e8453-2920-4f6d-9a6e-bc7005c10a22"
# WORKSPACE_RESOURCE_ID="<log-analytics-workspace-resource-id>"  # e.g. /subscriptions/.../Microsoft.OperationalInsights/workspaces/<name>

# ==========================
# LOGIN & CONTEXT
# ==========================
az login
az account set --subscription $SUBSCRIPTION_ID

# ==========================
# GET ALL RESOURCES
# ==========================
resources=$(az resource list --query "[].id" -o tsv)

# ==========================
# REMOVE LOCKS FROM ALL RESOURCES
# ==========================
for resource in $resources
do
    locks=$(az lock list --resource-id $resource --query "[].name" -o tsv)

    for lock in $locks
    do
        echo "Removing lock: $lock on $resource"
        az lock delete --name $lock --resource-id $resource
    done

    # ==========================
    # DIAGNOSTIC SETTINGS (COMMENTED OUT)
    # ==========================
    # diag_settings=$(az monitor diagnostic-settings list --resource $resource --query "[].name" -o tsv)
    #
    # for diag in $diag_settings
    # do
    #     # Check if it's sending to the target workspace
    #     workspace=$(az monitor diagnostic-settings show \
    #         --resource $resource \
    #         --name $diag \
    #         --query "workspaceId" -o tsv)
    #
    #     if [ "$workspace" == "$WORKSPACE_RESOURCE_ID" ]; then
    #         echo "Deleting diagnostic setting: $diag from $resource"
    #         az monitor diagnostic-settings delete \
    #             --resource $resource \
    #             --name $diag
    #     fi
    # done

done

echo "✅ Completed: All locks removed from resources"