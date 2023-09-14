<#
.SYNOPSIS
    PS Module with multiple Az Rest Method utilities
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
    $providerResponse = Invoke-AzRestMethod -Path "/providers/$($ResourceProvider)?api-version=2023-07-01"
    $provider = ConvertFrom-Json $providerResponse.Content
    $resourceTypeDefinition = $provider.resourceTypes | ? { $ResourceType -eq $_.resourceType }

    $defaultApiVersion = $resourceTypeDefinition.defaultApiVersion
    $releaseApiVersions = $resourceTypeDefinition.apiVersions | ? { -not ($_ -match "preview") }
    $previewApiVersions = $resourceTypeDefinition.apiVersions | ? { $_ -match "preview" }

    if ($null -eq $defaultApiVersion)
    {
        if ($releaseApiVersions.Count -gt 0)
        {
            $defaultApiVersion = $releaseApiVersions[-1]
        }
        else 
        {
            $defaultApiVersion = $previewApiVersions[-1]
        }
    }

    return [PSCustomObject]@{
        releaseApiVersions = $releaseApiVersions
        previewApiVersions = $previewApiVersions
        defaultApiVersion = $defaultApiVersion
    }
}

function Get-AzResourceDefinition([PsCustomObject] $Resource)
{
    $apiVersions = Get-AzApiVersionsForProvider -ResourceProvider $Resource.ResourceProvider -ResourceType $Resource.ResourceType
    $response = Invoke-AzRestMethod -Method GET -ApiVersion $apiVersions.defaultApiVersion -ResourceGroupName $resource.resourceGroupName -Name $resource.name -ResourceProviderName $resource.resourceProvider -ResourceType $resource.resourceType 

    return ConvertFrom-Json $response.Content
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

function ConvertTo-ResourceModel([Parameter(ValueFromPipeline=$true)] [PsCustomObject] $argResource)
{
    $resourceProvider, $resourceType = Split-ResourceProviderAndType $argResource.type

    return [PSCustomObject]@{
        id = $argResource.id
        location = $argResource.location
        name = $argResource.name
        resourceProvider = $resourceProvider
        resourceType = $resourceType
        identityType = $argResource.identity.type
        objectId = $argResource.identity.principalId
        userAssignedIdentities = ConvertTo-Hashtable -PsObject $argResource.identity.userAssignedIdentities
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