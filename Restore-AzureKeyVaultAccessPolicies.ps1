function Restore-AllAzureKeyVaults ($allAkvs, $PrincipalIdMapping) {
    # $akvOutputFilePath = ".\akvInfo.json"
    # $allAkvs = (Get-Content $akvOutputFilePath -Raw) | ConvertFrom-Json

    Write-Output "Start restoring Azure KeyVault Access Policies ..."
    
    $count = 1
    foreach ($akv in $allAkvs) {
        Update-AkvAcessPolicy -akv $akv -PrincipalIdMapping $PrincipalIdMapping
        Write-Output ("Finished restoring Azure Key Vault Access Policy: {0} / {1}" -f $count, $allAkvs.Count)
        $count++
    }
}

function Update-AkvAcessPolicy ($akv, $PrincipalIdMapping) {
    # Appending accessPolicies resource type, operation kind (replace) and API version to akv resource id
    $path = $akv.ResourceId + "/accessPolicies/replace?api-version=2022-07-01"

    $requestBody = [PSCustomObject]@{
        id = $akv.ResourceId + "/accessPolicies"
        type = "Microsoft.KeyVault/vaults/accessPolicies"
        location = $akv.Location
        properties = [PSCustomObject]@{
            accessPolicies = New-Object System.Collections.ArrayList
        }
    }

    # $requestBody.properties.accessPolicies = New-Object System.Collections.ArrayList
    foreach ($accessPolicy in $akv.AccessPolicies) {
        
        $objId = $accessPolicy.ObjectId
        if ($PrincipalIdMapping.ContainsKey($objId)) {
            $newObjId = $PrincipalIdMapping[$objId];

            $requestBody.properties.accessPolicies.Add(
                [PSCustomObject]@{
                    tenantId = $accessPolicy.TenantId
                    objectId = $newObjId
                    permissions = [PSCustomObject]@{
                        keys = $accessPolicy.PermissionsToKeys
                        secrets = $accessPolicy.PermissionsToSecrets
                        certificates = $accessPolicy.PermissionsToCertificates
                        storage = $accessPolicy.PermissionsToStorage
                    }
                }
            ) | out-null
        }
    }

    Invoke-AzRestMethod -Method PUT -Path $path -Payload $(ConvertTo-Json $patchBody -Depth 5)
}

