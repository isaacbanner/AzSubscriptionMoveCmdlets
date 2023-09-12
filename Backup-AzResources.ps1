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

$argQuery = 'Resources | where subscriptionId =~ "{0}" | where isnotempty(identity) | where identity.["type"] !has "None"'

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

function Split-ResourceProviderAndType($providerNamespaceAndType)
{
    $firstWhack = $providerNamespaceAndType.IndexOf('/')
    $namespace = $providerNamespaceAndType.Substring(0, $firstWhack)
    $fullResourceType = $providerNamespaceAndType.Substring($firstWhack + 1)

    return @($namespace, $fullResourceType)
}

function Format-ArgResource($argResource)
{
    $resourceProvider, $resourceType = Split-ResourceProviderAndType $argResource.type

    return [PSCustomObject]@{
        id = $argResource.id
        location = $argResource.location
        name = $argResource.name
        resourceProvider = $resourceProvider
        resourceType = $resourceType
        identityType = $argResource.identity.type
        userAssignedIdentities = Convert-PsCustomObjectToHashtable -PsObject $argResource.identity.userAssignedIdentities
        resourceGroupName = $argResource.resourceGroup
    }
}

function Get-AllIdentityEnabledResources ($Subscription)
{
    $query = $argQuery -f $Subscription
    $ArgResources = Search-AzGraph -Query $query
    return $ArgResources 
}

$context = Get-UserContext -Subscription $Subscription -TenantId $TenantId
$resources = Get-AllIdentityEnabledResources -Subscription $Subscription

return $resources | % {
    Format-ArgResource $_
}