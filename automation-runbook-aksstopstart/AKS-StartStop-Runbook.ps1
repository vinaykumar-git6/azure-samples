<#
.DISCLAIMER
    MICROSOFT DISCLAIMER - PROOF OF CONCEPT (POC)

    THIS SCRIPT IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
    INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
    PARTICULAR PURPOSE, AND NONINFRINGEMENT. IN NO EVENT SHALL MICROSOFT CORPORATION
    BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF
    CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH THIS
    SCRIPT OR THE USE OR OTHER DEALINGS IN THIS SCRIPT.

    This script is a Proof of Concept (POC) and is NOT a supported Microsoft product
    or service. It is provided for demonstration and reference purposes only.

    IMPORTANT:
    - You MUST test and validate this script in a non-production/test environment
      before executing it against any production subscription or resources.
    - The customer assumes full responsibility for reviewing, testing, and validating
      this script prior to production use.
    - Microsoft is not responsible for any data loss, service disruption, or other
      issues that may result from the execution of this script.

.SYNOPSIS
    Start or Stop an AKS cluster via Azure Automation.
    Uses System Managed Identity for authentication.

.PARAMETER Action
    Start or Stop the AKS cluster.

.PARAMETER ClusterName
    Name of the AKS cluster.

.PARAMETER ResourceGroupName
    Resource group containing the AKS cluster.

.PARAMETER SubscriptionId
    Azure subscription ID.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Start", "Stop")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$ClusterName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId
)

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
