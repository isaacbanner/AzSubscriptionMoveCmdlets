<#
.SYNOPSIS
    Tooling for backup/restore of keyvaults and their local access policies
#>

function Get-AllAzureKeyVaults () {
    $allAkvs = Get-AzKeyVault
    $resultAkvList = New-Object System.Collections.ArrayList

    Write-Progress -Activity "Backing up Azure Keyvault configuration"

    for ($i=0; $i -lt $allAkvs.Count; $i++) {
        Write-Progress -Activity "Backing up Azure Keyvault configuration" -PercentComplete $((100.0 * $i) / $allAkvs.Count)
        $kv = Get-AzKeyVault -ResourceGroupName $allAkvs[$i].ResourceGroupName -VaultName $allAkvs[$i].VaultName
        $resultAkvList.Add($kv) | out-null
    }

    return $resultAkvList
}


function Update-AzureKeyVaultTenantId ($TenantId, $AllAkvs) {
    Write-Progress -Activity "Resetting KeyVault to enable access policies" 

    for ($i=0; $i -lt $AllAkvs.Count; $i++) {
        Write-Progress -Activity "Resetting KeyVault to enable access policies" -PercentComplete $((100.0 * $i) / $AllAkvs.Count)
        $vault = Get-AzResource -ResourceId $AllAkvs[$i].ResourceId -ExpandProperties
        $vault.Properties.TenantId = $TenantId
        $vault.Properties.AccessPolicies = @()

        # Note: wipes all previous access policies on the KV from the old tenant
        Set-AzResource -ResourceId $vault.ResourceId -Properties $vault.Properties -Force | Out-Null
    }
}

function Restore-AzureKeyVaultAccessPolicies ($TenantId, $AllAkvs, $PrincipalIdMapping) {
    Write-Progress -Activity "Restoring KeyVault access policies" 
    $AllAkvs | % {Update-AkvAcessPolicy -tenantId $TenantId -akv $_ -PrincipalIdMapping $PrincipalIdMapping | Out-Null }
}

function Update-AkvAcessPolicy ($TenantId, $Akv, $PrincipalIdMapping) {
    # Appending accessPolicies resource type, operation kind (add) and API version to akv resource id
    $path = $Akv.ResourceId + "/accessPolicies/add?api-version=2022-07-01"
    $accessPolicies = @($Akv.AccessPolicies | ? {
        $PrincipalIdMapping.Keys -contains $_.ObjectId
    } | % {
        [PSCustomObject]@{
            objectId = $($PrincipalIdMapping[$_.ObjectId])
            tenantId = $TenantId
            permissions = [PSCustomObject]@{
                keys = $_.PermissionsToKeys
                secrets = $_.PermissionsToSecrets
                certificates = $_.PermissionsToCertificates
                storage = $_.PermissionsToStorage
            }
        }
    })

    $requestBody = [PSCustomObject]@{
        id = $Akv.ResourceId + "/accessPolicies"
        type = "Microsoft.KeyVault/vaults/accessPolicies"
        location = $Akv.Location
        properties = [PSCustomObject]@{
            accessPolicies = $accessPolicies
        }
    }

    Write-Progress -Activity "Updating access policies for $($Akv.VaultName)"
    Invoke-AzRestMethodWithRetry -Method PUT -Path $path -Payload $(ConvertTo-Json $requestBody -Depth 5) | Out-Null
}