class StorageConfig {
    [string]$LocalFolderName
    [string]$StorageAccountResourceGroup
    [string]$StorageAccountName
}

function Set-MigrationData {
    [CmdletBinding()]
    param (
       [Parameter(Mandatory=$true)] 
       [StorageConfig]$Config,
       [Parameter(Mandatory=$true)]
       [string]$Identifier,
       [Parameter(ValueFromPipeline=$true)]
       [PSCustomObject]$Data,
       [Parameter()]
       [switch]$Force
    )
    
    begin {
        Write-Debug "Writing migration data for $Identifier"
        if ($Config.LocalFolderName) {
            $folderName = "$($Config.LocalFolderName)\migrationData"

            if ((-not $Force) -and (Test-Path -Path "$folderName\$Identifier.json")) {
                $message = "$folderName\$Identifier.json already exists, use -Force to overwrite existing data."
                Write-Error $message
                throw $message
            }

            if (-not (Test-Path $folderName)) {
                Write-Debug "$folderName does not exist, creating it."
                New-Item -Path $folderName -ItemType Directory -Force | Out-Null
            }
        }

        if ($Config.StorageAccountName -and $Config.StorageAccountResourceGroup) {
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $Config.StorageAccountResourceGroup -Name $Config.StorageAccountName
            if (-not $storageAccount) {
                $message = "Storage account in $($Config.StorageAccountResourceGroup) with name $($Config.StorageAccountName) was not found"
                Write-Error $message
                throw $message
            }

            # ErrorAction=SilentlyContinue is needed to suppress error output when the container doesn't exist yet
            $storageContainer = Get-AzStorageContainer -Name "migrationdata" -Context $storageAccount.Context -ErrorAction SilentlyContinue
            if (-not $storageContainer) {
                Write-Debug "Migration data container does not exist, creating it."
                # Permission=Off to restrict access to only the container owner
                New-AzStorageContainer -Name "migrationdata" -Context $storageAccount.Context -Permission Off | Out-Null
            }
        }

        $objects = @()
    }
    
    process {
        $objects += $Data
    }
    
    end {
        if ($Config.LocalFolderName) {
            ConvertTo-Json $objects -Compress -Depth 10 > "$($Config.LocalFolderName)\migrationData\$Identifier.json"
        }

        if ($storageAccount) {
            try {
                $tempFile = New-TemporaryFile
                Write-Debug "Writing $Identifier data to $tempFile"
                ConvertTo-Json $objects -Compress -Depth 10 > $tempFile

                Write-Debug "Uploading $Identifier to migration data container"
                Set-AzStorageBlobContent -File $tempFile -Container "migrationdata" -Blob $Identifier -Context $storageAccount.Context -StandardBlobTier "Hot" -Force:$Force | Out-Null
            }
            finally {
                Write-Debug "Deleting $tempFile"
                Remove-Item $tempFile
            }
        }

        Write-Debug "Finished writing migration data for $Identifier"
    }
}

function Get-MigrationData {
    [CmdletBinding()]
    param (
       [Parameter(Mandatory=$true)] 
       [StorageConfig]$config,
       [Parameter(Mandatory=$true)]
       [string]$identifier
    )
    Write-Debug "Reading migration data for $Identifier"
    if ($Config.LocalFolderName) {
        $filePath = "$($Config.LocalFolderName)\migrationData\$Identifier.json"
        if (-not (Test-Path $filePath)) {
            $message = "$filePath does not exist."
            Write-Error $message
            throw $message
        }

        return Get-Content $filePath | ConvertFrom-Json 
    }

    if ($Config.StorageAccountName -and $Config.StorageAccountResourceGroup) {
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $Config.StorageAccountResourceGroup -Name $Config.StorageAccountName
        if (-not $storageAccount) {
            $message = "Storage account in $($Config.StorageAccountResourceGroup) with name $($Config.StorageAccountName) was not found"
            Write-Error $message
            throw $message
        }

        $storageContainer = Get-AzStorageContainer -Name "migrationdata" -Context $storageAccount.Context
        if (-not $storageContainer) {
            $message = "Migration data container not found in $($Config.StorageAccountName)"
            Write-Error $message
            throw $message
        }

        try {
            $tempFile = New-TemporaryFile
            Write-Debug "Downloading $Identifier data to $tempFile"
            Get-AzStorageBlobContent -Container "migrationdata" -Blob $Identifier -Context $storageAccount.Context -Destination $tempFile -Force | Out-Null
            
            Write-Debug "Finished downloading $Identifier data"
            return Get-Content $tempFile | ConvertFrom-Json
        }
        finally {
            Write-Debug "Deleting $tempFile"
            Remove-Item $tempFile
        }
    }
}

function Remove-MigrationDataInternal {
    [CmdletBinding()]
    param (
       [Parameter(Mandatory=$true)] 
       [StorageConfig]$Config
    )
    
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
    if ($Config.LocalFolderName)
    {
        $folderPath = "$($Config.LocalFolderName)\migrationData"
        $decision = $Host.UI.PromptForChoice(
            "Remove migration data",
            "Are you sure you want to remove all migration data from $($folderPath)?",
            $choices,
            0)
        if ($decision -ne 0)
        {
            return
        }

        if (Test-Path $folderPath)
        {
            Remove-Item -Recurse -Force $folderPath
        }
    }

    if ($Config.StorageAccountResourceGroup -and $Config.StorageAccountName)
    {
        $decision = $Host.UI.PromptForChoice(
            "Remove migration data",
            "Are you sure you want to remove all migration data from $($Config.StorageAccountName)?",
            $choices,
            0)
        if ($decision -ne 0)
        {
            return
        }

        $storageAccount = Get-AzStorageAccount -ResourceGroupName $Config.StorageAccountResourceGroup -Name $Config.StorageAccountName
        if (-not $storageAccount) {
            $message = "Storage account in $($Config.StorageAccountResourceGroup) with name $($Config.StorageAccountName) was not found"
            Write-Error $message
            throw $message
        }

        $storageContainer = Get-AzStorageContainer -Name "migrationdata" -Context $storageAccount.Context -ErrorAction SilentlyContinue
        if ($storageContainer)
        {
            Remove-AzStorageContainer -Name $storageContainer.Name -Context $storageAccount.Context
        }
    }
}