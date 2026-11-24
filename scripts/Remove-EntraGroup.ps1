<#
.SYNOPSIS
    Deletes a Microsoft Entra ID group by its object ID.

.DESCRIPTION
    Handy for cleaning up after a test import, or for removing a group straight
    through Microsoft Graph when the admin centre is slow or unhelpful.
    It looks the group up first, shows its name and asks you to confirm.
    Use -Force to skip the confirmation prompt (for example, in a loop).

    Microsoft 365 groups can be restored for 30 days after deletion.
    Treat any other group type as permanently deleted.

.PARAMETER GroupId
    Object ID of the group, as shown in the Entra or Intune admin centre.

.PARAMETER Force
    Delete without asking for confirmation.

.EXAMPLE
    .\Remove-EntraGroup.ps1 -GroupId 3f2a6b1c-0d4e-4f5a-9b8c-7d6e5f4a3b2c

.EXAMPLE
    .\Remove-EntraGroup.ps1 -GroupId 3f2a6b1c-0d4e-4f5a-9b8c-7d6e5f4a3b2c -WhatIf

.NOTES
    Author      : Kamruzzaman Akib
    Modules     : Microsoft.Graph.Authentication, Microsoft.Graph.Groups
    Permissions : Group.ReadWrite.All (delegated)
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, HelpMessage = 'Object ID of the group to delete')]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$GroupId,

    [switch]$Force
)

if ($Force -and -not $PSBoundParameters.ContainsKey('Confirm')) {
    $ConfirmPreference = 'None'
}

Connect-MgGraph -Scopes 'Group.ReadWrite.All' -NoWelcome -ErrorAction Stop

try {
    $group = Get-MgGroup -GroupId $GroupId -Property Id, DisplayName, GroupTypes -ErrorAction Stop
} catch {
    Write-Error "No group found with ID $GroupId. $($_.Exception.Message)"
    return
}

$kind = if ($group.GroupTypes -contains 'Unified') { 'Microsoft 365 group' } else { 'group' }

if ($PSCmdlet.ShouldProcess("$($group.DisplayName) ($GroupId)", "Delete $kind")) {
    try {
        Remove-MgGroup -GroupId $GroupId -Confirm:$false -ErrorAction Stop
        Write-Host "Deleted $kind '$($group.DisplayName)' ($GroupId)." -ForegroundColor Green
    } catch {
        Write-Error "Could not delete '$($group.DisplayName)': $($_.Exception.Message)"
    }
}
