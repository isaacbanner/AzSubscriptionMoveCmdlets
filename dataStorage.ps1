class StorageConfig {
    [string]$FolderName
    $StorageContainer
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
        if ($null -ne $Config.FolderName) {
            if (-not (Test-Path $Config.FolderName)) {
                Write-Debug "$Config.FolderName does not exist, creating it."
                New-Item -Path $Config.FolderName -ItemType Directory -Force
            }

            if ($Force) {
                Write-Debug "Force was specified, deleting all files from $($Config.FolderName)"
                Get-ChildItem $Config.FolderName | Remove-Item
            }

            if ((Get-ChildItem $Config.FolderName | Measure-Object).Count -ne 0) {
                $message = "$($Config.FolderName) is not empty, use -Force to overwrite existing files."
                Write-Error $message
                throw $message
            }
        }

        if ($null -ne $Config.StorageContainer) {
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
        if ($null -ne $Config.FolderName) {
            ConvertTo-Json $objects > "$($Config.FolderName)/$Identifier.json"
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
    if ($null -ne $Config.FolderName) {
        $filePath = "$($Config.FolderName)/$Identifier.json"
        if (-not (Test-Path $filePath)) {
            $message = "$filePath does not exist."
            Write-Error $message
            throw $message
        }

        return Get-Content $filePath | ConvertFrom-Json 
    }

    if ($null -ne $Config.StorageContainer) {
        $message = "Reading from Azure Storage isn't supported yet."
        Write-Error $message
        throw $message
    }
}