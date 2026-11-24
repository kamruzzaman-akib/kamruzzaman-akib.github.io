<#
.SYNOPSIS
    Assigns one Microsoft 365 licence to every user listed in a CSV file.

.DESCRIPTION
    Reads user principal names (UPNs) from a CSV file, lets you pick a licence (SKU)
    from the tenant in a grid, then assigns it to each user who does not already have it.

    Users who already have the licence are skipped. Users with no usage location are
    skipped too, because Microsoft 365 cannot assign a licence without one.

    Run it with -WhatIf first to see what would change without changing anything.

.PARAMETER CsvPath
    Path to the CSV file. It needs a column named UPN (or UserPrincipalName).

.EXAMPLE
    .\Add-LicensesFromCsv.ps1 -CsvPath .\users.csv -WhatIf
    Dry run: shows which users would get the licence.

.EXAMPLE
    .\Add-LicensesFromCsv.ps1 -CsvPath .\users.csv
    Assigns the licence you pick to every user in users.csv.

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
    Out-GridView -Title 'Select the licence to assign' -OutputMode Single

if (-not $sku) {
    Write-Warning 'No licence selected. Nothing was changed.'
    return
}
Write-Host "Selected licence: $($sku.SkuPartNumber) ($($sku.SkuId))" -ForegroundColor Cyan

# --- Assign the licence to each user ----------------------------------------
$assigned = 0; $skipped = 0; $failed = 0

foreach ($row in $rows) {
    $upn = "$($row.$upnColumn)".Trim()
    if (-not $upn) { continue }

    try {
        $user = Get-MgUser -UserId $upn -Property Id, UserPrincipalName, UsageLocation, AssignedLicenses -ErrorAction Stop
    } catch {
        Write-Warning "$upn : could not find or read this user. $($_.Exception.Message)"
        $failed++
        continue
    }

    if ($user.AssignedLicenses.SkuId -contains $sku.SkuId) {
        Write-Host "$upn already has $($sku.SkuPartNumber). Skipped." -ForegroundColor DarkGray
        $skipped++
        continue
    }

    if (-not $user.UsageLocation) {
        Write-Warning "$upn has no usage location, so a licence cannot be assigned. Set one and run the script again."
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($upn, "Assign licence $($sku.SkuPartNumber)")) {
        $body = @{
            addLicenses    = @(@{ skuId = $sku.SkuId })
            removeLicenses = @()
        } | ConvertTo-Json -Depth 5

        try {
            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($user.Id)/assignLicense" `
                -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Host "$upn : assigned $($sku.SkuPartNumber)" -ForegroundColor Green
            $assigned++
        } catch {
            Write-Warning "$upn : could not assign the licence. $($_.Exception.Message)"
            $failed++
        }
    }
}

Write-Host ''
Write-Host "Done. Assigned: $assigned   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan
