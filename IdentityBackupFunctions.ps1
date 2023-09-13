
$argResourceQuery = 'Resources | where subscriptionId =~ "{0}" | where isnotempty(identity) | where identity.["type"] !has "None"'
$argIdentityQuery = 'Resources | where subscriptionId =~ "{0}" | where isnotempty(identity) | where identity.["type"] has "SystemAssigned" | project id'

function Get-FederatedIdentityCredentialsForUserAssignedIdentities([PsCustomObject[]] $Identities)
{
    # Initialize an array to store the Federated Identity Credentials
    $federatedIdentityCredentials = @()

    foreach ($identity in $Identities) {
        if ($identity.type -eq "Microsoft.ManagedIdentity/userAssignedIdentities") {
            $federatedIdentityCredential = Get-AzFederatedIdentityCredentials -IdentityName $identity.name -ResourceGroupName $identity.resourceGroupName

            if ($federatedIdentityCredential) {
                $federatedIdentityCredentials += ConvertTo-FederatedIdentityCredentialModel -Identity $identity -Fic $federatedIdentityCredential
            }  
        }
    }

    return $federatedIdentityCredentials
}

function Get-AllSystemAssignedIdentitiesAtSubscriptionScope ([string] $Subscription)
{
    $query = $argIdentityQuery -f $Subscription
    $ArgIdentities = Search-AzGraph -Query $query
    return $ArgIdentities | % {Get-AzSystemAssignedIdentity -Scope $_.id} | % {ConvertTo-IdentityModel -AzIdentity $_}
}

function Get-AllIdentitiesAtSubscriptionScope ([string] $Subscription)
{
    $userAssigned = @(Get-AzUserAssignedIdentity -SubscriptionId $Subscription | % {ConvertTo-IdentityModel -AzIdentity $_})

    $systemAssigned = @(Get-AllSystemAssignedIdentitiesAtSubscriptionScope -Subscription $Subscription)
    $allIdentities = $systemAssigned + $userAssigned

    return $allIdentities
}

function Get-AllIdentityEnabledResources ([string] $Subscription)
{
    $query = $argResourceQuery -f $Subscription
    $ArgResources = Search-AzGraph -Query $query
    return $ArgResources | % {
        ConvertTo-ResourceModel $_
    }
}