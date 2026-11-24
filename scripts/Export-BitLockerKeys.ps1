<#
.SYNOPSIS
    Exports every BitLocker recovery key stored in Microsoft Entra ID to a CSV file,
    with the device name next to each key.

.DESCRIPTION
    The Intune and Entra admin centres show recovery keys one device at a time.
    This script lists every BitLocker recovery key backed up to Microsoft Entra ID,
    reads each key, and matches it to a device name: first from Intune managed
    devices, then from Entra ID devices for anything Intune no longer manages.

    Every key that is read is recorded in the Entra ID audit log (KeyManagement).
    The output file contains recovery keys: store it somewhere secure, limit who
    can open it, and delete it when you no longer need it.

.PARAMETER OutputPath
    Where to save the CSV file. Default: BitLockerKeys-<date>.csv in your Documents folder.

.EXAMPLE
    .\Export-BitLockerKeys.ps1

.EXAMPLE
    .\Export-BitLockerKeys.ps1 -OutputPath 'D:\Secure\BitLockerKeys.csv'

.NOTES
    Author      : Kamruzzaman Akib
    Modules     : Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns,
                  Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement
    Permissions : BitlockerKey.Read.All, DeviceManagementManagedDevices.Read.All, Device.Read.All (delegated)
    Admin role  : one of Cloud Device Administrator, Helpdesk Administrator, Intune Administrator,
                  Security Administrator, Security Reader or Global Reader
#>
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Identity.SignIns, Microsoft.Graph.DeviceManagement, Microsoft.Graph.Identity.DirectoryManagement

[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath ('BitLockerKeys-{0:yyyy-MM-dd}.csv' -f (Get-Date)))
)

Connect-MgGraph -Scopes 'BitlockerKey.Read.All', 'DeviceManagementManagedDevices.Read.All', 'Device.Read.All' -NoWelcome -ErrorAction Stop

# --- 1. Build a lookup table: Entra device ID -> device name -----------------
$deviceNames = @{}

Write-Host 'Reading Intune managed devices...' -ForegroundColor Cyan
try {
    Get-MgDeviceManagementManagedDevice -All -Property DeviceName, AzureADDeviceId -ErrorAction Stop |
        Where-Object { $_.AzureADDeviceId -and $_.AzureADDeviceId -ne '00000000-0000-0000-0000-000000000000' } |
        ForEach-Object { $deviceNames[$_.AzureADDeviceId] = $_.DeviceName }
} catch {
    Write-Warning "Could not read Intune devices: $($_.Exception.Message)"
}

Write-Host 'Reading Entra ID devices...' -ForegroundColor Cyan
try {
    Get-MgDevice -All -Property DeviceId, DisplayName -ErrorAction Stop |
        Where-Object { $_.DeviceId -and -not $deviceNames.ContainsKey($_.DeviceId) } |
        ForEach-Object { $deviceNames[$_.DeviceId] = $_.DisplayName }
} catch {
    Write-Warning "Could not read Entra ID devices: $($_.Exception.Message)"
}
Write-Host "Found names for $($deviceNames.Count) devices." -ForegroundColor Green

# --- 2. List every recovery key, then read each key value --------------------
$keys = @(Get-MgInformationProtectionBitlockerRecoveryKey -All -ErrorAction Stop)
Write-Host "Found $($keys.Count) recovery keys. Reading each one..." -ForegroundColor Cyan

$i = 0
$results = foreach ($k in $keys) {
    $i++
    Write-Progress -Activity 'Reading BitLocker recovery keys' -Status "$i of $($keys.Count)" -PercentComplete (100 * $i / $keys.Count)

    $recoveryKey = $null
    try {
        # The key value is only returned when it is asked for explicitly.
        $recoveryKey = (Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $k.Id -Property key -ErrorAction Stop).Key
    } catch {
        Write-Warning "Could not read key $($k.Id) (device $($k.DeviceId)): $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        DeviceName  = if ($k.DeviceId -and $deviceNames.ContainsKey($k.DeviceId)) { $deviceNames[$k.DeviceId] } else { 'Unknown device' }
        DeviceId    = $k.DeviceId
        KeyId       = $k.Id
        VolumeType  = $k.VolumeType
        Created     = $k.CreatedDateTime
        RecoveryKey = $recoveryKey
    }
}
Write-Progress -Activity 'Reading BitLocker recovery keys' -Completed

# --- 3. Save the results ------------------------------------------------------
$folder = Split-Path -Path $OutputPath -Parent
if ($folder -and -not (Test-Path -Path $folder)) {
    New-Item -Path $folder -ItemType Directory | Out-Null
}
$results | Sort-Object DeviceName, Created | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$missing = @($results | Where-Object { -not $_.RecoveryKey }).Count
Write-Host "Saved $($results.Count) keys to $OutputPath" -ForegroundColor Green
if ($missing -gt 0) {
    Write-Warning "$missing keys could not be read. Check that your account has one of the admin roles listed in the notes."
}
Write-Warning 'This file contains BitLocker recovery keys. Keep it somewhere secure and delete it when you are done.'
