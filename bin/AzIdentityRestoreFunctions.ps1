<#
.SYNOPSIS
    Reads all identities and identity-enabled resources from a subscription and dumps to a file.
.PARAMETER Subscription
    The subscription in which to restore identities.
.PARAMETER TenantId
    The new tenantId in which to restore identities.
.PARAMETER identities
    The UA identities to be restored.
.PARAMETER resources
    The resources in the subscription, potentially to which the identities are assigned.
#>

function Remove-SystemAssignedIdentityType([string] $IdentityType)
{
    if ($IdentityType -match "UserAssigned")
    {
        return "UserAssigned"
    }
    else 
    {
        return "None"
    }
} 

function Add-SystemAssignedIdentityType([string] $IdentityType)
{
    if ($IdentityType -match "UserAssigned")
    {
        return "SystemAssigned,UserAssigned"
    }
    else 
    {
        return "SystemAssigned"
    }
}

function Set-UpdatedIdentityIdsForResource (
    [string] $ResourceDefinition, 
    [Hashtable] $UserAssignedOidMap,
    [Hashtable] $UserAssignedAidMap)
{
    $UserAssignedOidMap.Keys | % {
        $ResourceDefinition = $ResourceDefinition.Replace($_, $UserAssignedOidMap[$_])
    }

    $UserAssignedAidMap.Keys | % {
        $ResourceDefinition = $ResourceDefinition.Replace($_, $UserAssignedAidMap[$_])
    }

    return $ResourceDefinition
}

function Restore-AzSingleIdentity([PsCustomObject] $identity)
{
    Get-AzUserAssignedIdentity -ResourceGroupName $identity.ResourceGroupName -Name $identity.Name | Remove-AzUserAssignedIdentity
    $newUa = New-AzUserAssignedIdentity -ResourceGroupName $identity.ResourceGroupName -Name $identity.Name -Location $identity.Location
    return ConvertTo-IdentityModel -AzIdentity $newUa
}

function Restore-AzIdentityAssignments(
    [PsCustomObject] $Resource, 
    [string] $TempUaIdentityId, 
    [Hashtable] $UserAssignedOidMap, 
    [Hashtable] $UserAssignedAidMap)
{
    # Start out by building a PATCH body and execute an optimistic update
    if ($Resource.identityType -match "UserAssigned")
    {
        $payloadResource = [PSCustomObject]@{
            identity = [PSCustomObject]@{
                type = $Resource.identityType
                userAssignedIdentities = $Resource.userAssignedIdentities
            }
        }
    }
    else 
    {
        $payloadResource = [PSCustomObject]@{
            identity = [PSCustomObject]@{
                type = $Resource.identityType
            }
        }
    }

    $apiVersions = Get-AzApiVersionsForProvider -ResourceProvider $Resource.resourceProvider -ResourceType $Resource.resourceType
    $path = $Resource.id + "?api-version=" + $apiVersions.latestOrDefault
    $toggleSystemAssigned = $False
    $tempUserAssigned = $False
    $httpMethod = "PATCH"

    # Identity update will either be triggered by toggling the SA identity or 
    #   assigning/unassigning the temp UA identity
    if ($payloadResource.identity.type -match "SystemAssigned")
    {
        $toggleSystemAssigned = $True
        $payloadResource.identity.type = Remove-SystemAssignedIdentityType -IdentityType $payloadResource.identity.type
    }
    else 
    {
        $tempUserAssigned = $True
        $payloadResource.identity.userAssignedIdentities[$TempUaIdentityId] = [PSCustomObject]@{}
    }
    
    # Attempt a PATCH on the identities, if the RP supports it
    $response = Invoke-AzRestMethod -Method $httpMethod -Path $path -Payload $(ConvertTo-Json $payloadResource -Depth 3)

    if ($response.StatusCode -eq 405)
    {
        # If PATCH fails with MethodNotAllowed, do a GET on the resource, 
        #   update identity on the full resource definition, and PUT the changes
        $payloadResource = Get-AzResourceDefinition -ResourcePath $path

        $httpMethod = "PUT"
        
        if ($Resource.identityType -match "UserAssigned")
        {
            # We need to wipe all the UA properties so that MIRP doesn't reject
            #   the stale objectIds in the resource definition
            $payloadResource.identity.userAssignedIdentities.PsObject.Properties | 
                % {$_.Value = [PSCustomObject]@{}}

            $payloadResource.identity.userAssignedIdentities[$TempUaIdentityId] = [PSCustomObject]@{}
        }
        else 
        {
            $payloadResource.identity.type = "None"
        }

        # We use the max depth here because I don't want to go breaking someone's resource
        $response = Invoke-AzRestMethod -Method $httpMethod -Path $path -Payload $(ConvertTo-Json $payloadResource -Depth 100)
    }

    # If either PUT or PATCH returned a 2xx response, return the new SA identity properties
    if ($response.StatusCode -lt 300)
    {
        if ($toggleSystemAssigned)
        {
            $payloadResource.identity.type = Add-SystemAssignedIdentityType -IdentityType $payloadResource.identity.type
            $response = Invoke-AzRestMethod -Method $httpMethod -Path $path -Payload $(ConvertTo-Json $payloadResource -Depth 3)
    
            return Get-AzSystemAssignedIdentity -Scope $Resource.id | ConvertTo-IdentityModel
        }
        elseif ($tempUserAssigned)
        {
            $payloadResource.identity.userAssignedIdentities[$tempUaIdentityId] = $null
            $response = Invoke-AzRestMethod -Method $httpMethod -Path $path -Payload $(ConvertTo-Json $payloadResource -Depth 3)
            return $null
        }
    }
    elseif ($response.StatusCode -eq 400)
    {
        # The most likely/reparable cause here is a RP with direct references to
        #   identity properties in the resource definition. 

        # $payloadResource = Format-AzResourceDefinition -ResourcePath $path -FilterOperation {Set-UpdatedIdentityIdsForResource -ResourceDefinition $args[0] -UserAssignedOidMap $UserAssignedOidMap -UserAssignedAidMap $UserAssignedAidMap}
        # TODO: Handle error behavior whoops
    }
    else {
        # TODO: What else could go wrong?
        # Should probably wrap all these Invoke-AzRestMethod calls in a retry handler
        #   for 5xx and other retry-able error codes
    }
}

function Restore-AzSingleFederatedCredentialIdentity(
    [PsCustomObject] $FederatedIdentityCredential, 
    [string] $BackupTenantId, 
    [string] $RestoreTenantId)
{
    $modifiedIssuer =   $FederatedIdentityCredential.issuer -replace $BackupTenantId, $RestoreTenantId
    New-AzFederatedIdentityCredentials -IdentityName $FederatedIdentityCredential.identityName -Name $FederatedIdentityCredential.name -ResourceGroupName $FederatedIdentityCredential.resourceGroupName -Audience $FederatedIdentityCredential.audience -Issuer $modifiedIssuer -Subject $FederatedIdentityCredential.subject | Out-Null
}