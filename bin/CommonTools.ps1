<#
.SYNOPSIS
    PS Module with multiple utility functions
#>

function Split-ResourceProviderAndType([string] $providerNamespaceAndType)
{
    $firstWhack = $providerNamespaceAndType.IndexOf('/')
    $namespace = $providerNamespaceAndType.Substring(0, $firstWhack)
    $fullResourceType = $providerNamespaceAndType.Substring($firstWhack + 1)

    return @($namespace, $fullResourceType)
}

function Get-UserContext ([string] $Subscription, [string] $TenantId) {  
    $context = Get-AzContext

    if ($null -eq $context -or $Subscription -ne $context.Subscription.Id -or $TenantId -ne $context.Tenant)
    {
        Connect-AzAccount -Subscription $Subscription -TenantId $TenantId
        $context = Get-AzContext
    }

    return $context
}

function Test-SubscriptionOwnership ([string] $SubscriptionId)
{
    if (-not $SubscriptionId) {
        Write-Debug "No subscription specified, testing subscription for current Azure context"
        $SubscriptionId = (Get-UserContext).Subscription.Id
    }

    Write-Debug "Testing subscription ownership for $SubscriptionId"

    $ownerAssignments = (Get-AzRoleAssignment
        | Where-Object { $_.Scope -eq "/subscriptions/$SubscriptionId" }
        | Where-Object { $_.RoleDefinitionName -eq "Owner" }
        | Measure-Object).Count

    return $ownerAssignments -gt 0
}

function Get-AzApiVersionsForProvider ([string] $ResourceProvider, [string] $ResourceType)
{
    $providerResponse = Invoke-AzRestMethodWithRetry -Path "/providers/$($ResourceProvider)?api-version=2023-07-01"
    $provider = ConvertFrom-Json $providerResponse.Content
    $resourceTypeDefinition = $provider.resourceTypes | ? { $ResourceType -eq $_.resourceType }

    $defaultApiVersion = $resourceTypeDefinition.defaultApiVersion
    $releaseApiVersions = $resourceTypeDefinition.apiVersions | ? { -not ($_ -match "preview") }
    $previewApiVersions = $resourceTypeDefinition.apiVersions | ? { $_ -match "preview" }

    if ($null -eq $defaultApiVersion)
    {
        if ($releaseApiVersions.Count -gt 0)
        {
            $defaultApiVersion = $releaseApiVersions[0]
        }
        else 
        {
            $defaultApiVersion = $previewApiVersions[0]
        }
    }

    $latestOrDefault = if($releaseApiVersions.Count -gt 0) { $releaseApiVersions[0] } else { $defaultApiVersion }

    return [PSCustomObject]@{
        releaseApiVersions = $releaseApiVersions
        previewApiVersions = $previewApiVersions
        defaultApiVersion = $defaultApiVersion
        latestOrDefault = $latestOrDefault
    }
}

function Format-AzResourceDefinition(
    [Parameter(Mandatory=$false)][PsCustomObject] $Resource, 
    [Parameter(Mandatory=$false)][string] $ResourcePath,
    [Parameter(Mandatory=$false)][scriptblock] $FilterOperation)
{
    if ($PSBoundParameters.ContainsKey("ResourcePath"))
    {
        $response = Invoke-AzRestMethodWithRetry -Method GET -Path $ResourcePath
    }
    elseif ($PSBoundParameters.ContainsKey("Resource")) {
        $apiVersions = Get-AzApiVersionsForProvider -ResourceProvider $Resource.ResourceProvider -ResourceType $Resource.ResourceType
        $response = Invoke-AzRestMethodWithRetry -Method GET -ApiVersion $apiVersions.latestOrDefault -ResourceGroupName $resource.resourceGroupName -Name $resource.name -ResourceProviderName $resource.resourceProvider -ResourceType $resource.resourceType 
    }
    else
    {
        return $null
    }
    
    $resourceBody = $response.Content

    if ($PSBoundParameters.ContainsKey("FilterOperation"))
    {
        # FilterOperation should perform some caller-specified string manipulation
        # on the resource definition before parsing the JSON object
        $resourceBody = $FilterOperation.InvokeReturnAsIs($resourceBody)
    }
    
    return ConvertFrom-Json $resourceBody
}

function Get-AzResourceDefinition(
    [Parameter(Mandatory=$false)][PsCustomObject] $Resource, 
    [Parameter(Mandatory=$false)][string] $ResourcePath)
{
    if ($PSBoundParameters.ContainsKey("ResourcePath"))
    {
        return Format-AzResourceDefinition -ResourcePath $ResourcePath
    }
    elseif ($PSBoundParameters.ContainsKey("Resource")) {
        return Format-AzResourceDefinition -Resource $Resource
    }
    else
    {
        return $null
    }
}


function ConvertTo-Hashtable ([PsCustomObject] $PsObject)
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

function FilterHashTable([hashtable]$Hashtable,[string]$StringToFilter)
{
    $filteredHashtable = @{}

    foreach ($key in $Hashtable.Keys) {
        $value = $Hashtable[$key]

        if ($value -like "*$StringToFilter*") {
            $filteredHashtable[$key] = $value
        }
    }

    return $filteredHashtable
}

function ConvertTo-ResourceModel([Parameter(ValueFromPipeline=$true)] [PsCustomObject] $argResource, [string] $SubscriptionId)
{
    $resourceProvider, $resourceType = Split-ResourceProviderAndType $argResource.type
    $userAssignedIdentities = ConvertTo-Hashtable -PsObject $argResource.identity.userAssignedIdentities

    return [PSCustomObject]@{
        id = $argResource.id
        location = $argResource.location
        name = $argResource.name
        resourceProvider = $resourceProvider
        resourceType = $resourceType
        identityType = $argResource.identity.type
        objectId = $argResource.identity.principalId
        userAssignedIdentities = Filter-Hashtable -Hashtable $userAssignedIdentities -StringToFilter $SubscriptionId
        resourceGroupName = $argResource.resourceGroup
    }
}

function ConvertTo-IdentityModel([Parameter(ValueFromPipeline=$true)] [PsCustomObject] $AzIdentity)
{
    return [PSCustomObject]@{
        clientId = $AzIdentity.clientId
        id = $AzIdentity.id  # Azure ResourceId
        location = $AzIdentity.location
        name = $AzIdentity.name
        objectId = $AzIdentity.principalId
        resourceGroupName = $AzIdentity.resourceGroupName
        type = $AzIdentity.type # Azure ResourceType
    }
}

function ConvertTo-FederatedIdentityCredentialModel([PsCustomObject] $Identity, [PsCustomObject] $Fic)
{
    return [PSCustomObject]@{
        name = $Fic.name
        issuer = $Fic.issuer  
        subject = $Fic.subject
        audience = $Fic.audience
        id = $Fic.id
        identityName = $Identity.name
        resourceGroupName = $Identity.resourceGroupName
    }
}

function ConvertTo-FirstPartyAppModel([Parameter(ValueFromPipeline=$true)] [PsCustomObject] $Az1PApp)
{
    return [PsCustomObject]@{
        clientId = $Az1PApp.appId
        name = $Az1PApp.displayName
        objectId = $Az1PApp.id
        is1pApp = $Az1PApp.appOwnerOrganizationId -eq "f8cdef31-a31e-4b4a-93e4-5f571e91255a"
    }
}