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
            $folderName = "$($Config.LocalFolderName)/migrationData"

            if ($Force) {
                Write-Debug "Force was specified, deleting $folderName"
                Remove-Item -Recurse -Force $folderName
            } elseif (Test-Path -Path $folderName) {
                $message = "$folderName already exists, use -Force to overwrite existing data."
                Write-Error $message
                throw $message
            }

            if (-not (Test-Path $folderName)) {
                Write-Debug "$folderName does not exist, creating it."
                New-Item -Path $folderName -ItemType Directory -Force
            }
        }

        if ($Config.StorageContainer) {
            $message = "Writing to Azure Storage isn't supported yet."
            Write-Error $message
            throw $message
        }

        $objects = @()
    }
    
    process {
        $objects += $Data
    }
    
    end {
        if ($Config.LocalFolderName) {
            ConvertTo-Json $objects > "$($Config.LocalFolderName)/migrationData/$Identifier.json"
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
        $filePath = "$($Config.LocalFolderName)/migrationData/$Identifier.json"
        if (-not (Test-Path $filePath)) {
            $message = "$filePath does not exist."
            Write-Error $message
            throw $message
        }

        return Get-Content $filePath | ConvertFrom-Json 
    }

    if ($Config.StorageContainer) {
        $message = "Reading from Azure Storage isn't supported yet."
        Write-Error $message
        throw $message
    }
}