<#
.SYNOPSIS
    Powershell module to assist in the migration of subscriptions between two AAD tenants.
    Includes tooling to backup identity and RBAC configuration then restore that configuration in the new tenant.
#>

. $PSScriptRoot\CommonTools.ps1
. $PSScriptRoot\GetRbacData.ps1
. $PSScriptRoot\IdentityBackupFunctions.ps1
. $PSScriptRoot\dataStorage.ps1
. $PSScriptRoot\Restore-AzFederatedIdentityCredentials.ps1
. $PSScriptRoot\Restore-AzureKeyVaultAccessPolicies.ps1
. $PSScriptRoot\Restore-AzUserAssignedIdentities.ps1
. $PSScriptRoot\Test-SubscriptionOwnership.ps1

function Get-AllAzureKeyVaults () {
    $allAkvs = Get-AzKeyVault
    $resultAkvList = New-Object System.Collections.ArrayList
    # Write-Output "Start downloading Azure KeyVault information ..."

    foreach ($akv in $allAkvs) {
        $kv = Get-AzKeyVault -ResourceGroupName $akv.ResourceGroupName -VaultName $akv.VaultName
        $resultAkvList.Add($kv) | out-null
        # Write-Output ("Finished downloading {0} / {1}" -f $resultAkvList.Count, $allAkvs.Count)
    }

    return $resultAkvList
}

function Backup-AzIdentityAndRbac([string] $Subscription, [string] $TenantId)
{
    Write-Progress -Activity "Getting user login context for subscription $Subscription and tenant $TenantId"
    $context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

    if (-Not (Test-SubscriptionOwnership -Subscription $context.Subscription.Id))
    {
        # TODO: Error behavior
        Write-Error "Ahhhh!"
        return
    }

    # backup identities, resources, and FIC
    $identities = Get-AllIdentitiesAtSubscriptionScope -Subscription $Subscription
    $resources = Get-AllIdentityEnabledResources -Subscription $Subscription
    $fic = Get-FederatedIdentityCredentialsForUserAssignedIdentities -Identities $identities
    
    # backup role assignments and RBAC
    $identityPrincipalOids = $identities | % { $_.objectId }
    $roleAssignments = Get-RoleAssignmentsForPrincipals -PrincipalIds $identityPrincipalOids -SubscriptionId $Subscription
    
    if ($roleAssignments.Length -gt 0)
    {
        $roleDefinitionIds = $roleAssignments.RoleDefinitionId | Select-Object -Unique
        $roleDefinitions = Get-CustomRoleDefinitionsForRoleAssignments -roleDefinitionIds $roleDefinitionIds 
    }
    else 
    {
        $roleDefinitions = @()
    }

    # backup AKV configuration
    $keyVaults = Get-AllAzureKeyVaults

    return [PSCustomObject]@{
        Identities = $identities
        Resources = $resources
        Fics = $fic
        RoleAssignments = $roleAssignments
        RoleDefinitions = $roleDefinitions
        KeyVaults = $keyVaults
    }
}

function Restore-AzIdentityAndRbac(
    [string] $Subscription, 
    [string] $TenantId, 
    [PsCustomObject[]] $Identities, 
    [PsCustomObject[]] $Resources,
    [PsCustomObject[]] $Fics,
    [PsCustomObject[]] $RoleAssignments,
    [PsCustomObject[]] $RoleDefinitions,
    [PsCustomObject[]] $KeyVaults)
{
    $context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

    if (-Not (Test-SubscriptionOwnership -Subscription $context.Subscription.Id))
    {
        Write-Output "boo"
    }

    # Recreate custom role definitions
    Add-RoleDefinitions -NewScope /subscriptions/ff945b8d-441a-41ef-a9db-7bd5fcc99978 -RoleDefinitions $roleDefinitions

    # Create temp identity for UA-only resources
    $rgName = "TempWorkflowRg-" + [Guid]::NewGuid().ToString()
    $identityName = "TempWorkflowIdentity" + [Guid]::NewGuid().ToString()
    $tempRg = New-AzResourceGroup -Name $rgName -Location "westus"
    $tempUaIdentity = New-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $identityName -Location "westus"

    $userAssignedMap = @{}
    $systemAssignedMap = @{}

    # Delete and recreate UA identities
    $Identities | % {
        if ($_.type -eq "Microsoft.ManagedIdentity/userAssignedIdentities")
        {
            $newUa = Restore-AzSingleIdentity -Identity $_
            $userAssignedMap[$_.objectId] = $newUa.objectId
        }
    }

    # Restore role assignments on UA identities
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $userAssignedMap

    # Restore local access policies for UA identities
    # TODO: DO

    # Restore FIC on new UA objects
    $Fics | % {
        Restore-AzSingleFederatedCredentialIdentity -federatedIdentityCredential $_
    }

    # Restore SA identities and UA identity assignments
    $Resources | % {
        $newSa = Restore-AzIdentityAssignments -Resource $_ -TempUaIdentityId $tempUaIdentity.Id
        if ($_.identityType -match "SystemAssigned")
        {
            $systemAssignedMap[$_.objectId] = $newSa.objectId
        }
    }

    # Restore role assignments on SA identities
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $systemAssignedMap
    
    # Restore local access policies for SA identities
    # TODO: DO

    # Clean up temp UA identity
    Remove-AzUserAssignedIdentity -ResourceGroupName $tempUaIdentity.ResourceGroupName -Name $tempUaIdentity.Name
    Remove-AzResourceGroup -Name $tempRg.ResourceGroupName -Force
}

Export-ModuleMember -Function @("Backup-AzIdentityAndRbac"; "Restore-AzIdentityAndRbac")