<#
.SYNOPSIS
    Powershell module to assist in the migration of subscriptions between two AAD tenants.
    Includes tooling to backup identity and RBAC configuration then restore that configuration in the new tenant.
#>

Import-Module Az

. $PSScriptRoot\bin\AzFirstPartyAppsFunctions.ps1
. $PSScriptRoot\bin\AzIdentityBackupFunctions.ps1
. $PSScriptRoot\bin\AzIdentityRestoreFunctions.ps1
. $PSScriptRoot\bin\AzKeyVaultFunctions.ps1
. $PSScriptRoot\bin\AzKustoFunctions.ps1
. $PSScriptRoot\bin\AzRbacFunctions.ps1
. $PSScriptRoot\bin\AzRestMethodTools.ps1
. $PSScriptRoot\bin\AzSqlFunctions.ps1
. $PSScriptRoot\bin\CommonTools.ps1
. $PSScriptRoot\bin\DataStorage.ps1

function Backup-AzIdentityAndRbac(
    [Parameter(Mandatory=$true)][string] $Subscription,
    [Parameter(Mandatory=$true)][string] $TenantId,
    [Parameter(Mandatory=$false)][string] $LocalDataFolder,
    [Parameter(Mandatory=$false)][string] $AzStorageResourceGroup,
    [Parameter(Mandatory=$false)][string] $AzStorageAccountName,
    [switch]$Force
)
{
    Write-Progress "Getting user login context for subscription $Subscription and tenant $TenantId"
    $context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

    if (-Not (Test-SubscriptionOwnership -Subscription $context.Subscription.Id))
    {
        # TODO: Error behavior
        Write-Error "Logged-in user does not have owner permissions on the requested subscription. Exiting."
        return
    }

    Write-Progress "Backing up identity and authorization configuration for subscription $Subscription"

    # backup identities, resources, and FIC
    $identities = Get-AllIdentitiesAtSubscriptionScope -Subscription $Subscription
    $resources = Get-AllIdentityEnabledResources -Subscription $Subscription
    $fic = Get-FederatedIdentityCredentialsForUserAssignedIdentities -Identities $identities
    $firstPartyApps = Get-AzFirstPartyApps
    
    # backup role assignments and RBAC
    $servicePrincipalOids = $identities + $firstPartyApps | % { $_.objectId }
    $roleAssignments = Get-RoleAssignmentsForPrincipals -PrincipalIds $servicePrincipalOids -SubscriptionId $Subscription
    
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

    # backup Kusto configuration
    $kustoClusters = Get-AzKustoClusters

    # backup SQL configuration
    $sqlResources = Get-AzSqlResources

    if ($PSBoundParameters.ContainsKey("LocalDataFolder"))
    {
        $storageConfig = [StorageConfig]@{
            LocalFolderName = $LocalDataFolder
        }
    }
    if ($PSBoundParameters.ContainsKey("AzStorageResourceGroup") -and $PSBoundParameters.ContainsKey("AzStorageAccountName"))
    {
        $storageConfig = [StorageConfig]@{
            StorageAccountResourceGroup = $AzStorageResourceGroup
            StorageAccountName = $AzStorageAccountName
        }
    }

    if ($storageConfig)
    {
        $identities | Set-MigrationData -Config $storageConfig -Identifier "identities" -Force:$Force
        $resources | Set-MigrationData -Config $storageConfig -Identifier "resources" -Force:$Force
        $fic | Set-MigrationData -Config $storageConfig -Identifier "fics" -Force:$Force
        $firstPartyApps | Set-MigrationData -Config $storageConfig -Identifier "firstPartyApps" -Force:$Force
        $roleAssignments | Set-MigrationData -Config $storageConfig -Identifier "roleAssignments" -Force:$Force
        $roleDefinitions | Set-MigrationData -Config $storageConfig -Identifier "roleDefinitions" -Force:$Force
        $keyVaults | Set-MigrationData -Config $storageConfig -Identifier "keyVaults" -Force:$Force
        $kustoClusters | Set-MigrationData -Config $storageConfig -Identifier "kustoClusters" -Force:$Force
        $sqlResources | Set-MigrationData -Config $storageConfig -Identifier "sqlResources" -Force:$Force
        $TenantId | Set-MigrationData -Config $storageConfig - Identifier "backupTenantId" -Force:$Force 
    }

    return [PSCustomObject]@{
        Identities = $identities
        Resources = $resources
        Fics = $fic
        FirstPartyApps = $firstPartyApps
        RoleAssignments = $roleAssignments
        RoleDefinitions = $roleDefinitions
        KeyVaults = $keyVaults
        KustoClusters = $kustoClusters
        SqlResources = $sqlResources
        BackupTenantId = $TenantId
    }
}

function Restore-AzIdentityAndRbac(
    [string] $Subscription, 
    [string] $TenantId, 
    [Parameter(Mandatory=$false)][PsCustomObject[]] $BackupConfig,
    [Parameter(Mandatory=$false)][string] $LocalDataFolder,
    [Parameter(Mandatory=$false)][string] $AzStorageResourceGroup,
    [Parameter(Mandatory=$false)][string] $AzStorageAccountName
)
{
    Write-Progress "Getting user login context for subscription $Subscription and tenant $TenantId"
    $context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

    if (-Not (Test-SubscriptionOwnership -Subscription $context.Subscription.Id))
    {
        Write-Error "Logged-in user does not have owner permissions on the requested subscription. Exiting."
        return 
    }

    Write-Progress "Restoring identity and authorization configuration for subscription $Subscription"

    if ($PSBoundParameters.ContainsKey("LocalDataFolder"))
    {
        $storageConfig = [StorageConfig]@{
            LocalFolderName = $LocalDataFolder
        }
    }
    if ($PSBoundParameters.ContainsKey("AzStorageResourceGroup") -and $PSBoundParameters.ContainsKey("AzStorageAccountName"))
    {
        $storageConfig = [StorageConfig]@{
            StorageAccountResourceGroup = $AzStorageResourceGroup
            StorageAccountName = $AzStorageAccountName
        }
    }

    if ($PSBoundParameters.ContainsKey("BackupConfig"))
    {
        $Identities = $BackupConfig.Identities
        $Resources = $BackupConfig.Resources
        $Fics = $BackupConfig.Fics
        $FirstPartyApps = $BackupConfig.FirstPartyApps
        $RoleAssignments = $BackupConfig.RoleAssignments
        $RoleDefinitions = $BackupConfig.RoleDefinitions
        $KeyVaults = $BackupConfig.KeyVaults
        $KustoClusters = $BackupConfig.KustoClusters
        $SqlResources = $BackupConfig.SqlResources
        $BackupTenantId = $BackupConfig.BackupTenantId
    }
    elseif ($storageConfig)
    {
        $Identities = @(Get-MigrationData -Config $storageConfig -Identifier "identities")
        $Resources = @(Get-MigrationData -Config $storageConfig -Identifier "resources")
        $Fics = @(Get-MigrationData -Config $storageConfig -Identifier "fics")
        $FirstPartyApps = @(Get-MigrationData -Config $storageConfig -Identifier "firstPartyApps")
        $RoleAssignments = @(Get-MigrationData -Config $storageConfig -Identifier "roleAssignments")
        $RoleDefinitions = @(Get-MigrationData -Config $storageConfig -Identifier "roleDefinitions")
        $KeyVaults = @(Get-MigrationData -Config $storageConfig -Identifier "keyVaults")
        $KustoClusters = @(Get-MigrationData -Config $storageConfig -Identifier "kustoClusters")
        $SqlResources =  @(Get-MigrationData -Config $storageConfig -Identifier "sqlResources")
        $BackupTenantId = @(Get-MigrationData -Config $storageConfig -Identifier "backupTenantId")
    }
    else {
        Write-Error "At least one of '-BackupConfig', '-LocalDataFolder', or '-AzStorageResourceGroup' and '-AzStorageAccountName' must be provided."
        return $null
    }

    # Recreate custom role definitions
    Add-RoleDefinitions -NewScope "/subscriptions/$Subscription" -RoleDefinitions $roleDefinitions

    # Get 1P app mapping and restore Azure RBAC
    $firstPartyOidMap = Get-AzFirstPartyPrincipalIdMapping $FirstPartyApps
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $firstPartyOidMap

    # Reset keyvault to new tenantId and restore access policies for 1P apps
    Update-AzureKeyVaultTenantId -TenantId $TenantId -AllAkvs $KeyVaults
    Restore-AzureKeyVaultAccessPolicies -TenantId $TenantId -AllAkvs $KeyVaults -PrincipalIdMapping $firstPartyOidMap

    # TODO: Does Kusto need to be reset after a tenant migration or is it good to go?
    Restore-AzKustoPrincipalAssignments -KustoClusters $KustoClusters -PrincipalIdMapping $firstPartyOidMap

    # TODO: Restore SQL MI and 1PA  assignments

    # Create temp identity for UA-only resources
    $rgName = "TempWorkflowRg-" + [Guid]::NewGuid().ToString()
    $identityName = "TempWorkflowIdentity-" + [Guid]::NewGuid().ToString()
    $tempRg = New-AzResourceGroup -Name $rgName -Location "westus"
    $tempUaIdentity = New-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $identityName -Location "westus"

    $userAssignedAidMap = @{}
    $userAssignedOidMap = @{}
    $systemAssignedMap = @{}

    # Delete and recreate UA identities
    $userAssignedIdentities = $Identities | ? { $_.type -eq "Microsoft.ManagedIdentity/userAssignedIdentities" }

    for ($i=0; $i -lt $userAssignedIdentities.Count; $i++)
    {
        Write-Progress -Activity "Restoring user-assigned identities" -PercentComplete $((100.0 * $i) / $userAssignedIdentities.Count)
        $oldUa = $userAssignedIdentities[$i]
        $newUa = Restore-AzSingleIdentity -Identity $oldUa
        $userAssignedOidMap[$oldUa.objectId] = $newUa.objectId
        $userAssignedAidMap[$oldUa.clientId] = $newUa.clientId
    }

    Write-Progress -Activity "Restoring user-assigned identities" -Completed

    # Restore role assignments on UA identities
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $userAssignedOidMap

    # Restore local access policies for UA identities
    Restore-AzureKeyVaultAccessPolicies -TenantId $TenantId -AllAkvs $KeyVaults -PrincipalIdMapping $userAssignedOidMap
    Restore-AzKustoPrincipalAssignments -KustoClusters $KustoClusters -PrincipalIdMapping $userAssignedOidMap
    # TODO: Restore SQL 

    # Restore FIC on new UA objects
    for ($i=0; $i -lt $Fics.Count; $i++)
    {
        Write-Progress -Activity "Restoring FIC configuration for user-assigned identities" -PercentComplete $((100.0 * $i) / $Fics.Count)
        Restore-AzSingleFederatedCredentialIdentity -FederatedIdentityCredential $Fics[$i] -BackupTenantId $BackupTenantId -RestoreTenantId $TenantId
    }

    Write-Progress -Activity "Restoring FIC configuration for user-assigned identities" -Completed

    # Restore SA identities and UA identity assignments
    for ($i=0; $i -lt $Resources.Count; $i++)
    {
        Write-Progress -Activity "Restoring system-assigned identities, identity assignments" -PercentComplete $((100.0 * $i) / $Resources.Count)
        $oldSa = $Resources[$i]
        $newSa = Restore-AzIdentityAssignments -Resource $oldSa -TempUaIdentityId $tempUaIdentity.Id -UserAssignedOidMap $userAssignedOidMap -UserAssignedAidMap $userAssignedAidMap
        if ($_.identityType -match "SystemAssigned")
        {
            $systemAssignedMap[$oldSa.objectId] = $newSa.objectId
        }
    }

    Write-Progress -Activity "Restoring system-assigned identities, identity assignments" -Completed

    # Restore role assignments on SA identities
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $systemAssignedMap
    
    # Restore local access policies for SA identities
    Restore-AzureKeyVaultAccessPolicies -TenantId $TenantId -AllAkvs $KeyVaults -PrincipalIdMapping $systemAssignedMap
    Restore-AzKustoPrincipalAssignments -KustoClusters $KustoClusters -PrincipalIdMapping $systemAssignedMap
    # TODO: Restore SQL

    # Clean up temp UA identity
    Remove-AzUserAssignedIdentity -ResourceGroupName $tempUaIdentity.ResourceGroupName -Name $tempUaIdentity.Name
    Remove-AzResourceGroup -Name $tempRg.ResourceGroupName -Force
}

function Remove-MigrationData {
    param (
        [Parameter(Mandatory=$false)][string] $LocalDataFolder,
        [Parameter(Mandatory=$false)][string] $AzStorageResourceGroup,
        [Parameter(Mandatory=$false)][string] $AzStorageAccountName
    )
    if ($LocalDataFolder)
    {
        $storageConfig = [StorageConfig]@{
            LocalFolderName = $LocalDataFolder
        }
    }
    if ($AzStorageResourceGroup -and $AzStorageAccountName)
    {
        $storageConfig = [StorageConfig]@{
            StorageAccountResourceGroup = $AzStorageResourceGroup
            StorageAccountName = $AzStorageAccountName
        }
    }

    if ($storageConfig)
    {
        Remove-MigrationDataInternal -Config $storageConfig
    }
}

Export-ModuleMember -Function @("Backup-AzIdentityAndRbac"; "Restore-AzIdentityAndRbac"; "Remove-MigrationData")