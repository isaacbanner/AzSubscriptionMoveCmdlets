<#
.SYNOPSIS
    Functions to get 1P app registrations in a tenant and 
    build a mapping between oids post-migration.
#>

function Get-AzFirstPartyApps()
{
    Write-Progress -Activity "Reading all Microsoft application registrations." 
    $firstPartyApps = Get-AzADServicePrincipal -Filter "appOwnerOrganizationId eq f8cdef31-a31e-4b4a-93e4-5f571e91255a" -Count -ConsistencyLevel "eventual"
    
    return @($firstPartyApps | % {ConvertTo-FirstPartyAppModel -Az1PApp $_})
}

function Get-AzFirstPartyPrincipalIdMapping ([PsCustomObject[]] $FirstPartyApps)
{
    $PrincipalIdMapping = @{}

    for ($i=0; $i -lt $FirstPartyApps.Count; $i++)
    {
        Write-Progress -Activity "Reading all Microsoft application registrations."  -PercentComplete $($i * 100.0 / $FirstPartyApps.Count)
        if(-not $FirstPartyApps[$i].is1pApp)
        {
            Write-Error "Application $($FirstPartyApps[$i].Name) is not recognized as a Microsoft-owned application, skipping. Please verify your backup data has not been subject to tampering."
        }
        else {
            $app = Get-AzADServicePrincipal -ApplicationId $FirstPartyApps[$i].clientId

            if ($null -ne $app)
            {
                $PrincipalIdMapping[$FirstPartyApps[$i].objectId] = $app.id
            }
        }
    }

    return $PrincipalIdMapping
}
