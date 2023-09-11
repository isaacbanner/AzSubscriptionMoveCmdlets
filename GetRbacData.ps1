function Get-RoleAssignmentsForPrincipals {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$PrincipalIds,
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId
    )

    Select-AzSubscription -Subscription $SubscriptionId
    $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" | Where-Object { $PrincipalIds -contains $_.ObjectId }
    return $roleAssignments
}

function Get-CustomRoleDefinitionsForRoleAssignments {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$roleDefinitionIds
    )

    $customRoleDefinitions = @()

    foreach ($roleDefinitionId in $roleDefinitionIds) {
        $roleDefinition = Get-AzRoleDefinition -Id $roleDefinitionId

        if ($roleDefinition.IsCustom) {
            $customRoleDefinitions += $roleDefinition
        }
    }

    return $customRoleDefinitions
}


<#

# Test case
$PrincipalIds = @('5c445532-1499-448e-970c-bda7db1e1f15');
$SubscriptionId = 'ff945b8d-441a-41ef-a9db-7bd5fcc99978';

Connect-AzAccount -Subscription $SubscriptionId

$RA = Get-RoleAssignmentsForPrincipals $PrincipalIds $SubscriptionId;


$roleDefinitionIds = $RA.RoleDefinitionId | Select-Object -Unique

Get-CustomRoleDefinitionsForRoleAssignments $roleDefinitionIds  

#>