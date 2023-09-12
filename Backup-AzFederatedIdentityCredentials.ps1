<#
.SYNOPSIS
    Reads all federated identity credentials associated with user assigned identity and dumps to a file.
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
    [psobject[]]
    $Identities
)


function Get-FederatedIdentityCredentialsForUserAssignedIdentities 
{

    # Initialize an array to store the Federated Identity Credentials
    $federatedIdentityCredentials = @()

    foreach ($identity in $Identities) {
        if ($identity.type -eq "UserAssigned") {
            $federatedIdentityCredential = Get-AzFederatedIdentityCredentials -IdentityName  identity.name -ResourceGroupName identity.resourceGroupName -SubscriptionId $Subscription
            if ($federatedIdentityCredential) {
                $federatedIdentityCredentials += $federatedIdentityCredential
            }  
        }
    }

    return $federatedIdentityCredentials
}

$federatedIdentityCredentials = Get-FederatedIdentityCredentialsForUserAssignedIdentities

return $federatedIdentityCredentials