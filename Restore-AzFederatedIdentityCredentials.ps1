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


function Restore-AzSingleFederatedCredentialIdentity([PsCustomObject] $federatedIdentityCredential)
{
    $modifiedIssuer =   $federatedIdentityCredential.issuer -replace $OldTenantId, $NewTenantId
    New-AzFederatedIdentityCredentials -IdentityName $federatedIdentityCredential.identityName -Name $federatedIdentityCredential.name -ResourceGroupName $federatedIdentityCredential.resourceGroupName -Audience $federatedIdentityCredential.audience -Issuer $modifiedIssuer -Subject $federatedIdentityCredential.subject | Out-Null
}