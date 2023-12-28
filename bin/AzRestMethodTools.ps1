<#
.SYNOPSIS
    PS Module with http utilities
#>

Invoke-AzRestMethodWithRetry(
    [string] $Path,
    [string] $Method,
    [Parameter(Mandatory=$false)][string] $Payload,
    [int] $Retries = 2)
{
    for ($i=0; $i -le $Retries; $i++)
    {
        $response = Invoke-AzRestMethod -Path $Path -Method $Method -Payload $Payload

        if ($response.StatusCode -eq 429)
        {
            # Client throttling
            $retryAfterSpan = $response.Headers.RetryAfter.Delta
            if ($retryAfterSpan.HasValue)
            {
                $waitTime = $retryAfterSpan.Value.TotalSeconds
            }
            else {
                $waitTime = 5
            }

            Write-Progress -Activity "Received throttling response from Azure, waiting..." -SecondsRemaining $waitTime
            Start-Sleep -Seconds $waitTime
            continue
        }
        elseif ($response.StatusCode -eq 408 -or $response.StatusCode -ge 500)
        {
            # Request Timeout or Server Error, pause for a moment and retry
            Start-Sleep -Milliseconds 500
            continue
        }
        else
        {
            return $response
        }
    }
}