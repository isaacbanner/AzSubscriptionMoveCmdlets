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

$argQuery = 'Resources | where subscriptionId =~ "fa5fc227-a624-475e-b696-cdd604c735bc" | where isnotempty(identity) | where identity.["type"] !has "None" | project id, location, identity'

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

function Get-UserContext ($Subscription) {  
    $context = Get-AzContext

    if ($null -eq $context -or $Subscription -ne $context.Subscription.Id)
    {
        Connect-AzAccount -Subscription $Subscription
        $context = Get-AzContext
    }

    return $context
}

$context = Get-UserContext($Subscription)
$resources = Get-AllIdentityEnabledResources

return $resources