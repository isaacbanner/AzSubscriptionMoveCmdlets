Import-Module Az.KeyVault

function Restore-AllAzureKeyVaults () {
    $akvOutputFilePath = ".\akvInfo.json"

    Write-Output "Start restoring Azure KeyVault Access Policies ..."

    $allAkvs = (Get-Content $akvOutputFilePath -Raw) | ConvertFrom-Json
    $count = 0
    foreach ($akv in $allAkvs) {
        foreach ($ap in $akv.AccessPolicies) {
            Set-AzKeyVaultAccessPolicy 
                -ResourceGroupName $akv.ResourceGroupName 
                -VaultName $akv.VaultName 
                -ObjectId $ap.ObjectId
                -PermissionsToKeys $ap.PermissionsToKeys
                -PermissionsToSecrets $ap.PermissionsToSecrets
                -PermissionsToCertificates $ap.PermissionsToCertificates
                -PermissionsToStorage $ap.PermissionsToStorage
        }
        Write-Output ("Finished restoring Azure Key Vault Access Policy: {0} / {1}" -f $count, $allAkvs.Count)
        $count++
    }
}

Restore-AllAzureKeyVaults
