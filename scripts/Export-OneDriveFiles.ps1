<#
.SYNOPSIS
    Downloads users' OneDrive files to a local folder, keeping the folder structure.

.DESCRIPTION
    Built for a tenant migration, where every OneDrive had to be exported before the
    old tenant was closed. Choose who to export in one of three ways:

      -UserPrincipalName   one or more users
      -CsvPath             a CSV file with a UserPrincipalName (or UPN) column
      -AllUsers            every member account in the tenant (guests are skipped)

    Each user's files are saved to <ExportPath>\<UPN>\ with the same folders as in
    OneDrive. Files that are already there with the same size are skipped, so you can
    stop the script and run it again to carry on where it left off.

    You must be Site Collection Administrator on each OneDrive first (see
    Add-OneDriveSiteAdmin.ps1), otherwise that OneDrive is reported as not accessible.

.PARAMETER UserPrincipalName
    One or more users to export.

.PARAMETER CsvPath
    A CSV file with a column named UserPrincipalName or UPN.

.PARAMETER AllUsers
    Export every member account in the tenant.

.PARAMETER ExportPath
    Local folder to save the files in. It is created if it does not exist.

.EXAMPLE
    .\Export-OneDriveFiles.ps1 -UserPrincipalName alex.wilber@contoso.com -ExportPath D:\OneDriveExport

.EXAMPLE
    .\Export-OneDriveFiles.ps1 -CsvPath .\users.csv -ExportPath D:\OneDriveExport

.EXAMPLE
    .\Export-OneDriveFiles.ps1 -AllUsers -ExportPath D:\OneDriveExport

.NOTES
    Author      : Kamruzzaman Akib
    Modules     : Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Files
    Permissions : Files.Read.All, User.Read.All (delegated)
    Replaces my three earlier scripts (single user, CSV list, whole organisation).
    OneNote notebooks are listed as not exported: export them from OneNote instead.
    Paths longer than 260 characters can fail unless Windows long paths are enabled.
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Files

[CmdletBinding(DefaultParameterSetName = 'User')]
param(
    [Parameter(Mandatory, ParameterSetName = 'User')]
    [string[]]$UserPrincipalName,

    [Parameter(Mandatory, ParameterSetName = 'Csv')]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory, ParameterSetName = 'All')]
    [switch]$AllUsers,

    [Parameter(Mandatory)]
    [string]$ExportPath
)

$stats      = @{ Files = 0; AlreadyThere = 0; Failed = 0; Bytes = 0 }
$notExported = [System.Collections.Generic.List[string]]::new()

function Save-DriveFolder {
    param(
        [string]$DriveId,
        [string]$ItemId,
        [string]$LocalPath,
        [switch]$IsRoot
    )
    New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null

    try {
        # -All follows paging. Without it, folders with more than 200 items are cut short.
        $children = Get-MgDriveItemChild -DriveId $DriveId -DriveItemId $ItemId -All -ErrorAction Stop
    }
    catch {
        if ($IsRoot) { throw }
        $script:stats.Failed++
        Write-Warning "Could not list $($LocalPath): $($_.Exception.Message)"
        return
    }

    foreach ($item in $children) {
        $target = Join-Path -Path $LocalPath -ChildPath $item.Name

        if ($item.Folder) {
            Save-DriveFolder -DriveId $DriveId -ItemId $item.Id -LocalPath $target
        }
        elseif ($item.File) {
            if ((Test-Path -LiteralPath $target) -and (Get-Item -LiteralPath $target).Length -eq $item.Size) {
                $script:stats.AlreadyThere++
                continue
            }
            try {
                Get-MgDriveItemContent -DriveId $DriveId -DriveItemId $item.Id -OutFile $target -ErrorAction Stop
                $script:stats.Files++
                $script:stats.Bytes += $item.Size
                Write-Verbose "Downloaded $target"
            }
            catch {
                $script:stats.Failed++
                Write-Warning "Could not download $($target): $($_.Exception.Message)"
            }
        }
        else {
            # OneNote notebooks and other packages are not plain files
            $notExported.Add($target)
        }
    }
}

# --- Connect and work out who to export --------------------------------------
Connect-MgGraph -Scopes 'Files.Read.All', 'User.Read.All' -NoWelcome -ErrorAction Stop

switch ($PSCmdlet.ParameterSetName) {
    'User' {
        $upns = $UserPrincipalName
    }
    'Csv' {
        $rows = @(Import-Csv -Path $CsvPath)
        if ($rows.Count -eq 0) { throw "The CSV file '$CsvPath' is empty." }
        $column = $rows[0].PSObject.Properties.Name |
            Where-Object { $_ -in 'UserPrincipalName', 'UPN' } |
            Select-Object -First 1
        if (-not $column) { throw 'The CSV file needs a column named UserPrincipalName or UPN.' }
        $upns = $rows.$column | Where-Object { $_ } | ForEach-Object { $_.Trim() }
    }
    'All' {
        $upns = Get-MgUser -All -Filter "userType eq 'Member'" -Property UserPrincipalName -ErrorAction Stop |
            Select-Object -ExpandProperty UserPrincipalName
    }
}
$upns = @($upns | Sort-Object -Unique)
Write-Host "Users to export: $($upns.Count)" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null

# --- Export each OneDrive ----------------------------------------------------
$usersDone    = 0
$usersSkipped = [System.Collections.Generic.List[string]]::new()
$i = 0

foreach ($upn in $upns) {
    $i++
    Write-Progress -Activity 'Exporting OneDrives' -Status "$upn ($i of $($upns.Count))" -PercentComplete ($i / $upns.Count * 100)

    try {
        $drive = Get-MgUserDefaultDrive -UserId $upn -ErrorAction Stop
        Write-Host "Exporting $upn" -ForegroundColor Cyan
        Save-DriveFolder -DriveId $drive.Id -ItemId 'root' -LocalPath (Join-Path -Path $ExportPath -ChildPath $upn) -IsRoot
        $usersDone++
    }
    catch {
        $usersSkipped.Add($upn)
        Write-Warning "Skipped $($upn): no OneDrive, or you are not Site Collection Administrator on it. $($_.Exception.Message)"
    }
}
Write-Progress -Activity 'Exporting OneDrives' -Completed

# --- Summary -----------------------------------------------------------------
Write-Host ''
Write-Host "Users exported   : $usersDone of $($upns.Count)" -ForegroundColor Green
Write-Host "Files downloaded : $($stats.Files) ($([math]::Round($stats.Bytes / 1GB, 2)) GB)"
Write-Host "Already there    : $($stats.AlreadyThere)"
if ($stats.Failed) { Write-Host "Failed           : $($stats.Failed) (see the warnings above, then run again)" -ForegroundColor Red }
if ($usersSkipped.Count) {
    Write-Host "Users skipped    : $($usersSkipped -join ', ')" -ForegroundColor Yellow
}
if ($notExported.Count) {
    Write-Host "Not exported (OneNote notebooks or other packages): $($notExported.Count)" -ForegroundColor Yellow
    $notExported | ForEach-Object { Write-Host "  $_" }
}
Write-Host "Files are in $((Resolve-Path -Path $ExportPath).Path)"

Disconnect-MgGraph | Out-Null
