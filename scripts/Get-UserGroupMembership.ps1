<#
.SYNOPSIS
    Lists the groups a user belongs to in Microsoft Entra ID, with the type of each group.

.DESCRIPTION
    Useful when you need to know why someone has, or doesn't have, access to an app,
    a policy or a mailbox. For each group it shows the name, the type (security,
    Microsoft 365, distribution list or mail-enabled security), whether membership is
    dynamic, and the group ID.

    By default it lists direct memberships. Add -Transitive to include groups the user
    is in through another group (nested groups).

.PARAMETER UserPrincipalName
    The user to look up. You are asked for it if you leave it out.

.PARAMETER Transitive
    Include nested group memberships.

.PARAMETER OutputPath
    Optional. Also saves the list to this CSV file.

.EXAMPLE
    .\Get-UserGroupMembership.ps1 -UserPrincipalName alex.wilber@contoso.com

.EXAMPLE
    .\Get-UserGroupMembership.ps1 alex.wilber@contoso.com -Transitive -OutputPath .\alex-groups.csv

.NOTES
    Author      : Kamruzzaman Akib
    Module      : Microsoft.Graph.Authentication
    Permissions : User.Read.All, GroupMember.Read.All (delegated)
    Directory roles and administrative units are left out; only groups are listed.
#>
#Requires -Modules Microsoft.Graph.Authentication

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$UserPrincipalName,

    [switch]$Transitive,

    [string]$OutputPath
)

Connect-MgGraph -Scopes 'User.Read.All', 'GroupMember.Read.All' -NoWelcome -ErrorAction Stop

try {
    # --- Find the user -------------------------------------------------------
    $id = [uri]::EscapeDataString($UserPrincipalName)
    try {
        $user = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/users/$($id)?`$select=id,displayName,userPrincipalName" -ErrorAction Stop
    }
    catch {
        throw "User '$UserPrincipalName' was not found. $($_.Exception.Message)"
    }

    # --- Read every page of memberships --------------------------------------
    $relation = if ($Transitive) { 'transitiveMemberOf' } else { 'memberOf' }
    $uri      = "/v1.0/users/$($user.id)/$($relation)?`$top=999"
    $groups   = [System.Collections.Generic.List[object]]::new()

    while ($uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        foreach ($entry in $page.value) {
            if ($entry.'@odata.type' -eq '#microsoft.graph.group') { $groups.Add($entry) }
        }
        $uri = $page.'@odata.nextLink'
    }

    # --- Describe each group -------------------------------------------------
    $result = foreach ($g in $groups) {
        $kind = if ($g.groupTypes -contains 'Unified')           { 'Microsoft 365' }
                elseif ($g.mailEnabled -and $g.securityEnabled)  { 'Mail-enabled security' }
                elseif ($g.mailEnabled)                          { 'Distribution list' }
                else                                             { 'Security' }
        [PSCustomObject]@{
            Group      = $g.displayName
            Type       = $kind
            Membership = if ($g.groupTypes -contains 'DynamicMembership') { 'Dynamic' } else { 'Assigned' }
            GroupId    = $g.id
        }
    }
    $result = @($result | Sort-Object Group)

    $scope = if ($Transitive) { 'direct and nested' } else { 'direct' }
    Write-Host "$($user.displayName) ($($user.userPrincipalName)) is a $scope member of $($result.Count) groups." -ForegroundColor Cyan
    $result | Format-Table -AutoSize

    if ($OutputPath) {
        $result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Saved to $((Resolve-Path -Path $OutputPath).Path)" -ForegroundColor Green
    }
}
finally {
    Disconnect-MgGraph | Out-Null
}
