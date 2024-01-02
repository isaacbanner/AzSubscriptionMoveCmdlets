
$argResourceQuery = 'Resources | where subscriptionId =~ "{0}" | where isnotempty(identity) | where identity.["type"] !has "None"'
$argIdentityQuery = 'Resources | where subscriptionId =~ "{0}" | where isnotempty(identity) | where identity.["type"] has "SystemAssigned" | project id'

function Get-FederatedIdentityCredentialsForUserAssignedIdentities([PsCustomObject[]] $Identities)
{
    # Initialize an array to store the Federated Identity Credentials
    $federatedIdentityCredentials = @()

    for ($i=0; $i -lt $Identities.Count; $i++) {
        $identity = $Identities[$i]
        Write-Progress -Activity "Reading FIC configuration for user-assigned identities" -PercentComplete $(100.0 * $i / $Identities.Count)

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
    Write-Progress -Activity "Getting all resources with system-assigned identities in subscription $Subscription"
    $query = $argIdentityQuery -f $Subscription
    $argIdentities = Search-AzGraph -Query $query

    $identities = @()

    for ($i = 0; $i -lt $argIdentities.Count; $i++)
    {
        Write-Progress -Activity "Reading all system-assigned identities in subscription $Subscription" -PercentComplete $(100.0 * $i / $ArgIdentities.Count)
        $identities += $(Get-AzSystemAssignedIdentity -Scope $argIdentities[$i].id | ConvertTo-IdentityModel)
    }

    return $identities
}

function Get-AllIdentitiesAtSubscriptionScope ([string] $Subscription)
{
    Write-Progress -Activity "Reading all user-assigned identities in subscription $Subscription" 
    $userAssigned = @(Get-AzUserAssignedIdentity -SubscriptionId $Subscription | % {ConvertTo-IdentityModel -AzIdentity $_})

    $systemAssigned = @(Get-AllSystemAssignedIdentitiesAtSubscriptionScope -Subscription $Subscription)
    $allIdentities = $systemAssigned + $userAssigned

    return $allIdentities
}

function Get-AllIdentityEnabledResources ([string] $Subscription)
{
    Write-Progress -Activity "Reading all identity enabled resources and assignments in subscription $Subscription"
    $query = $argResourceQuery -f $Subscription
    $ArgResources = Search-AzGraph -Query $query

    return $ArgResources | % {
        ConvertTo-ResourceModel $_
    }
}