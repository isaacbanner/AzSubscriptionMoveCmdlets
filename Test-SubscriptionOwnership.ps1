function Test-SubscriptionOwnership {
    param (
        [Parameter()]
        [string]$SubscriptionId
    )
    if (-not $SubscriptionId) {
        Write-Debug "No subscription specified, testing subscription for current Azure context"
        $SubscriptionId = (Get-UserContext).Subscription.Id
    }

    Write-Debug "Testing subscription ownership for $SubscriptionId"

    $ownerAssignments = (Get-AzRoleAssignment
    | Where-Object { $_.Scope -eq "/subscriptions/$SubscriptionId" }
    | Where-Object { $_.RoleDefinitionName -eq "Owner" }
    | Measure-Object).Count

    return $ownerAssignments -gt 0
}