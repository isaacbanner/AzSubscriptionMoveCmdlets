<#
.SYNOPSIS
    Powershell module to assist in the migration of subscriptions between two AAD tenants.
    Includes tooling to backup identity and RBAC configuration then restore that configuration in the new tenant.
#>

. $PSScriptRoot\bin\AzFirstPartyAppsFunctions.ps1
. $PSScriptRoot\bin\AzIdentityBackupFunctions.ps1
. $PSScriptRoot\bin\AzIdentityRestoreFunctions.ps1
. $PSScriptRoot\bin\AzKeyVaultFunctions.ps1
. $PSScriptRoot\bin\AzKustoFunctions.ps1
. $PSScriptRoot\bin\AzRbacFunctions.ps1
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
    $kustoClusters = Get-AllKustoClusters

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
    $context = Get-UserContext -Subscription $Subscription -TenantId $TenantId

    if (-Not (Test-SubscriptionOwnership -Subscription $context.Subscription.Id))
    {
        Write-Output "boo"
        return $null
    }

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

    # Create temp identity for UA-only resources
    $rgName = "TempWorkflowRg-" + [Guid]::NewGuid().ToString()
    $identityName = "TempWorkflowIdentity-" + [Guid]::NewGuid().ToString()
    $tempRg = New-AzResourceGroup -Name $rgName -Location "westus"
    $tempUaIdentity = New-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $identityName -Location "westus"

    $userAssignedAidMap = @{}
    $userAssignedOidMap = @{}
    $systemAssignedMap = @{}

    # Delete and recreate UA identities
    $Identities | % {
        if ($_.type -eq "Microsoft.ManagedIdentity/userAssignedIdentities")
        {
            $newUa = Restore-AzSingleIdentity -Identity $_
            $userAssignedOidMap[$_.objectId] = $newUa.objectId
            $userAssignedAidMap[$_.clientId] = $newUa.clientId
        }
    }

    # Restore role assignments on UA identities
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $userAssignedOidMap

    # Restore local access policies for UA identities
    Restore-AzureKeyVaultAccessPolicies -TenantId $TenantId -AllAkvs $KeyVaults -PrincipalIdMapping $userAssignedOidMap

    # Restore FIC on new UA objects
    $Fics | % {
        Restore-AzSingleFederatedCredentialIdentity -FederatedIdentityCredential $_ -BackupTenantId $BackupTenantId -RestoreTenantId $TenantId
    }

    # Restore SA identities and UA identity assignments
    $Resources | % {
        $newSa = Restore-AzIdentityAssignments -Resource $_ -TempUaIdentityId $tempUaIdentity.Id -UserAssignedOidMap $userAssignedOidMap -UserAssignedAidMap $userAssignedAidMap
        if ($_.identityType -match "SystemAssigned")
        {
            $systemAssignedMap[$_.objectId] = $newSa.objectId
        }
    }

    # Restore role assignments on SA identities
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $systemAssignedMap
    
    # Restore local access policies for SA identities
    Restore-AzureKeyVaultAccessPolicies -TenantId $TenantId -AllAkvs $KeyVaults -PrincipalIdMapping $systemAssignedMap

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