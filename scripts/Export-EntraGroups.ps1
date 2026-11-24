<#
.SYNOPSIS
    Exports Microsoft Entra ID groups (the groups Intune apps and policies are assigned to)
    to a CSV file, so they can be recreated in another tenant.

.DESCRIPTION
    First half of a tenant-to-tenant group copy. For each group it saves the name,
    description, mail nickname, group type, visibility and, for dynamic groups, the
    membership rule. Import-EntraGroups.ps1 reads this file in the destination tenant.

    Members, owners and assignments are not exported.

.PARAMETER OutputPath
    Where to save the CSV file. Default: groups.csv in the current folder.

.EXAMPLE
    .\Export-EntraGroups.ps1 -OutputPath .\groups.csv

.NOTES
    Author      : Kamruzzaman Akib
    Modules     : Microsoft.Graph.Authentication, Microsoft.Graph.Groups
    Permissions : Group.Read.All (delegated)
    Sign in to the SOURCE tenant when prompted.
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups

[CmdletBinding()]
param(
    [string]$OutputPath = '.\groups.csv'
)

Connect-MgGraph -Scopes 'Group.Read.All' -NoWelcome -ErrorAction Stop
Write-Host "Connected to tenant $((Get-MgContext).TenantId)" -ForegroundColor Cyan

$properties = 'Id', 'DisplayName', 'Description', 'MailNickname', 'MailEnabled', 'SecurityEnabled',
              'GroupTypes', 'Visibility', 'MembershipRule', 'MembershipRuleProcessingState'

$groups = @(Get-MgGroup -All -Property $properties -ErrorAction Stop)

$groups | ForEach-Object {
    [PSCustomObject]@{
        ObjectId                      = $_.Id
        DisplayName                   = $_.DisplayName
        Description                   = $_.Description
        MailNickname                  = $_.MailNickname
        MailEnabled                   = $_.MailEnabled
        SecurityEnabled               = $_.SecurityEnabled
        GroupTypes                    = $_.GroupTypes -join ';'
        Visibility                    = $_.Visibility
        MembershipRule                = $_.MembershipRule
        MembershipRuleProcessingState = $_.MembershipRuleProcessingState
    }
} | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Exported $($groups.Count) groups to $((Resolve-Path -Path $OutputPath).Path)" -ForegroundColor Green

Disconnect-MgGraph | Out-Null
