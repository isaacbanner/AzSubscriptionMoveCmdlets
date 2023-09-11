<#
.SYNOPSIS
    Reads all identities and identity-enabled resources from a subscription and dumps to a file.
.PARAMETER Subscription
    The subscription to dump.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Subscription
)

function Get-UserContext ($Subscription) {  
    $context = Get-AzContext

    if ($null -eq $context -or $Subscription -ne $context.Subscription.Id)
    {
        Connect-AzAccount -Subscription $Subscription
        $context = Get-AzContext
    }

    return $context
}

function Get-AllSystemAssignedIdentities ($Subscription)
{
    $ArgIdentities = Search-AzGraph -Query 'Resources | where subscriptionId =~ "fa5fc227-a624-475e-b696-cdd604c735bc" | where isnotempty(identity) | where identity.["type"] has "SystemAssigned" | project id'
    return $ArgIdentities | % {Get-AzSystemAssignedIdentity -Scope $_.id}
}

$userAssigned = Get-AzUserAssignedIdentity -SubscriptionId $Subscription
$systemAssigned = Get-AllSystemAssignedIdentities($Subscription)
$allIdentities = $systemAssigned + $userAssigned

# TODO: current object format contains too much filler and property names are not aligned with downstream inputs

return $allIdentities