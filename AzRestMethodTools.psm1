<#
.SYNOPSIS
    PS Module with multiple Az Rest Method utilities
#>

function Get-UserContext ($Subscription, $TenantId) {  
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

function Get-AzResourceDefinition($Resource)
{
    $apiVersions = Get-AzApiVersionsForProvider -ResourceProvider $Resource.ResourceProvider -ResourceType $Resource.ResourceType
    $response = Invoke-AzRestMethod -Method GET -ApiVersion $apiVersions.defaultApiVersion -ResourceGroupName $resource.resourceGroupName -Name $resource.name -ResourceProviderName $resource.resourceProvider -ResourceType $resource.resourceType 

    return ConvertFrom-Json $response.Content
}