
function Get-FederatedIdentityCredentialsForUserAssignedIdentities 
{
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$userAssignedIdentityIds
    )


    # Define regular expressions to match subscription ID, resource group name, and identity name
    $subscriptionPattern = "/subscriptions/([^/]+)/"
    $resourceGroupPattern = "/resourcegroups/([^/]+)/"
    $identityPattern = "/userassignedidentities/([^/]+)$"


    # Initialize an array to store the Federated Identity Credentials
    $federatedIdentityCredentials = @()

    foreach ($userAssignedIdentityId in $userAssignedIdentityIds) {
        if ($userAssignedIdentityId -match $subscriptionPattern -and $userAssignedIdentityId -match $resourceGroupPattern -and $userAssignedIdentityId -match $identityPattern) {
            $federatedIdentityCredential = Get-AzFederatedIdentityCredentials -IdentityName  $Matches[3] -ResourceGroupName $Matches[2] -SubscriptionId $Matches[1]
            if ($federatedIdentityCredential) {
                $federatedIdentityCredentials += $federatedIdentityCredential
            }  
        }
    }

    return $federatedIdentityCredentials
}
