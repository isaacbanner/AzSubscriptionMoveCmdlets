. $PSScriptRoot\bin\AzKeyVaultFunctions.ps1

function Get-AllFirstPartyAppRoleAssignmentsAtTenantScope ([string] $TenantId)
{
    Write-Output "Getting all First Party Applications Role Assignments for Tenant $TenantId"
    Set-AzContext -Tenant $TenantId
    $firstPartyApps = Get-AzADServicePrincipal -Filter "appOwnerOrganizationId eq f8cdef31-a31e-4b4a-93e4-5f571e91255a" -Count -ConsistencyLevel "eventual"
    $firstPartyAppPrincipalOids = $firstPartyApps | % { $_.Id }
    $roleAssignments = @()
    for ($i = 0; $i -lt $firstPartyAppPrincipalOids.Count; $i++)
    {
        Write-Progress -Activity "Reading First Party assignment for Tenant $TenantId" -PercentComplete $(100.0 * $i / $firstPartyAppPrincipalOids.Count)
        $roleAssignment = Get-AzRoleAssignment -ObjectId $firstPartyAppPrincipalOids[$i]
        if($roleAssignment -ne $null)
        {
            $roleAssignments += $roleAssignment
        }
    }
    return [PSCustomObject]@{
        RoleAssignments = $roleAssignments
    }
}

function Restore-AllFirstPartyAppRoleAssignmentsAtTenantScope ([string] $TenantId, [PsCustomObject[]] $RoleAssignments)
{
    Write-Output "Getting all First Party Applications Role Assignments for Tenant $TenantId"
    Set-AzContext -Tenant $TenantId
    $firstPartyApps = Get-AzADServicePrincipal -Filter "appOwnerOrganizationId eq f8cdef31-a31e-4b4a-93e4-5f571e91255a" -Count -ConsistencyLevel "eventual"
    $PrincipalIdMapping = @{}

    for($i = 0; $i -lt $RoleAssignments.Count; $i++)
    {
        for( $j = 0; $j -lt $firstPartyApps.Count; $i++)
        {
            if($RoleAssignments[$i].DisplayName -eq $firstPartyApps[$j].DisplayName)
            {
                Write-Output "New Object Id is $firstPartyApps[$j].objectId for RoleAssignment $RoleAssignments[$i].ObjectId"
                $PrincipalIdMapping[$RoleAssignments[$i].objectId] = $firstPartyApps[$j].objectId
                break
            }
        }
    }

    # Restore role assignments on First Party App Prinicipals
    Add-RoleAssignments -RoleAssignments $RoleAssignments -PrincipalIdMapping $PrincipalIdMapping
    Write-Output "Completed Restoring RoleAssignments for First Part Applications"
}

function Restore-AllFirstPartyAppKVAccessPolicies ($TenantId, $AllAkvs)
{
    Write-Output "Getting all First Party Applications Role Assignments for Tenant $TenantId"
    Set-AzContext -Tenant $TenantId
    $firstPartyApps = Get-AzADServicePrincipal -Filter "appOwnerOrganizationId eq f8cdef31-a31e-4b4a-93e4-5f571e91255a" -Count -ConsistencyLevel "eventual"
    $PrincipalIdMapping = @{}
    $objectIds = @()

    foreach ($akv in $allAkvs) {
        $kv = Get-AzKeyVault -ResourceGroupName $akv.ResourceGroupName -VaultName $akv.VaultName
        # take all object ids for policies
        $objectIds = $kv.AccessPolicies | select -ExpandProperty ObjectId
    }

    for($i = 0; $i -lt $objectIds.Count; $i++)
    {
        for( $j = 0; $j -lt $firstPartyApps.Count; $i++)
        {
            if($objectIds[$i].ObjectId -eq $firstPartyApps[$j].DisplayName)
            {
                Write-Output "New Object Id is $firstPartyApps[$j].objectId for RoleAssignment $RoleAssignments[$i].ObjectId"
                $PrincipalIdMapping[$objectIds[$i].ObjectId] = $firstPartyApps[$j].objectId
                break
            }
        }
    }

    Write-Output "Start restoring Azure KeyVault Access Policies ..."
    $count = 1
    foreach ($akv in $AllAkvs) {
        Update-AkvAcessPolicy -tenantId $TenantId -akv $akv -PrincipalIdMapping $PrincipalIdMapping
        Write-Output ("Finished restoring Azure Key Vault Access Policy: {0} / {1}" -f $count, $allAkvs.Count)
        $count++
    }
}
