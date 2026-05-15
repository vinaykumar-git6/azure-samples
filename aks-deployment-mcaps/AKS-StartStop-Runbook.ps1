<#
.SYNOPSIS
    Start or Stop AKS cluster aks-vk-with-cilium via Azure Automation.
    Uses System Managed Identity for authentication.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop")]
    [string]$Action
)

$ClusterName = "aks-vk-with-cilium"
$ResourceGroupName = "azure-vk-rg"
$SubscriptionId = "7d1e8453-2920-4f6d-9a6e-bc7005c10a22"

# Authenticate using Managed Identity
try {
    Connect-AzAccount -Identity | Out-Null
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Authenticated successfully via Managed Identity"
}
catch {
    Write-Error "Failed to authenticate: $_"
    throw
}

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Action: $Action | Cluster: $ClusterName | RG: $ResourceGroupName"

try {
    if ($Action -eq "Stop") {
        Write-Output "Stopping AKS cluster '$ClusterName'..."
        Stop-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Cluster '$ClusterName' stopped successfully."
    }
    elseif ($Action -eq "Start") {
        Write-Output "Starting AKS cluster '$ClusterName'..."
        Start-AzAksCluster -ResourceGroupName $ResourceGroupName -Name $ClusterName
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Cluster '$ClusterName' started successfully."
    }
}
catch {
    Write-Error "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Failed to $Action cluster: $_"
    throw
}
