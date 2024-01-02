function Get-RoleAssignmentsForPrincipals {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$PrincipalIds,
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId
    )
    Write-Progress -Activity "Reading role assignments for application principals"
    $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" | Where-Object { $PrincipalIds -contains $_.ObjectId } | Where-Object { $_.Scope -match "/subscriptions/$SubscriptionId"}

    return $roleAssignments;
}

function Get-CustomRoleDefinitionsForRoleAssignments {
    param (
        [Parameter(Mandatory=$true)]
        [AllowEmptyCollection()]
        [string[]]$roleDefinitionIds
    )
    $customRoleDefinitions = @()
    Write-Progress -Activity "Backing up custom roles"

    for ($i=0; $i -lt $roleDefinitionIds.Count; $i++) {
        Write-Progress -Activity "Backing up custom roles" -PercentComplete $((100.0 * $i) / $roleDefinitionIds.Count)
        $roleDefinition = Get-AzRoleDefinition -Id $roleDefinitionIds[$i]

        if ($roleDefinition.IsCustom) {
            $customRoleDefinitions += $roleDefinition
        }
    }

    Write-Progress -Activity "Backing up custom roles" -PercentComplete 100
    return $customRoleDefinitions
}

function Add-RoleAssignments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleAssignment[]]$RoleAssignments,
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$PrincipalIdMapping
    )
    Write-Progress -Activity "Restoring role assignments for application principals" 

    for ($i=0; $i -lt $RoleAssignments.Count; $i++) {
        Write-Progress -Activity "Restoring role assignments for application principals" -PercentComplete $((100.0 * $i) / $RoleAssignments.Count)
        
        $roleAssignment = $RoleAssignments[$i]
        $principalId = $roleAssignment.ObjectId;

        if ($PrincipalIdMapping.ContainsKey($principalId)) {
            $newPrincipalId = $PrincipalIdMapping[$principalId];
            
            Write-Debug "Found mapping from PrincipalId: $($principalId)  to principalId: $($newPrincipalId) Scope: $($roleAssignment.Scope)"; 

            $existingRA = Get-AzRoleAssignment -ObjectId $newPrincipalId -Scope $roleAssignment.Scope -RoleDefinitionName $roleAssignment.RoleDefinitionName;

            if ($existingRA.Count -eq 0)
            {
                Write-Debug "Adding Role Assignment for Principal: $($newPrincipalId), Scope: $($roleAssignment.Scope), RoleDefinitionName: $($roleAssignment.RoleDefinitionName)";

                if ($roleAssignment.Condition -and $roleAssignment.ConditionVersion)
                {
                    New-AzRoleAssignment -ObjectId $newPrincipalId -RoleDefinitionName $roleAssignment.RoleDefinitionName -Scope $roleAssignment.Scope -Condition $roleAssignment.Condition -ConditionVersion $roleAssignment.ConditionVersion -ObjectType $roleAssignment.ObjectType | Out-Null
                }
                else
                {
                    New-AzRoleAssignment -ObjectId $newPrincipalId -RoleDefinitionName $roleAssignment.RoleDefinitionName -Scope $roleAssignment.Scope -ObjectType $roleAssignment.ObjectType | Out-Null
                }
            }
            else 
            {
                Write-Debug "RA already exists for Principal: $($newPrincipalId), Scope: $($roleAssignment.Scope), RoleDefinitionName $($roleAssignment.RoleDefinitionName)";
            }
        }
    }

    Write-Progress -Activity "Restoring role assignments for application principals" -PercentComplete 100
}


function Add-RoleDefinitions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$NewScope,
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Resources.Models.Authorization.PSRoleDefinition[]]$RoleDefinitions
    )
    Write-Progress -Activity "Restoring custom role definitions"

    for ($i=0; $i -lt $RoleDefinitions.Count; $i++) {
        Write-Progress -Activity "Restoring custom role definitions" -PercentComplete $((100.0 * $i) / $RoleDefinitions.Count)

        $item = $RoleDefinitions[$i]
        $existingRole = Get-AzRoleDefinition -Name $item.Name;
        # Write-Output "Role definition ItemId : $($item.Id), Name: $($item.Name)";
        
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
            
            if (-Not $existingRole.AssignableScopes.Contains($AssignableScope) -and -Not $existingRole.AssignableScopes.Contains("/") -and -Not (Confirm-StringStartsWithX $existingRole.AssignableScopes $AssignableScope))
            {
                $existingRole.AssignableScopes.Add($AssignableScope);
                Write-Debug "Found role definition with same properties but missing assignable scope"
                New-AzRoleDefinition -Role $item | Out-Null
            }
            else
            {
                Write-Debug "Found role definition with same properties and required assignable scope. Update will be skipped for $($item.Id)"
            }
        }
        else
        {
            $item.AssignableScopes.Clear();
            $item.AssignableScopes.Add($NewScope);
            
            New-AzRoleDefinition -Role $item | Out-Null
        }
    }

    Write-Progress -Activity "Restoring custom role definitions" -PercentComplete 100
}

function Compare-Arrays($a1, $b1) {
    $c = Compare-Object -ReferenceObject $a1 -DifferenceObject $b1 -PassThru

    if ($null -eq $c) {
        return $true
    } else {
        return $false
    }
}

function Confirm-StringStartsWithX {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$stringArray,
        [Parameter(Mandatory=$true)]
        [string]$input
    )

    foreach ($string in $stringArray) {
        if ($string.StartsWith($input)) {
            return $true
        }
    }

    return $false
}