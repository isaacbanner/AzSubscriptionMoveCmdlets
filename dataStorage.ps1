class StorageConfig {
    [string]$fileName
    $storageAccount
}

function Set-MigrationData {
    [CmdletBinding()]
    param (
       [Parameter(Mandatory=$true)] 
       [StorageConfig]$config,
       [Parameter(Mandatory=$true)]
       [string]$identifier,
       [Parameter(ValueFromPipeline=$true)]
       [PSCustomObject]$data
    )
    
    begin {
        
    }
    
    process {
        
    }
    
    end {
        
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
    
    begin {
        
    }
    
    process {
        
    }
    
    end {
        
    }
}