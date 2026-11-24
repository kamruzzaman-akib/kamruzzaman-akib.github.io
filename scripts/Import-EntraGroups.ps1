<#
.SYNOPSIS
    Recreates Microsoft Entra ID groups from a CSV made by Export-EntraGroups.ps1.

.DESCRIPTION
    Second half of a tenant-to-tenant group copy. Run it while signed in to the
    DESTINATION tenant. For each row it creates a security group or Microsoft 365
    group with the same name, description, mail nickname, visibility and (for
    dynamic groups) membership rule.

    It skips:
      - groups whose name already exists in the destination tenant, so the script
        is safe to run again;
      - distribution lists and mail-enabled security groups, because Microsoft Graph
        cannot create them (create them in Exchange Online instead).

    It also writes <CsvPath>-id-map.csv with the old and new group IDs, which helps
    when you recreate Intune assignments.

    Run it with -WhatIf first to see what would be created.

.PARAMETER CsvPath
    Path to the CSV file created by Export-EntraGroups.ps1.

.EXAMPLE
    .\Import-EntraGroups.ps1 -CsvPath .\groups.csv -WhatIf

.EXAMPLE
    .\Import-EntraGroups.ps1 -CsvPath .\groups.csv

.NOTES
    Author      : Kamruzzaman Akib
    Modules     : Microsoft.Graph.Authentication, Microsoft.Graph.Groups
    Permissions : Group.ReadWrite.All (delegated)
    Members and owners are not copied.
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath
)

$rows = @(Import-Csv -Path $CsvPath)
if ($rows.Count -eq 0) {
    throw "The CSV file '$CsvPath' is empty."
}

Connect-MgGraph -Scopes 'Group.ReadWrite.All' -NoWelcome -ErrorAction Stop
Write-Host "Connected to tenant $((Get-MgContext).TenantId)" -ForegroundColor Cyan

$created = 0; $skipped = 0; $failed = 0
$idMap = New-Object System.Collections.Generic.List[object]

foreach ($row in $rows) {
    $name = $row.DisplayName
    if (-not $name) { continue }

    $groupTypes      = @($row.GroupTypes -split ';' | Where-Object { $_ })
    $mailEnabled     = ($row.MailEnabled -eq 'True')
    $securityEnabled = ($row.SecurityEnabled -eq 'True')

    # Microsoft Graph can only create Microsoft 365 groups and security groups.
    if ($mailEnabled -and ($groupTypes -notcontains 'Unified')) {
        Write-Warning "Skipped '$name': distribution lists and mail-enabled security groups must be created in Exchange Online."
        $skipped++
        continue
    }

    # Do not create a second group with the same name.
    $filterName = $name -replace "'", "''"
    $existing = Get-MgGroup -Filter "displayName eq '$filterName'" -Top 1 -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Skipped '$name': a group with this name already exists." -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # Mail nickname is required. Make one from the name if the CSV has none.
    $mailNickname = $row.MailNickname
    if (-not $mailNickname) {
        $mailNickname = ($name -replace '[^a-zA-Z0-9]', '')
        if (-not $mailNickname) { $mailNickname = 'group' + (Get-Random -Maximum 999999) }
    }

    $params = @{
        DisplayName     = $name
        MailNickname    = $mailNickname
        MailEnabled     = $mailEnabled
        SecurityEnabled = $securityEnabled
    }
    if ($groupTypes.Count -gt 0) { $params.GroupTypes = $groupTypes }
    if ($row.Description -and $row.Description -ne '.') { $params.Description = $row.Description }
    if ($row.Visibility) { $params.Visibility = $row.Visibility }
    if ($row.MembershipRule) {
        $params.MembershipRule = $row.MembershipRule
        $params.MembershipRuleProcessingState = if ($row.MembershipRuleProcessingState) { $row.MembershipRuleProcessingState } else { 'On' }
    }

    if ($PSCmdlet.ShouldProcess($name, 'Create group')) {
        try {
            $newGroup = New-MgGroup @params -ErrorAction Stop
            Write-Host "Created '$name' ($($newGroup.Id))" -ForegroundColor Green
            $idMap.Add([PSCustomObject]@{ DisplayName = $name; OldId = $row.ObjectId; NewId = $newGroup.Id })
            $created++
        } catch {
            Write-Warning "Failed to create '$name': $($_.Exception.Message)"
            $failed++
        }
    }
}

if ($idMap.Count -gt 0) {
    $mapPath = [System.IO.Path]::ChangeExtension((Resolve-Path -Path $CsvPath).Path, $null).TrimEnd('.') + '-id-map.csv'
    $idMap | Export-Csv -Path $mapPath -NoTypeInformation -Encoding UTF8
    Write-Host "Old and new group IDs saved to $mapPath" -ForegroundColor Cyan
}

Write-Host ''
Write-Host "Done. Created: $created   Skipped: $skipped   Failed: $failed" -ForegroundColor Cyan

Disconnect-MgGraph | Out-Null
