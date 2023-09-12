<#
.SYNOPSIS
    Reads all identities and identity-enabled resources from a subscription and dumps to a file.
.PARAMETER Subscription
    The subscription to dump.
.PARAMETER TenantId
    The tenantId of the subscription.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Subscription,

    [Parameter(Mandatory=$True)]
    [string]
    $TenantId
)

$argIdentityQuery = 'Resources | where subscriptionId =~ "{0}" | where isnotempty(identity) | where identity.["type"] has "SystemAssigned" | project id'

Import-Module .\AzRestMethodTools

function Get-AllSystemAssignedIdentities ($Subscription)
{
    $query = $argIdentityQuery -f $Subscription
    $ArgIdentities = Search-AzGraph -Query $query
    return $ArgIdentities | % {Get-AzSystemAssignedIdentity -Scope $_.id} | % {ConvertTo-IdentityModel -AzIdentity $_}
}

$context = Get-UserContext -Subscription $Subscription -TenantId $TenantId 

$userAssigned = @(Get-AzUserAssignedIdentity -SubscriptionId $Subscription | % {ConvertTo-IdentityModel -AzIdentity $_})

$systemAssigned = @(Get-AllSystemAssignedIdentities -Subscription $Subscription)
$allIdentities = $systemAssigned + $userAssigned

return $allIdentities