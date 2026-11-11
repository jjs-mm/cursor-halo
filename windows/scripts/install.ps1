[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'This installer requires Windows.' }
$ExpectedId = 'local.personal.CursorHalo'
$Source = Join-Path $PSScriptRoot 'app'
$ManifestPath = Join-Path $PSScriptRoot 'package-manifest.json'
$SourceExe = Join-Path $Source 'CursorHalo.exe'
if (-not (Test-Path -LiteralPath $SourceExe -PathType Leaf)) { throw 'Extract the entire release ZIP before running this installer.' }
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($Manifest.schemaVersion -ne 1 -or $Manifest.appId -ne $ExpectedId) { throw 'Unrecognized Cursor Halo package manifest.' }
$ActualHash = (Get-FileHash -LiteralPath $SourceExe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualHash -ne $Manifest.executableSha256) { throw 'The executable does not match its package manifest. Download the release again.' }
$Links = @(Get-ChildItem -LiteralPath $Source -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
if ($Links.Count -ne 0) { throw 'The package must not contain symbolic links or junctions.' }
if (@(Get-Process -Name CursorHalo -ErrorAction SilentlyContinue).Count -ne 0) { throw 'Quit Cursor Halo before installing this update.' }

$Programs = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs'
$Destination = Join-Path $Programs 'Cursor Halo'
$DestinationExe = Join-Path $Destination 'CursorHalo.exe'
$StartMenu = [Environment]::GetFolderPath('Programs')
$ShortcutPath = Join-Path $StartMenu 'Cursor Halo.lnk'
$Shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $ShortcutPath) {
    $ExistingShortcut = $Shell.CreateShortcut($ShortcutPath)
    if (-not [string]::Equals($ExistingShortcut.TargetPath, $DestinationExe, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An unrelated Start menu shortcut named Cursor Halo already exists.'
    }
}
if (Test-Path -LiteralPath $Destination) {
    if ((Get-Item -LiteralPath $Destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing to replace a symbolic link or junction.'
    }
    $Marker = Join-Path $Destination '.cursor-halo-install.json'
    if (-not (Test-Path -LiteralPath $Marker -PathType Leaf)) { throw 'The destination is not an installation managed by this installer.' }
    $Installed = Get-Content -LiteralPath $Marker -Raw | ConvertFrom-Json
    if ($Installed.appId -ne $ExpectedId) { throw 'The destination belongs to another application.' }
}
New-Item -ItemType Directory -Path $Programs -Force | Out-Null
New-Item -ItemType Directory -Path $StartMenu -Force | Out-Null
$Nonce = [Guid]::NewGuid().ToString('N')
$StagingRoot = Join-Path $Programs ".cursor-halo-install-$Nonce"
$StagedApp = Join-Path $StagingRoot 'app'
$Backup = $null
$Placed = $false
New-Item -ItemType Directory -Path $StagingRoot | Out-Null
try {
    Copy-Item -LiteralPath $Source -Destination $StagedApp -Recurse
    $MarkerData = @{ appId = $ExpectedId; version = $Manifest.version } | ConvertTo-Json
    [IO.File]::WriteAllText((Join-Path $StagedApp '.cursor-halo-install.json'), $MarkerData, ([System.Text.UTF8Encoding]::new($false)))
    if (Test-Path -LiteralPath $Destination) {
        $Backup = Join-Path $Programs "Cursor Halo.backup-$Nonce"
        Move-Item -LiteralPath $Destination -Destination $Backup
    }
    Move-Item -LiteralPath $StagedApp -Destination $Destination
    $Placed = $true
    $InstalledHash = (Get-FileHash -LiteralPath $DestinationExe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($InstalledHash -ne $Manifest.executableSha256) { throw 'Installed executable verification failed.' }
    $StagedShortcut = Join-Path $StagingRoot 'Cursor Halo.lnk'
    $Shortcut = $Shell.CreateShortcut($StagedShortcut)
    $Shortcut.TargetPath = $DestinationExe
    $Shortcut.WorkingDirectory = $Destination
    $Shortcut.Description = 'Cursor Halo'
    $Shortcut.Save()
    Move-Item -LiteralPath $StagedShortcut -Destination $ShortcutPath -Force
}
catch {
    if ($Placed -and (Test-Path -LiteralPath $Destination)) {
        Move-Item -LiteralPath $Destination -Destination (Join-Path $StagingRoot 'failed')
    }
    if ($Backup -and (Test-Path -LiteralPath $Backup) -and -not (Test-Path -LiteralPath $Destination)) {
        Move-Item -LiteralPath $Backup -Destination $Destination
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force }
}
Write-Host "Installed: $Destination"
Write-Host "Start menu shortcut: $ShortcutPath"
if ($Backup) {
    Write-Host "Previous build preserved: $Backup"
    Write-Host 'To roll back, quit Cursor Halo, move the new folder aside, and rename the backup to Cursor Halo.'
}
Write-Host 'Launch at login was not changed. Start Cursor Halo from the Start menu.'
