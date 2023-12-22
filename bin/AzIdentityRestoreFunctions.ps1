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

function Restore-AzSingleIdentity($identity)
{
    Get-AzUserAssignedIdentity -ResourceGroupName $identity.ResourceGroupName -Name $identity.Name | Remove-AzUserAssignedIdentity
    $newUa = New-AzUserAssignedIdentity -ResourceGroupName $identity.ResourceGroupName -Name $identity.Name -Location $identity.Location
    return ConvertTo-IdentityModel -AzIdentity $newUa
}

function Restore-AzIdentityAssignments($Resource, $TempUaIdentityId)
{
    if ($Resource.identityType -match "UserAssigned")
    {
        $patchBody = [PSCustomObject]@{
            identity = [PSCustomObject]@{
                type = $Resource.identityType
                userAssignedIdentities = $Resource.userAssignedIdentities
            }
        }
    }
    else 
    {
        $patchBody = [PSCustomObject]@{
            identity = [PSCustomObject]@{
                type = $Resource.identityType
            }
        }
    }

    $apiVersions = Get-AzApiVersionsForProvider -ResourceProvider $Resource.resourceProvider -ResourceType $Resource.resourceType
    $path = $Resource.id + "?api-version=" + $apiVersions.latestOrDefault
    $toggleSystemAssigned = $False
    $tempUserAssigned = $False

    # Identity update will either be triggered by toggling the SA identity or 
    #   assigning/unassigning the temp UA identity
    if ($patchBody.identity.type -match "SystemAssigned")
    {
        $toggleSystemAssigned = $True
        $patchBody.identity.type = Remove-SystemAssignedIdentityType -IdentityType $patchBody.identity.type
    }
    else 
    {
        $tempUserAssigned = $True
        $patchBody.identity.userAssignedIdentities[$TempUaIdentityId] = [PSCustomObject]@{}
    }
    
    # For a resource, attempt a PATCH on the identities.
    $response = Invoke-AzRestMethod -Method PATCH -Path $path -Payload $(ConvertTo-Json $patchBody -Depth 3)

    if ($response.StatusCode -lt 300)
    {
        if ($toggleSystemAssigned)
        {
            $patchBody.identity.type = Add-SystemAssignedIdentityType -IdentityType $patchBody.identity.type
            $response = Invoke-AzRestMethod -Method PATCH -Path $path -Payload $(ConvertTo-Json $patchBody -Depth 3)
    
            return Get-AzSystemAssignedIdentity -Scope $Resource.id | ConvertTo-IdentityModel
        }
        elseif ($tempUserAssigned)
        {
            $patchBody.identity.userAssignedIdentities[$tempUaIdentityId] = $null
            $response = Invoke-AzRestMethod -Method PATCH -Path $path -Payload $(ConvertTo-Json $patchBody -Depth 3)
        }
    }
    elseif ($response.StatusCode -eq 405)
    {
        # TODO: Handle HttpMethodIsNotSupported
        # If that fails, do a GET on the resource, update the body, and PUT the update
    }
    else 
    {
        # TODO: Handle error behavior whoops
    }
}

function Restore-AzSingleFederatedCredentialIdentity([PsCustomObject] $FederatedIdentityCredential, [string] $BackupTenantId, [string] $RestoreTenantId)
{
    $modifiedIssuer =   $FederatedIdentityCredential.issuer -replace $BackupTenantId, $RestoreTenantId
    New-AzFederatedIdentityCredentials -IdentityName $FederatedIdentityCredential.identityName -Name $FederatedIdentityCredential.name -ResourceGroupName $FederatedIdentityCredential.resourceGroupName -Audience $FederatedIdentityCredential.audience -Issuer $modifiedIssuer -Subject $FederatedIdentityCredential.subject | Out-Null
}