function Update-AzureKeyVaultTenantId ($TenantId, $AllAkvs) {
    # $akvOutputFilePath = ".\akvInfo.json"
    # $AllAkvs = (Get-Content $akvOutputFilePath -Raw) | ConvertFrom-Json

    Write-Output "Start updating Azure KeyVault TenantId ..."
    
    $count = 1
    foreach ($akv in $AllAkvs) {
        $vault = Get-AzResource -ResourceId $akv.ResourceId -ExpandProperties
        Set-AzResource -ResourceId $akv.ResourceId -Properties $vault.Properties -Force
        Write-Output ("Finished updating Azure Key Vault TenatId: {0} / {1}" -f $count, $allAkvs.Count)
        $count++
    }
}

function Restore-AzureKeyVaultAccessPolicies ($TenantId, $AllAkvs, $PrincipalIdMapping) {
    # $akvOutputFilePath = ".\akvInfo.json"
    # $AllAkvs = (Get-Content $akvOutputFilePath -Raw) | ConvertFrom-Json

    Write-Output "Start restoring Azure KeyVault Access Policies ..."
    
    $count = 1
    foreach ($akv in $AllAkvs) {
        Update-AkvAcessPolicy -tenantId $TenantId -akv $akv -PrincipalIdMapping $PrincipalIdMapping
        Write-Output ("Finished restoring Azure Key Vault Access Policy: {0} / {1}" -f $count, $allAkvs.Count)
        $count++
    }
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
            tenantId = $tenantId
            tenantName = $tenantId
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

    Invoke-AzRestMethod -Method PUT -Path $path -Payload $(ConvertTo-Json $requestBody -Depth 5)
}

# Update-AzureKeyVaultTenantId -TenantId "3d1e2be9-a10a-4a0c-8380-7ce190f98ed9"