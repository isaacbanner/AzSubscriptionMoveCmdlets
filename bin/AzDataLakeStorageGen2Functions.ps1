<#
.SYNOPSIS
    Tooling for backup/restore of Data Lake Storage Gen2 local access policies
#>

function Get-DataLakeStorageGen2 () 
{
    # List all Storage Account in the current subscription
    $allStorageAccounts = Get-AzStorageAccount

    Write-Progress -Activity "Backing up Azure Data Lake Storage Gen2"

    $storageAccountResultMap = @{ }
    for ($i=0; $i -lt $allStorageAccounts.Count; $i++) 
    {        
        Write-Progress -Activity "Backing up Azure Data Lake Storage Gen2 configuration" -PercentComplete $((100.0 * $i) / $allStorageAccounts.Count)
        $storageAccount = $allStorageAccounts[$i]

        # Skip non data lake gen2 storage
        if (-Not $storageAccount.EnableHierarchicalNamespace)
        {
            continue;
        }

        $context = $storageAccount.Context
        $containerMap = @{ }
        # List all the containers under the storage accounts
        $allContainers = Get-AzStorageContainer -Context $Context
        for ($j=0; $j -lt $allContainers.Count; $j++) 
        {
            $container = $allContainers[$j]
            
            # List all files and sub-directories
            # TODO: consider batch the call to improve the performance
            # https://learn.microsoft.com/en-us/powershell/module/az.storage/get-azdatalakegen2childitem?view=azps-11.1.0#example-3-list-items-recursively-from-a-filesystem-in-multiple-batches
            $allFiles = Get-AzDataLakeGen2ChildItem -Context $context -FileSystem $container.Name -Recurse -FetchProperty
            $resultFileList = New-Object System.Collections.ArrayList
            for ($k=0; $k -lt $allFiles.Count; $k++) 
            {
                $fileOrDirectory = $allFiles[$k]
                $resultFileList.Add([PSCustomObject]@{
                    Path = $fileOrDirectory.Path
                    IsDirectory = $fileOrDirectory.IsDirectory
                    AccessControl = $fileOrDirectory.AccessControl
                }) | out-null
            }
            $containerMap.Add($container.name, $resultFileList) | out-null
        }
        $storageAccountResultMap.Add($storageAccount.StorageAccountName, $containerMap) | out-null
    }
    
    ConvertTo-Json $storageAccountResultMap -Depth 5 | Set-Content azureStorageAccountsDataLakeGen2.json
    return $storageAccountResultMap
}

function Restore-DataLakeStorageGen2Acl ($storageAccountResultMap)
{
    Write-Progress -Activity "Restoring Azure Data Lake Storage Gen2 access policies"

    # $storageAccountResultMap = get-content -raw -path ".\azureStorageAccountsDataLakeGen2.json" | Convertfrom-Json

    # Loop through each storage account
    foreach ($storageAccountProperties in $storageAccountResultMap.PsObject.Properties) 
    {
        $storageAccountName = $storageAccountProperties.Name
        $containers = $storageAccountProperties.Value
        $context = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount

        # Loop through each container
        foreach ($containerProperties in $containers.PsObject.Properties) 
        {
            $containerName = $containerProperties.Name
            $files = $containerProperties.Value

            # Loop through each file or directory
            foreach ($file in $files) 
            {
                $path = $file.Path
                
                # Update ACL only for managed identity SP
                foreach ($acl in $file.AccessControl.AccessControlList)
                {
                    $aclParts = $acl -split ":"
                    if ($aclParts[0] -eq "default")
                    {
                        # Default permission. For example: "default:user:043f621d-655c-436e-ad13-988698d962b5:rwx"
                        $isDefaultScope = $true
                        $oid = $aclParts[2]
                        $permissions = $aclParts[3]
                    } 
                    else 
                    {
                        # For example: "user:043f621d-655c-436e-ad13-988698d962b5:rwx"
                        $isDefaultScope = $false
                        $oid = $aclParts[1]
                        $permissions = $aclParts[2]
                    }
                    
                    # Skip non managed identity sp
                    if ($oid.Length -eq 0)
                    {
                        continue;
                    }
                    
                    if ($isDefaultScope)
                    {
                        $acl = Set-AzDataLakeGen2ItemAclObject -AccessControlType user -EntityId $oid -Permission $permissions -DefaultScope
                    }
                    else
                    {
                         $acl = Set-AzDataLakeGen2ItemAclObject -AccessControlType user -EntityId $oid -Permission $permissions
                    }
                    
                    Update-AzDataLakeGen2Item -Context $context -FileSystem $containerName -Path $path -Acl $acl
                }
            }
        }
    }
    #
}

# Get-DataLakeStorageGen2
# Restore-DataLakeStorageGen2Acl