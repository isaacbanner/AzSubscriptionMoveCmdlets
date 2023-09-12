<#
.SYNOPSIS
    Reads all federated identity credentials and recreates them.
.PARAMETER Subscription
    The subscription in which to restore identities.
.PARAMETER OldTenantId
    The old tenant id
.PARAMETER NewTenantId
    The new tenant id
.PARAMETER FederatedIdentityCredentials
    The  FIC to be restored.
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [string]
    $Subscription,

    [Parameter(Mandatory=$True)]
    [string]
    $OldTenantId,

    [Parameter(Mandatory=$True)]
    [string]
    $NewTenantId,

    [Parameter(Mandatory=$True)]
    [psobject[]]
    $FederatedIdentityCredentials
)

# Define regular expressions to match resource group name, and ua identity name
$resourceGroupPattern = "/resourceGroups/([^/]+)/"
$uaIdentityPattern = "/userAssignedIdentities/([^/]+)/"

function Restore-AzSingleFederatedCredentialIdentity($federatedIdentityCredential)
{
    if ($federatedIdentityCredential.id -match $resourceGroupPattern -and $federatedIdentityCredential.id -match $identityPattern) {
        $resourceGroupName = $Matches[1]
        $identityName = $Matches[2]
        $modifiedIssuer =   $federatedIdentityCredential.issuer -replace $OldTenantId, $NewTenantId
        return New-AzFederatedIdentityCredentials -IdentityName $identityName -Name $federatedIdentityCredential.name -ResourceGroupName $resourceGroupName -SubscriptionId $Subscription -Audience $federatedIdentityCredential.audience -Issuer $modifiedIssuer -Subject $federatedIdentityCredential.subject 
    } else {
        Write-Host "Not able to retrieve the UA Identity Name and Resource Group"
    }
    
}


$FederatedIdentityCredentials | % {
    Restore-AzSingleFederatedCredentialIdentity($_)
}