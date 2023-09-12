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

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Subscription,
    
    [Parameter(Mandatory=$True)]
    [string]
    $TenantId,

    [Parameter(Mandatory=$True)]
    [psobject[]]
    $Identities,

    [Parameter(Mandatory=$True)]
    [psobject[]]
    $Resources
)


Import-Module .\AzRestMethodTools

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
    # For a resource, attempt a PATCH on the identities.
    # If that fails, do a GET on the resource, update the body, and PUT the update

    $patchBody = [PSCustomObject]@{
        location = $Resource.location
        identity = [PSCustomObject]@{
            type = $Resource.identityType
            userAssignedIdentities = $Resource.userAssignedIdentities
        }
    }

    $apiVersions = Get-AzApiVersionsForProvider -ResourceProvider $Resource.resourceProvider -ResourceType $Resource.resourceType
    $path = $Resource.id + "?api-version=" + $apiVersions.defaultApiVersion
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
    
    $response = Invoke-AzRestMethod -Method PATCH -Path $path -Payload $(ConvertTo-Json $patchBody -Depth 3)

    if ($response.StatusCode -lt 300)
    {
        if ($toggleSystemAssigned)
        {
            $patchBody.identity.type = Add-SystemAssignedIdentityType -IdentityType $patchBody.identity.type
            $response = Invoke-AzRestMethod -Method PATCH -Path $path -Payload $(ConvertTo-Json $patchBody -Depth 3)
    
            $newSa = Get-AzSystemAssignedIdentity -Scope $Resource.id
            return ConvertTo-IdentityModel -AzIdentity $newSa
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
    }
    else 
    {
        # TODO: Handle error behavior whoops
    }
}

$context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

# Create temp identity for UA-only resources
$rgName = "TempWorkflowRg-" + [Guid]::NewGuid().ToString()
$identityName = "TempWorkflowIdentity" + [Guid]::NewGuid().ToString()
$tempRg = New-AzResourceGroup -Name $rgName -Location "westus"
$tempUaIdentity = New-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $identityName -Location "westus"

$userAssignedMap = @{}
$systemAssignedMap = @{}

$Identities | % {
    if ($_.type -eq "Microsoft.ManagedIdentity/userAssignedIdentities")
    {
        $newUa = Restore-AzSingleIdentity -Identity $_
        $userAssignedMap[$_.id] = $newUa
    }
}

# TODO: Redo role assignments and access policies for new UA identities

$Resources | % {
    $newSa = Restore-AzIdentityAssignments -Resource $_ -TempUaIdentityId $tempUaIdentity.Id
    if ($_.identityType -match "SystemAssigned")
    {
        $systemAssignedMap[$_.id] = $newSa
    }
}

# TODO: Redo role assignments and access policies for new SA identities

# Clean up temp UA identity
Remove-AzUserAssignedIdentity -ResourceGroupName $tempUaIdentity.ResourceGroupName -Name $tempUaIdentity.Name
Remove-AzResourceGroup -Name $tempRg.ResourceGroupName -Force

return [PSCustomObject]@{
    uaMap = $userAssignedMap
    saMap = $systemAssignedMap
}