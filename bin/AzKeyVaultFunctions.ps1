<#
.SYNOPSIS
    Tooling for backup/restore of keyvaults and their local access policies
#>

function Get-AllAzureKeyVaults () {
    $allAkvs = Get-AzKeyVault
    $resultAkvList = New-Object System.Collections.ArrayList

    for ($i=0; $i -lt $allAkvs.Count; $i++) {
        Write-Progress -Activity "Backing up Azure Keyvault configuration" -PercentComplete $((100.0 * $i) / $allAkvs.Count)
        $kv = Get-AzKeyVault -ResourceGroupName $allAkvs[$i].ResourceGroupName -VaultName $allAkvs[$i].VaultName
        $resultAkvList.Add($kv) | out-null
    }

    Write-Progress -Activity "Backing up Azure Keyvault configuration" -Completed
    return $resultAkvList
}


function Update-AzureKeyVaultTenantId ($TenantId, $AllAkvs) {
    for ($i=0; $i -lt $AllAkvs.Count; $i++) {
        Write-Progress -Activity "Resetting KeyVault to enable access policies" -PercentComplete $((100.0 * $i) / $AllAkvs.Count)
        $vault = Get-AzResource -ResourceId $AllAkvs[$i].ResourceId -ExpandProperties
        $vault.Properties.TenantId = $TenantId
        $vault.Properties.AccessPolicies = @()

        # Note: wipes all previous access policies on the KV from the old tenant
        Set-AzResource -ResourceId $vault.ResourceId -Properties $vault.Properties -Force
    }

    Write-Progress -Activity "Resetting KeyVault to enable access policies" -Completed
}

function Restore-AzureKeyVaultAccessPolicies ($TenantId, $AllAkvs, $PrincipalIdMapping) {
    for ($i=0; $i -lt $AllAkvs.Count; $i++) {
        Write-Progress -Activity "Restoring KeyVault access policies" -PercentComplete $((100.0 * $i) / $AllAkvs.Count)
        Update-AkvAcessPolicy -tenantId $TenantId -akv $AllAkvs[$i] -PrincipalIdMapping $PrincipalIdMapping
    }

    Write-Progress -Activity "Restoring KeyVault access policies" -Completed
}

function Update-AkvAcessPolicy ($tenantId, $Akv, $PrincipalIdMapping) {
    # Appending accessPolicies resource type, operation kind (add) and API version to akv resource id
    $path = $Akv.ResourceId + "/accessPolicies/add?api-version=2022-07-01"

    $requestBody = [PSCustomObject]@{
        id = $Akv.ResourceId + "/accessPolicies"
        type = "Microsoft.KeyVault/vaults/accessPolicies"
        location = $Akv.Location
        properties = [PSCustomObject]@{
            accessPolicies = New-Object System.Collections.ArrayList
        }
    }

    # $requestBody.properties.accessPolicies = New-Object System.Collections.ArrayList
    foreach ($accessPolicy in $Akv.AccessPolicies) {
        
        $objId = $accessPolicy.ObjectId
        if ($PrincipalIdMapping.ContainsKey($objId)) {
            $newObjId = $PrincipalIdMapping[$objId];

            $requestBody.properties.accessPolicies.Add(
                [PSCustomObject]@{
                    objectId = $newObjId
                    tenantId = $tenantId
                    permissions = [PSCustomObject]@{
                        keys = $accessPolicy.PermissionsToKeys
                        secrets = $accessPolicy.PermissionsToSecrets
                        certificates = $accessPolicy.PermissionsToCertificates
                        storage = $accessPolicy.PermissionsToStorage
                    }
                }
            )
        }
    }

    Invoke-AzRestMethodWithRetry -Method PUT -Path $path -Payload $(ConvertTo-Json $requestBody -Depth 5)
}