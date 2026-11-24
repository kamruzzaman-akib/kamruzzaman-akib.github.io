<#
.SYNOPSIS
    Adds (or removes) one account as Site Collection Administrator on every OneDrive
    in the tenant.

.DESCRIPTION
    Global and SharePoint administrators cannot open another user's OneDrive until
    they are a Site Collection Administrator on it. This script lists every OneDrive
    (personal site) in the tenant and grants that right to one account, so a bulk
    export such as Export-OneDriveFiles.ps1 can read the files.

    When the export is finished, run it again with -Remove to take the access away.

    Run it with -WhatIf first to see which OneDrives would change.

.PARAMETER AdminUrl
    Your SharePoint admin centre URL, for example https://contoso-admin.sharepoint.com

.PARAMETER UserPrincipalName
    The account to add (or remove) as Site Collection Administrator.

.PARAMETER Remove
    Removes the account as Site Collection Administrator instead of adding it.

.EXAMPLE
    .\Add-OneDriveSiteAdmin.ps1 -AdminUrl https://contoso-admin.sharepoint.com -UserPrincipalName admin@contoso.com -WhatIf
    Dry run: lists the OneDrives that would change.

.EXAMPLE
    .\Add-OneDriveSiteAdmin.ps1 -AdminUrl https://contoso-admin.sharepoint.com -UserPrincipalName admin@contoso.com -Remove
    Takes the access away again after the export.

.NOTES
    Author     : Kamruzzaman Akib
    Module     : Microsoft.Online.SharePoint.PowerShell (run it in Windows PowerShell 5.1)
    Admin role : SharePoint Administrator or Global Administrator
    Access to personal files is sensitive. Get written approval first, and remove
    the access as soon as the work is done.
#>
#Requires -Modules Microsoft.Online.SharePoint.PowerShell

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://[\w-]+-admin\.sharepoint\.[a-z.]+/?$')]
    [string]$AdminUrl,

    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [switch]$Remove
)

Connect-SPOService -Url $AdminUrl -ErrorAction Stop

Write-Host 'Listing every OneDrive in the tenant. This can take a few minutes...' -ForegroundColor Cyan
$sites = @(Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'" -ErrorAction Stop)
Write-Host "Found $($sites.Count) OneDrives." -ForegroundColor Cyan

$grant  = -not $Remove
$action = if ($grant) { 'Add as Site Collection Administrator' } else { 'Remove as Site Collection Administrator' }
$changed = 0
$failed  = 0
$i       = 0

foreach ($site in $sites) {
    $i++
    Write-Progress -Activity $action -Status $site.Url -PercentComplete ($i / $sites.Count * 100)

    if (-not $PSCmdlet.ShouldProcess($site.Url, "$action ($UserPrincipalName)")) { continue }

    try {
        $null = Set-SPOUser -Site $site.Url -LoginName $UserPrincipalName -IsSiteCollectionAdmin $grant -ErrorAction Stop
        $changed++
        Write-Verbose "Done: $($site.Url)"
    }
    catch {
        $failed++
        Write-Warning "Failed on $($site.Url): $($_.Exception.Message)"
    }
}
Write-Progress -Activity $action -Completed

Write-Host ''
Write-Host "OneDrives found : $($sites.Count)"
Write-Host "Changed         : $changed" -ForegroundColor Green
if ($failed) { Write-Host "Failed          : $failed" -ForegroundColor Red }
if ($grant -and $changed) {
    Write-Host 'When the export is finished, run this again with -Remove to take the access away.' -ForegroundColor Yellow
}

Disconnect-SPOService
