<#
.SYNOPSIS
    PS Module with multiple Az Rest Method utilities
#>

function Get-ApiVersionsForProvider ([string] $ResourceProvider, [string] $ResourceType)
{
    $providerResponse = Invoke-AzRestMethod -Path "/providers/$($ResourceProvider)?api-version=2023-07-01"
    $provider = ConvertFrom-Json $providerResponse.Content
    $resourceTypeDefinition = $provider.resourceTypes | Where-Object { $ResourceType -eq $_.resourceType }

    return [PSCustomObject]@{
        apiVersions = $resourceTypeDefinition.apiVersions
        defaultApiVersion = $resourceTypeDefinition.defaultApiVersion
    }
}

function Get-UserContext ($Subscription, $TenantId) {  
    $context = Get-AzContext

    if ($null -eq $context -or $Subscription -ne $context.Subscription.Id -or $TenantId -ne $context.Tenant)
    {
        Connect-AzAccount -Subscription $Subscription -TenantId $TenantId
        $context = Get-AzContext
    }

    return $context
}
