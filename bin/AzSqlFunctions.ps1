<#
.SYNOPSIS
    Functions to backup SQL local users/auth and restore post-migration
#>

try {
    Import-Module SqlServer
}
catch {
    Write-Warning "SqlServer module not available, only Active Directory administrator information will be backed up.\nFor full functionality, first run 'Install-Module SqlServer'."
}

function ConvertTo-AzSqlServer(
    [Parameter(ValueFromPipeline=$true)] [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResource] $ArmResource)
{
    if ("Microsoft.Sql/servers" -eq $ArmResource.ResourceType) 
    { 
        Get-AzSqlServer -ResourceGroupName $ArmResource.ResourceGroupName -ServerName $ArmResource.Name 
    }
    else {
        return $null
    }
}

function Invoke-AzSqlCmd(
    [Microsoft.Azure.Commands.Sql.Server.Model.AzureSqlServerModel] $SqlServer, 
    [string] $Query,
    [Parameter(Mandatory=$false)] $Database)
{
    $token = Get-AzAccessToken -ResourceUrl "https://database.windows.net"

    if ($PSBoundParameters.ContainsKey("Database"))
    {
        Invoke-Sqlcmd -ServerInstance $SqlServer.FullyQualifiedDomainName -Database $Database -AccessToken $token.Token -Query $Query
    }
    else {
        Invoke-Sqlcmd -ServerInstance $SqlServer.FullyQualifiedDomainName -AccessToken $token.Token -Query $Query
    }
}

function Get-AzSqlResources()
{
    Write-Progress -Activity "Backing up Azure SQL resources" -PercentComplete 0

    $sqlServers = Get-AzResource -ResourceType "Microsoft.SQL/servers"
    $serverAdmins = @{}

    for ($i=0; $i -lt $sqlServers.Count; $i++)
    {
        Write-Progress -Activity "Backing up Azure SQL resources" -PercentComplete $((100.0 * $i) / $sqlServers.Count)
        $server = $sqlServers[$i]
        $dbAdmin = Get-AzSqlServerActiveDirectoryAdministrator -ServerName $server.Name -ResourceGroupName $server.ResourceGroupName

        # Please don't ask me why SQL puts the MI appId in a field named ObjectId.
        $adminSpObject = Select-AzAdServicePrincipal -ApplicationId $dbAdmin.ObjectId
        if ("ManagedIdentity" -eq $adminSpObject.ServicePrincipalType -or 
            "f8cdef31-a31e-4b4a-93e4-5f571e91255a" -eq $adminSpObject.appOwnerOrganizationId)
        {
            # TODO: Trim down these objects
            $serverAdmins += @{$server.Id = $adminSpObject}
        }
    }

    Write-Progress -Activity "Backing up Azure SQL resources" -PercentComplete 100

    if (Get-Module -ListAvailable -Name SqlServer)
    {
        # TODO: SQL external users oh boy
    }

    [PSCustomObject]@{
        Servers = $sqlServers | % {$_ | ConvertTo-ResourceModel}
        AdminIdentities = $serverAdmins
    }
}

function Restore-AzSqlServerActiveDirectoryAdministrators(
    [PsCustomObject[]] $SqlServers,
    [hashtable] $ClientIdMapping)
{
    for ($i=0; $i -lt $SqlServers.Servers.Count; $i++)
    {
        Write-Progress -Activity "Restoring Azure SQL configuration" -PercentComplete $((100.0 * $i) / $SqlServers.Servers.Count)
        $server = $SqlServers.Servers[$i]

        if ($SqlServers.AdminIdentities.Keys -contains $server.Id)
        {
            $adminIdentity = $SqlServers.AdminIdentities[$server.Id]
            if ($ClientIdMapping.Keys -contains $adminIdentity.AppId)
            {
                Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.Name -DisplayName $adminIdentity.DisplayName -ObjectId $($ClientIdMapping[$adminIdentity.AppId]) | Out-Null
            }
        }

        Write-Progress -Activity "Restoring Azure SQL configuration" -PercentComplete 100
        
        if (Get-Module -ListAvailable -Name SqlServer)
        {
            # TODO: SQL external users oh boy
        }
    }
}