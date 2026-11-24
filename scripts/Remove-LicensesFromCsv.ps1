<#
.SYNOPSIS
    Removes one Microsoft 365 licence from every user listed in a CSV file.

.DESCRIPTION
    Reads user principal names (UPNs) from a CSV file, lets you pick a licence (SKU)
    from the tenant in a grid, then removes it from each user who has it.

    Users who do not have the licence are skipped. Licences that a user gets through
    group-based licensing cannot be removed one user at a time, so those users are
    skipped with a message: remove them from the licensing group instead.

    Run it with -WhatIf first to see what would change without changing anything.

.PARAMETER CsvPath
    Path to the CSV file. It needs a column named UPN (or UserPrincipalName).

.EXAMPLE
    .\Remove-LicensesFromCsv.ps1 -CsvPath .\leavers.csv -WhatIf
    Dry run: shows which users would lose the licence.

.EXAMPLE
    .\Remove-LicensesFromCsv.ps1 -CsvPath .\leavers.csv
    Removes the licence you pick from every user in leavers.csv.

.NOTES
    Author      : Kamruzzaman Akib
    Modules     : Microsoft.Graph.Authentication, Microsoft.Graph.Users,
                  Microsoft.Graph.Identity.DirectoryManagement
    Permissions : LicenseAssignment.ReadWrite.All, User.Read.All, Organization.Read.All (delegated)
    Admin role  : License Administrator or User Administrator
    The licence picker uses Out-GridView, which needs Windows.
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath
)

# --- Read and check the CSV -------------------------------------------------
$rows = @(Import-Csv -Path $CsvPath)
if ($rows.Count -eq 0) {
    throw "The CSV file '$CsvPath' is empty."
}
$upnColumn = $rows[0].PSObject.Properties.Name |
    Where-Object { $_ -in 'UPN', 'UserPrincipalName' } |
    Select-Object -First 1
if (-not $upnColumn) {
    throw 'The CSV file needs a column named UPN or UserPrincipalName.'
}

# --- Connect to Microsoft Graph ---------------------------------------------
Connect-MgGraph -Scopes 'LicenseAssignment.ReadWrite.All', 'User.Read.All', 'Organization.Read.All' -NoWelcome -ErrorAction Stop

# --- Pick the licence --------------------------------------------------------
$sku = Get-MgSubscribedSku -ErrorAction Stop |
    Select-Object SkuPartNumber, SkuId, ConsumedUnits,
        @{ Name = 'Available'; Expression = { $_.PrepaidUnits.Enabled - $_.ConsumedUnits } } |
    Out-GridView -Title 'Select the licence to remove' -OutputMode Single

if (-not $sku) {
    Write-Warning 'No licence selected. Nothing was changed.'
    return
}
Write-Host "Selected licence: $($sku.SkuPartNumber) ($($sku.SkuId))" -ForegroundColor Cyan

# --- Remove the licence from each user --------------------------------------
$removed = 0; $skipped = 0; $failed = 0

foreach ($row in $rows) {
    $upn = "$($row.$upnColumn)".Trim()
    if (-not $upn) { continue }

    try {
        $user = Get-MgUser -UserId $upn -Property Id, UserPrincipalName, AssignedLicenses, LicenseAssignmentStates -ErrorAction Stop
    } catch {
        Write-Warning "$upn : could not find or read this user. $($_.Exception.Message)"
        $failed++
        continue
    }

    if ($user.AssignedLicenses.SkuId -notcontains $sku.SkuId) {
        Write-Host "$upn does not have $($sku.SkuPartNumber). Skipped." -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # A licence that only comes from a group cannot be removed from the user directly.
    $states = @($user.LicenseAssignmentStates | Where-Object { $_.SkuId -eq $sku.SkuId })
    if ($states.Count -gt 0 -and -not ($states | Where-Object { -not $_.AssignedByGroup })) {
        Write-Warning "$upn gets $($sku.SkuPartNumber) from a group. Remove the user from that group instead."
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($upn, "Remove licence $($sku.SkuPartNumber)")) {
        $body = @{
            addLicenses    = @()
            removeLicenses = @($sku.SkuId)
        } | ConvertTo-Json -Depth 5

        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($user.Id)/assignLicense" `
                -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Host "$upn : removed $($sku.SkuPartNumber)" -ForegroundColor Green
            $removed++
        } catch {
            Write-Warning "$upn : could not remove the licence. $($_.Exception.Message)"
            $failed++
        }
    }
}

Write-Host ''
Write-Host "Done. Removed: $removed   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan
