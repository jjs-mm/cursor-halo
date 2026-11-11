[CmdletBinding()]
param([Parameter(Mandatory = $true)][ValidateSet('win-x64', 'win-arm64')][string]$Runtime)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true') { throw 'This installation smoke check is restricted to disposable GitHub Actions runners.' }
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Package = Join-Path $ProjectRoot ".build/package-windows/$Runtime"
$Installer = Join-Path $Package 'Install-CursorHalo.ps1'
$Manifest = Get-Content -LiteralPath (Join-Path $Package 'package-manifest.json') -Raw | ConvertFrom-Json
$ExpectedId = 'local.personal.CursorHalo'
$LocalData = [Environment]::GetFolderPath('LocalApplicationData')
$Programs = Join-Path $LocalData 'Programs'
$Destination = Join-Path $Programs 'Cursor Halo'
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'Cursor Halo.lnk'
$Preferences = Join-Path $LocalData 'CursorHalo/settings.json'
$ExistingBackups = @(Get-ChildItem -Path (Join-Path $Programs 'Cursor Halo.backup-*') -Directory -ErrorAction SilentlyContinue)
if ((Test-Path -LiteralPath $Destination) -or (Test-Path -LiteralPath $ShortcutPath) -or $ExistingBackups.Count -ne 0) {
    throw 'Refusing to run: this runner already contains Cursor Halo installations or shortcuts.'
}
function Get-PreferenceDigest {
    if (Test-Path -LiteralPath $Preferences) { return (Get-FileHash -LiteralPath $Preferences -Algorithm SHA256).Hash }
    return 'absent'
}
function Get-StartupSnapshot {
    $Key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $false)
    try {
        if ($null -eq $Key -or -not ($Key.GetValueNames() -contains 'CursorHalo')) { return '{"exists":false}' }
        return ([ordered]@{
            exists = $true
            kind = [string]$Key.GetValueKind('CursorHalo')
            value = $Key.GetValue('CursorHalo', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        } | ConvertTo-Json -Compress -Depth 4)
    }
    finally { if ($null -ne $Key) { $Key.Dispose() } }
}
function Assert-Installed([string]$Path) {
    $Marker = Get-Content -LiteralPath (Join-Path $Path '.cursor-halo-install.json') -Raw | ConvertFrom-Json
    if ($Marker.appId -ne $ExpectedId -or $Marker.version -ne $Manifest.version) { throw "Incorrect installation marker: $Path" }
    $Hash = (Get-FileHash -LiteralPath (Join-Path $Path 'CursorHalo.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Hash -ne $Manifest.executableSha256) { throw "Incorrect installed executable: $Path" }
    $SourceLicense = (Get-FileHash -LiteralPath (Join-Path $Package 'app/LICENSE') -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath (Join-Path $Path 'LICENSE') -Algorithm SHA256).Hash -ne $SourceLicense) { throw "Missing or changed app license: $Path" }
    foreach ($Pack in $Manifest.runtimePacks) {
        foreach ($Name in $Pack.notices) {
            $Relative = "notices/$($Pack.id)-$($Pack.version)/$Name"
            $SourceHash = (Get-FileHash -LiteralPath (Join-Path (Join-Path $Package 'app') $Relative) -Algorithm SHA256).Hash
            if ((Get-FileHash -LiteralPath (Join-Path $Path $Relative) -Algorithm SHA256).Hash -ne $SourceHash) {
                throw "Missing or changed runtime notice: $Relative"
            }
        }
    }
}
function Assert-Shortcut {
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    if (-not [string]::Equals($Shortcut.TargetPath, (Join-Path $Destination 'CursorHalo.exe'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Start menu shortcut has an incorrect target.'
    }
}
$BeforePreferences = Get-PreferenceDigest
$BeforeStartup = Get-StartupSnapshot
try {
    & $Installer
    Assert-Installed $Destination
    Assert-Shortcut
    if (@(Get-ChildItem -Path (Join-Path $Programs 'Cursor Halo.backup-*') -Directory -ErrorAction SilentlyContinue).Count -ne 0) {
        throw 'A fresh install unexpectedly created a backup.'
    }
    & $Installer
    Assert-Installed $Destination
    Assert-Shortcut
    $Backups = @(Get-ChildItem -Path (Join-Path $Programs 'Cursor Halo.backup-*') -Directory -ErrorAction SilentlyContinue)
    if ($Backups.Count -ne 1) { throw 'Update did not preserve exactly one previous installation.' }
    Assert-Installed ($Backups[0].FullName)
    if ((Get-PreferenceDigest) -ne $BeforePreferences) { throw 'The installer changed appearance preferences.' }
    if ((Get-StartupSnapshot) -ne $BeforeStartup) { throw 'The installer changed launch-at-login registration.' }
    Write-Host 'Windows installer smoke passed: fresh install, replacement, backup, hashes, licenses, notices, shortcut, and unchanged preferences/startup registration.'
}
finally {
    # Preflight proved all these app paths and the shortcut were absent.
    $Owned = @($Destination) + @(Get-ChildItem -Path (Join-Path $Programs 'Cursor Halo.backup-*') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($Path in $Owned) {
        $MarkerPath = Join-Path $Path '.cursor-halo-install.json'
        if ((Test-Path -LiteralPath $MarkerPath) -and -not ((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $Marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json
            if ($Marker.appId -eq $ExpectedId) { Remove-Item -LiteralPath $Path -Recurse -Force }
        }
    }
    if (Test-Path -LiteralPath $ShortcutPath) {
        $Shell = New-Object -ComObject WScript.Shell
        $Shortcut = $Shell.CreateShortcut($ShortcutPath)
        if ([string]::Equals($Shortcut.TargetPath, (Join-Path $Destination 'CursorHalo.exe'), [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $ShortcutPath -Force
        }
    }
}
