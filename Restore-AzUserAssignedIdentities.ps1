<#
.SYNOPSIS
    Reads all identities and identity-enabled resources from a subscription and dumps to a file.
.PARAMETER Subscription
    The subscription in which to restore identities.
.PARAMETER TenantId
    The new tenantId in which to restore identities.
.PARAMETER identities
    The UA identities to be restored.
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
    $Identities
)

function Get-UserContext ($Subscription, $TenantId) {  
    $context = Get-AzContext

    if ($null -eq $context -or $Subscription -ne $context.Subscription.Id -or $TenantId -ne $context.TenantId)
    {
        Connect-AzAccount -Subscription $Subscription -TenantId $TenantId
        $context = Get-AzContext
    }

    return $context
}

function Restore-AzSingleIdentity($identity)
{
    Get-AzUserAssignedIdentity -ResourceGroupName $identity.ResourceGroupName -Name $identity.Name | Remove-AzUserAssignedIdentity
    return New-AzUserAssignedIdentity -ResourceGroupName $identity.ResourceGroupName -Name $identity.Name -Location $identity.Location
}

$context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

$Identities | % {
    Restore-AzSingleIdentity($_)
}