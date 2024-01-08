<#
.SYNOPSIS
    Functions to backup SQL local users/auth and restore post-migration

    From Shobit -- select cast(cast('73816E85-0D22-4F58-A306-C3E4EDBF9C96' as uniqueidentifier) as varbinary(16)) SID
#>

try {
    Import-Module SqlServer
}
catch {
    Write-Warning "SqlServer module not available, only Active Directory administrator information will be backed up.\nFor full functionality, first run 'Install-Module SqlServer'."
}

$ServerLoginsQuery = "select * from sys.server_principals where type = 'E' or type = 'X'"

$DatabaseUserQuery = @"
select CASE  
    WHEN CONVERT(VARCHAR(100), sid, 2) LIKE '%AADE' AND LEN(sid) = 18 
    THEN 'login-based user' 
    ELSE 'database-contained user' 
    END AS user_type, 
    * 
from sys.database_principals where type = 'E' or type = 'X'
"@

$RoleMembershipsQuery = @"
SELECT   users.[name]         AS username 
       , users.[principal_id] AS principal_id 
       , users.[type]         AS user_type 
       , roles.[name]         AS role_name 
       , role_members.role_principal_id 
       , roles.is_fixed_role 
FROM sys.database_principals users 
INNER JOIN sys.database_role_members role_members 
    ON users.principal_id = role_members.member_principal_id 
INNER JOIN sys.database_principals roles 
    ON role_members.role_principal_id = roles.principal_id 
WHERE users.[type] IN ('X', 'E')
"@

$GrantedPermissionsQuery = @"
SELECT 
       database_principals.name 
     , database_principals.principal_id 
     , database_principals.type_desc 
     , database_permissions.permission_name 
     , CASE 
        WHEN class = 0 THEN 'DATABASE' 
        WHEN class = 3 THEN 'SCHEMA: ' + SCHEMA_NAME(major_id) 
        WHEN class = 4 THEN 'Database Principal: ' + USER_NAME(major_id) 
        ELSE OBJECT_SCHEMA_NAME(database_permissions.major_id) + '.' + OBJECT_NAME(database_permissions.major_id) 
        END AS object_name 
     , columns.name                    AS column_name 
     , database_permissions.state_desc AS permission_type 
FROM sys.database_principals             AS database_principals 
INNER JOIN sys.database_permissions      AS database_permissions   
    ON database_principals.principal_id = database_permissions.grantee_principal_id 
LEFT JOIN sys.columns                    AS columns   
    ON database_permissions.major_id = columns.object_id  
    AND database_permissions.minor_id = columns.column_id 
WHERE database_principals.authentication_type_desc = 'EXTERNAL' 
ORDER BY database_principals.name
"@

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

function Restore-AzSqlRole(
    [Microsoft.Azure.Commands.Sql.Server.Model.AzureSqlServerModel] $SqlServer, 
    [string] $RoleName,
    [string] $ObjectId)
{
    $query = "ALTER ROLE [$RoleName] ADD MEMBER [$ObjectId]"
    Invoke-AzSqlCmd -SqlServer $SqlServer -Query $query
}

function Restore-AzSqlPermission(
    [Microsoft.Azure.Commands.Sql.Server.Model.AzureSqlServerModel] $SqlServer, 
    [string] $Permission,
    [string] $DbObject,
    [string] $ObjectId)
{
    $query = "GRANT $Permission ON [$DbObject] to [$ObjectId]"
    Invoke-AzSqlCmd -SqlServer $SqlServer -Query $query
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

    if (Get-Module -ListAvailable -Name SqlServer)
    {
        $userInput = Read-Host "Restoring SQL users, logins, roles, and permissions requires temporarily elevation to server administrator.`nWould you like to proceed? [Y] Yes  [N] No  [?] Help (default is ""N"")"

        while ($userInput -match "^\s*\?\s*$")
        {
            $userInput = Read-Host "In order to perform the operations necessary to restore external logins and users from Entra along with their roles/permissions,`nthe current logged-in user will be temporarily assigned as the server administrator.`nWould you like to proceed? [Y] Yes  [N] No  [?] Help (default is ""N"")"
        }

        $elevatedAdmin = $userInput -ieq "y"

        if ($elevatedAdmin)
        {
            $serverAdmin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.Name 
            # TODO: Make user the admin

            # TODO: Read SQL stuff

            # Reset to the previous server admin
            Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.Name -DisplayName $serverAdmin.DisplayName -ObjectId $serverAdmin.ObjectId | Out-Null
        }
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
        $elevatedAdmin = $false
        
        if (Get-Module -ListAvailable -Name SqlServer)
        {
            $userInput = Read-Host "Restoring SQL users, logins, roles, and permissions requires temporarily elevation to server administrator.`nWould you like to proceed? [Y] Yes  [N] No  [?] Help (default is ""N"")"

            while ($userInput -match "^\s*\?\s*$")
            {
                $userInput = Read-Host "In order to perform the operations necessary to restore external logins and users from Entra along with their roles/permissions,`nthe current logged-in user will be temporarily assigned as the server administrator.`nWould you like to proceed? [Y] Yes  [N] No  [?] Help (default is ""N"")"
            }

            $elevatedAdmin = $userInput -ieq "y"

            if ($elevatedAdmin)
            {
                $serverAdmin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.Name 
                # TODO: Make user the admin

                # TODO: Restore SQL stuff
            }
        }

        if ($SqlServers.AdminIdentities.Keys -contains $server.Id)
        {
            $adminIdentity = $SqlServers.AdminIdentities[$server.Id]
            if ($ClientIdMapping.Keys -contains $adminIdentity.AppId)
            {
                # Update the admin here
                Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.Name -DisplayName $adminIdentity.DisplayName -ObjectId $($ClientIdMapping[$adminIdentity.AppId]) | Out-Null
                
                # No need to reset the admin a second time below
                $elevatedAdmin = $false
            }
        }

        if ($elevatedAdmin)
        {
            # Reset to the previous server admin
            Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.Name -DisplayName $serverAdmin.DisplayName -ObjectId $serverAdmin.ObjectId | Out-Null
        }
    }
}