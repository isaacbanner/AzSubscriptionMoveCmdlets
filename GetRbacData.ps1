function Get-RoleAssignmentsForPrincipals {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$PrincipalIds,
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId
    )

    $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" | Where-Object { $PrincipalIds -contains $_.ObjectId } | Where-Object { $_.Scope -contains "/subscriptions/$SubscriptionId"}
    
    return $roleAssignments;
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

function Add-RoleAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleAssignment[]]$RoleAssignments,
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$PrincipalIdMapping
    )

    foreach ($roleAssignment in $RoleAssignments) {
    $principalId = $roleAssignment.ObjectId;

    if ($PrincipalIdMapping.ContainsKey($principalId)) {
        $newPrincipalId = $PrincipalIdMapping[$principalId];
        
        Write-Output "Found mapping from PrincipalId:" $principalId " to principalId: " $newPrincipalId "Scope:" $roleAssignment.Scope; 

        $existingRA = Get-AzRoleAssignment -ObjectId $newPrincipalId -Scope $roleAssignment.Scope -RoleDefinitionName $roleAssignment.RoleDefinitionName;

        if ($existingRA.Count -eq 0)
        {
            Write-Output "Adding Role Assignment for Principal: " $newPrincipalId " Scope: " $roleAssignment.Scope ", RoleDefinitionName" $roleAssignment.RoleDefinitionName;
            New-AzRoleAssignment -ObjectId $newPrincipalId -RoleDefinitionName $roleAssignment.RoleDefinitionName -Scope $roleAssignment.Scope -Condition $roleAssignment.Condition -ConditionVersion $roleAssignment.ConditionVersion
        }
        else 
        {
            Write-Output "RA already exists for Principal: " $newPrincipalId " Scope: " $roleAssignment.Scope ", RoleDefinitionName" $roleAssignment.RoleDefinitionName;
        }
    }
}

}


function Add-RoleDefinitions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$NewScope,
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition[]]$RoleDefinitions
    )

    foreach ($item in $RoleDefinitions){

        Write-Output "ItemId : $($item.Id)";
        $existingRole = Get-AzRoleDefinition -Id $item.Id;
        
        <#
        # This code is still error prone. For Hackathon we will simplify the logic 
        $AssignableScope = $item.AssignableScopes | Where-Object { $_.StartsWith($NewScope) -or $_ -eq "/"};
        Write-Output "New Scope: " $AssignableScope;

        if ($AssignableScope -eq "/")
        {
            $AssignableScope = $NewScope;
        }
        #>

        # For simplicity, the new role definition should be created with subscription scope as Assignable Scope.
        $AssignableScope = $NewScope;

        if ($existingRole) 
        {
            if ($existingRole.Description -ne $item.Description -or 
                    $existingRole.Name -ne $item.Name -or 
                    (-Not (Compare-Arrays $existingRole.Actions $item.Actions)) -or 
                    (-Not (Compare-Arrays $existingRole.NotActions  $item.NotActions)) -or 
                    (-Not (Compare-Arrays $existingRole.DataActions $item.DataActions)) -or 
                    (-Not (Compare-Arrays $existingRole.NotDataActions $item.NotDataActions))) 
            {
               throw "Role Definition found with same Id but different properties in new tenant. Rbac Copy failed";
            }
            
            
            if (-Not $existingRole.AssignableScopes.Contains($AssignableScope) -and -Not $existingRole.AssignableScopes.Contains("/"))
            {
                $existingRole.AssignableScopes.Add($AssignableScope);
                Write-Output "Found role definition with same properties but missing assignable scope"
                New-AzRoleDefinition -InputObject $item
            }
            else
            {
                Write-Output "Found role definition with same properties and required assignable scope. Update will be skipped for $($item.Id)"
            }
        }
        else
        {
            $item.AssignableScopes.Clear();
            $item.AssignableScopes.Add($NewScope);
            
            New-AzRoleDefinition -InputObject $item
        }

    }
}

function Compare-Arrays($a1, $b1) {
    $c = Compare-Object -ReferenceObject $a1 -DifferenceObject $b1 -PassThru

    if ($c -eq $null) {
        return $true
    } else {
        return $false
    }
}

<#
# Test case
$PrincipalIds = @('4f6ef689-de83-4ace-b76a-b8471fe11185');
$SubscriptionId = 'ff945b8d-441a-41ef-a9db-7bd5fcc99978';

Connect-AzAccount -Subscription $SubscriptionId
Select-AzSubscription -Subscription $SubscriptionId;

$RA = Get-RoleAssignmentsForPrincipals $PrincipalIds $SubscriptionId;

$RA;

$roleDefinitionIds = $RA.RoleDefinitionId | Select-Object -Unique

$roleDefinitions = Get-CustomRoleDefinitionsForRoleAssignments $roleDefinitionIds  

$roleDefinitions

$principalIdMapping = @{
    "4f6ef689-de83-4ace-b76a-b8471fe11185" = "4f6ef689-de83-4ace-b76a-b8471fe11185"
}

Add-RoleDefinitions -NewScope /subscriptions/ff945b8d-441a-41ef-a9db-7bd5fcc99978 -RoleDefinitions $roleDefinitions;

#Update-RoleAssignments -RoleAssignments $RA -PrincipalIdMapping $principalIdMapping

#>