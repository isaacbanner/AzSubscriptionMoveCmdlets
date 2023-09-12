Import-Module Az.KeyVault

function Get-AllAzureKeyVaults () {
    
    $akvOutputFilePath = ".\akvInfo.json"
    $allAkvs = Get-AzKeyVault
    $resultAkvList = New-Object System.Collections.ArrayList
    Write-Output "Start downloading Azure KeyVault information ..."

    foreach ($akv in $allAkvs) {
        $kv = Get-AzKeyVault -ResourceGroupName $akv.ResourceGroupName -VaultName $akv.VaultName
        $resultAkvList.Add($kv) | out-null
        Write-Output ("Finished downloading {0} / {1}" -f $resultAkvList.Count, $allAkvs.Count)
    }

    # Save retrieved akv in a json file
    $resultAkvList | ConvertTo-Json -Depth 4 | Out-File -FilePath $akvOutputFilePath

    return $resultAkvList
}

# Connect-AzAccount -Subscription $SubscriptionId
Get-AllAzureKeyVaults