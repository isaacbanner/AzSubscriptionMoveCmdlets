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

function Get-AzApiVersionsForProvider ([string] $ResourceProvider, [string] $ResourceType)
{
    $providerResponse = Invoke-AzRestMethod -Path "/providers/$($ResourceProvider)?api-version=2023-07-01"
    $provider = ConvertFrom-Json $providerResponse.Content
    $resourceTypeDefinition = $provider.resourceTypes | ? { $ResourceType -eq $_.resourceType }

    return [PSCustomObject]@{
        apiVersions = $resourceTypeDefinition.apiVersions
        defaultApiVersion = $resourceTypeDefinition.defaultApiVersion
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