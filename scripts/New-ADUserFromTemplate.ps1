<#
.SYNOPSIS
    Creates an on-premises Active Directory user by copying a template user from the
    same OU.

.DESCRIPTION
    The onboarding shortcut I used for new joiners. You type the first and last name,
    pick the OU and a template user (someone in the same team), and the script:

      - builds a unique username (first initial + last name, then 1, 2, 3... if taken),
        removing accents and punctuation (Jose O'Brien -> jobrien)
      - creates the account with the UPN and email address set, and forces a password
        change at first sign-in
      - copies Company, Department and Office from the template user
      - adds the new user to the same groups as the template user

    It shows what it is about to do before it does it. Run it with -WhatIf for a dry run.

.PARAMETER SearchBase
    Distinguished name of the OU that holds your user OUs, for example
    "OU=Staff,DC=corp,DC=contoso,DC=com". Default: the whole domain.

.PARAMETER UpnSuffix
    The part after @ in the new user's UPN and email address, for example contoso.com.
    Default: the domain's DNS name.

.PARAMETER FirstName
    Optional. You are asked for it if you leave it out.

.PARAMETER LastName
    Optional. You are asked for it if you leave it out.

.EXAMPLE
    .\New-ADUserFromTemplate.ps1 -SearchBase "OU=Staff,DC=corp,DC=contoso,DC=com" -UpnSuffix contoso.com -WhatIf

.EXAMPLE
    .\New-ADUserFromTemplate.ps1 -UpnSuffix contoso.com -FirstName Alex -LastName Wilber

.NOTES
    Author : Kamruzzaman Akib
    Module : ActiveDirectory (RSAT), Windows PowerShell 5.1
    Rights : create users in the chosen OU and change membership of the copied groups
    The OU and template pickers use Out-GridView.
    The password is typed as a secure string and is never shown or saved.
#>
#Requires -Modules ActiveDirectory

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SearchBase,
    [string]$UpnSuffix,
    [string]$FirstName,
    [string]$LastName
)

$domain = Get-ADDomain -ErrorAction Stop
if (-not $SearchBase) { $SearchBase = $domain.DistinguishedName }
if (-not $UpnSuffix)  { $UpnSuffix  = $domain.DNSRoot }

# Use one domain controller for every step, so the new account is never
# "not found" because of replication delay.
$server = $domain.PDCEmulator

function ConvertTo-UsernamePart {
    param([string]$Text)
    # Remove accents (an accented e becomes e), then anything that is not a letter (O'Brien -> OBrien)
    $decomposed = $Text.Normalize([Text.NormalizationForm]::FormD)
    $letters = $decomposed.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
    }
    (-join $letters).ToLower() -replace '[^a-z]', ''
}

function New-UniqueUsername {
    param([string]$First, [string]$Last)
    $f = ConvertTo-UsernamePart $First
    $l = ConvertTo-UsernamePart $Last
    if (-not $f -or -not $l) { throw 'The first and last name must contain letters.' }

    # sAMAccountName allows 20 characters; keep room for a number on the end
    $base = $f.Substring(0, 1) + $l
    if ($base.Length -gt 17) { $base = $base.Substring(0, 17) }

    $candidate = $base
    $n = 0
    while (Get-ADUser -Server $server -Filter "SamAccountName -eq '$candidate' -or UserPrincipalName -eq '$candidate@$UpnSuffix'") {
        $n++
        $candidate = "$base$n"
    }
    $candidate
}

# --- Names -----------------------------------------------------------------------
if (-not $FirstName) { $FirstName = Read-Host 'First name' }
if (-not $LastName)  { $LastName  = Read-Host 'Last name' }
$FirstName = $FirstName.Trim()
$LastName  = $LastName.Trim()

# --- Pick the OU and the template user ----------------------------------------------
$ou = Get-ADOrganizationalUnit -Server $server -Filter * -SearchBase $SearchBase |
    Sort-Object DistinguishedName |
    Select-Object Name, DistinguishedName |
    Out-GridView -Title 'Pick the OU for the new user' -OutputMode Single
if (-not $ou) { Write-Warning 'No OU picked. Nothing was created.'; return }

$candidates = @(Get-ADUser -Server $server -Filter 'Enabled -eq $true' -SearchBase $ou.DistinguishedName -SearchScope OneLevel -Properties Title, Department)
$template = $null
if ($candidates.Count -eq 0) {
    Write-Warning 'There are no enabled users in this OU to copy, so no groups will be copied.'
}
else {
    $pick = $candidates |
        Sort-Object Name |
        Select-Object Name, SamAccountName, Title, Department, DistinguishedName |
        Out-GridView -Title 'Pick a template user (someone in the same role or team)' -OutputMode Single
    if (-not $pick) { Write-Warning 'No template user picked. Nothing was created.'; return }
    $template = Get-ADUser -Server $server -Identity $pick.DistinguishedName -Properties MemberOf, Company, Department, Office
}
$groups = if ($template) { @($template.MemberOf) } else { @() }

# --- Build the account details ------------------------------------------------------
$username    = New-UniqueUsername -First $FirstName -Last $LastName
$upn         = "$username@$UpnSuffix"
$displayName = "$FirstName $LastName"

# The object name (CN) must be unique inside the OU
$cn = $displayName
$escapedName = $displayName -replace "'", "''"
if (Get-ADUser -Server $server -Filter "Name -eq '$escapedName'" -SearchBase $ou.DistinguishedName -SearchScope OneLevel) {
    $cn = "$displayName ($username)"
}

Write-Host ''
Write-Host 'About to create:' -ForegroundColor Cyan
[PSCustomObject]@{
    Name     = $cn
    Username = $username
    UPN      = $upn
    OU       = $ou.DistinguishedName
    Template = if ($template) { $template.Name } else { '(none)' }
    Groups   = $groups.Count
} | Format-List

if (-not $PSCmdlet.ShouldProcess($upn, "Create user in $($ou.DistinguishedName)")) { return }

$password = Read-Host 'Initial password (the user must change it at first sign-in)' -AsSecureString

$newUser = @{
    Server                = $server
    Name                  = $cn
    GivenName             = $FirstName
    Surname               = $LastName
    DisplayName           = $displayName
    SamAccountName        = $username
    UserPrincipalName     = $upn
    EmailAddress          = $upn
    Path                  = $ou.DistinguishedName
    AccountPassword       = $password
    Enabled               = $true
    ChangePasswordAtLogon = $true
    PassThru              = $true
    ErrorAction           = 'Stop'
}
if ($template) {
    foreach ($attribute in 'Company', 'Department', 'Office') {
        if ($template.$attribute) { $newUser[$attribute] = $template.$attribute }
    }
}

try {
    $created = New-ADUser @newUser
}
catch {
    Write-Warning "The user was not created: $($_.Exception.Message)"
    Write-Warning 'If the message is about the password, the account may exist but be disabled. Reset its password and enable it in Active Directory Users and Computers.'
    return
}
Write-Host "Created $upn in $($ou.DistinguishedName)." -ForegroundColor Green

# --- Copy the template user's groups -------------------------------------------------
$added  = 0
$failed = 0
foreach ($group in $groups) {
    try {
        Add-ADGroupMember -Server $server -Identity $group -Members $created -ErrorAction Stop
        $added++
    }
    catch {
        $failed++
        Write-Warning "Could not add to $($group): $($_.Exception.Message)"
    }
}
if ($template) {
    Write-Host "Added to $added of $($groups.Count) groups copied from $($template.Name)." -ForegroundColor Green
}
if ($failed) { Write-Host "$failed groups failed. Add those by hand." -ForegroundColor Yellow }

Write-Host ''
Write-Host "Sign-in name for the new user: $upn" -ForegroundColor Cyan
Write-Host 'Give them the password you typed through a secure channel. They must change it at first sign-in.'
