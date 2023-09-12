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

$argQuery = 'Resources | where subscriptionId =~ "fa5fc227-a624-475e-b696-cdd604c735bc" | where isnotempty(identity) | where identity.["type"] !has "None" | project id, location, identity'

Import-Module .\AzRestMethodTools

function Convert-PsCustomObjectToHashtable ($PsObject)
{
    If ($null -ne $PsObject) 
    {
        return $PsObject.psobject.properties | % { $ht = @{} } { $ht[$_.Name] = $_.Value } { $ht }
    } 
    Else 
    {
        return @{}
    }
}

function Get-AllIdentityEnabledResources ($Subscription)
{
    $ArgResources = Search-AzGraph -Query $argQuery
    return $ArgResources | % {[PSCustomObject]@{
        id = $_.id
        location = $_.location
        type = $_.identity.type
        userAssignedIdentities = Convert-PsCustomObjectToHashtable($_.identity.userAssignedIdentities)
    }}
}

$context = Get-UserContext -Subscription $Subscription -TenantId $TenantId
$resources = Get-AllIdentityEnabledResources

return $resources