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
    $Subscription,

    [Parameter(Mandatory=$True)]
    [string]
    $TenantId
)

$argIdentityQuery = 'Resources | where subscriptionId =~ "fa5fc227-a624-475e-b696-cdd604c735bc" | where isnotempty(identity) | where identity.["type"] has "SystemAssigned" | project id'

function Get-UserContext ($Subscription, $TenantId) {  
    $context = Get-AzContext

    if ($null -eq $context -or $Subscription -ne $context.Subscription.Id)
    {
        Connect-AzAccount -Subscription $Subscription -TenantId $TenantId
        $context = Get-AzContext
    }

    return $context
}

function Get-AllSystemAssignedIdentities ($Subscription)
{
    $ArgIdentities = Search-AzGraph -Query $argIdentityQuery
    return $ArgIdentities | % {Get-AzSystemAssignedIdentity -Scope $_.id}
}

$context = Get-UserContext -Subscription $Subscription -TenantId $TenantId 

$userAssigned = Get-AzUserAssignedIdentity -SubscriptionId $Subscription
$systemAssigned = Get-AllSystemAssignedIdentities -Subscription $Subscription
$allIdentities = $systemAssigned + $userAssigned

return $allIdentities | % {[PSCustomObject]@{
    clientId = $_.clientId
    id = $_.id  # Azure ResourceId
    location = $_.location
    name = $_.name
    objectId = $_.principalId
    resourceGroupName = $_.resourceGroupName
    type = $_.type
}}