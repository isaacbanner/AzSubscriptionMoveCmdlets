<#
.SYNOPSIS 
    Utility functions to fetch all kusto clusters, all databases within,
        and all principalassignments for both, along with restore commands
        for the same.
#>

function Get-AzKustoClusters()
{
    $armClusters = Get-AzResource -ResourceType Microsoft.Kusto/clusters

    @($armClusters | % {
        Write-Progress -Activity "Kusto: Get cluster PrincipalAssignments for $($_.Name)"
        # Grab the name and RG into locals so they're accessible in the next foreach
        $clusterName = $_.Name
        $clusterRgName = $_.ResourceGroupName
        $clusterPrincipalAssignments = Get-AzKustoClusterPrincipalAssignment -ClusterName $clusterName -ResourceGroupName $clusterRgName | ?{
            "App" -eq $_.PrincipalType
        } | % {
            [PSCustomObject]@{
                ClusterName = $clusterName
                PrincipalAssignmentName = $_.Name.Split("/")[-1]
                PrincipalId = $_.PrincipalId
                PrincipalType = $_.PrincipalType
                ResourceGroupName = $clusterRgName
                Role = $_.Role
            }
        }
        
        Write-Progress -Activity "Kusto: Get database PrincipalAssignments for $($_.Name)"

        # Can we just talk about how Az.Kusto doesn't return objects in a format that it can consume?
        #   We have to use Az.Resources to get the clusters because the Az.Kusto object doesn't expose
        #   a ResourceGroupName property, despite it being *required by every command*...
        #   The Get-AzKustoDatabase command returns objects which, when you call $_.Name, return 
        #   **both the cluster and the database name**, which is a format ***their own cmdlets can't consume.***
        #   So yeah, let's clobber the DB names into something that Az.Kusto actually recognizes as a parameter,
        #   and regret that this was packaged and released, publicly, with Microsoft's name on it.
        $databaseNames = @(Get-AzKustoDatabase -ClusterName $_.Name -ResourceGroupName $_.ResourceGroupName | % { $_.Name.Split("/")[-1]})
        $databasePrincipalAssignments = $databaseNames | % {
            # Oh yeah and we have to do it for principal assignment names too, clobber everything.
            $databaseName = $_
            @{ $_ = @(Get-AzKustoDatabasePrincipalAssignment -ClusterName $clusterName -ResourceGroupName $clusterRgName -DatabaseName $_ | ? {
                "App" -eq $_.PrincipalType
            } | % {
                [PSCustomObject]@{
                    ClusterName = $clusterName
                    DatabaseName = $databaseName
                    PrincipalAssignmentName = $_.Name.Split("/")[-1]
                    PrincipalId = $_.PrincipalId
                    PrincipalType = $_.PrincipalType
                    ResourceGroupName = $clusterRgName
                    Role = $_.Role
                }
            })
        }}
        
        Write-Progress -Activity "Kusto: Get database PrincipalAssignments for $($_.Name)" -Completed

        [PSCustomObject]@{
            ClusterName = $clusterName
            ResourceGroupName = $clusterRgName
            ClusterPrincipalAssignments = $clusterPrincipalAssignments
            DatabasePrincipalAssignments = $databasePrincipalAssignments
        }
    })

}

function Restore-AzKustoPrincipalAssignments(
    [PsCustomObject[]] $KustoClusters,
    [hashtable] $PrincipalIdMapping)
{
    $KustoClusters | % {
        Write-Progress -Activity "Kusto: Restore cluster PrincipalAssignments for $($_.Name)" 
        $newAssignments = @()

        $KustoClusters.ClusterPrincipalAssignments | ? {
            $PrincipalIdMapping.Keys -contains $_.PrincipalId 
        } | % {
            # Remove the old assignment and recreate for the new service principal object
            Remove-AzKustoClusterPrincipalAssignment -ClusterName $_.ClusterName -ResourceGroupName $_.ResourceGroupName -PrincipalAssignmentName $_.PrincipalAssignmentName
            $newAssignments += New-AzKustoClusterPrincipalAssignment -ClusterName $_.ClusterName -ResourceGroupName $_.ResourceGroupName -PrincipalAssignmentName $_.PrincipalAssignmentName -PrincipalId $PrincipalIdMapping[$_.PrincipalId] -PrincipalType $_.PrincipalType -Role $_.Role
        }

        Write-Progress -Activity "Kusto: Restore cluster PrincipalAssignments for $($_.Name)" -Completed

        for($i = 0; $i -lt $KustoClusters.DatabasePrincipalAssignments.Count; $i++)
        {
            Write-Progress -Activity "Kusto: Restore database PrincipalAssignments for $($_.Name)" -PercentComplete ($i * 100.0 / $KustoClusters.DatabasePrincipalAssignments.Count)

            $KustoClusters.DatabasePrincipalAssignments[$i] | ? {
                $PrincipalIdMapping.Keys -contains $_.PrincipalId
            } | % {
                Remove-AzKustoDatabasePrincipalAssignment -ClusterName $_.ClusterName -ResourceGroupName $_.ResourceGroupName -DatabaseName $_.DatabaseName -PrincipalAssignmentName $_.PrincipalAssignmentName
                $newAssignments += New-AzKustoDatabasePrincipalAssignment -ClusterName $_.ClusterName -ResourceGroupName $_.ResourceGroupName -DatabaseName $_.DatabaseName -PrincipalAssignmentName $_.PrincipalAssignmentName -PrincipalId $PrincipalIdMapping[$_.PrincipalId] -PrincipalType $_.PrincipalType -Role $_.Role
            }
        }

        Write-Progress -Activity "Kusto: Restore database PrincipalAssignments for $($_.Name)" -Completed
    }
}