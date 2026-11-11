[CmdletBinding()]
param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Version = (Get-Content -LiteralPath (Join-Path $ProjectRoot 'VERSION') -Raw).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid VERSION file.' }
$BuildRoot = Join-Path $ProjectRoot '.build'
$DistRoot = Join-Path $ProjectRoot 'dist'
$PublishRoot = Join-Path $DistRoot "windows/$Runtime/app"
$StageRoot = Join-Path $BuildRoot "package-windows/$Runtime"
$env:DOTNET_CLI_HOME = Join-Path $BuildRoot 'dotnet-home'
$env:NUGET_PACKAGES = Join-Path $BuildRoot 'nuget'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
foreach ($Path in @($PublishRoot, $StageRoot)) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}
$Project = Join-Path $ProjectRoot 'windows/CursorHalo/CursorHalo.csproj'
& dotnet publish $Project -c Release -r $Runtime --self-contained true --output $PublishRoot "-p:Version=$Version" -p:PublishSingleFile=true -p:PublishTrimmed=false -p:DebugType=None -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE." }
$Executable = Join-Path $PublishRoot 'CursorHalo.exe'
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Published executable is missing.' }
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'LICENSE') -Destination (Join-Path $PublishRoot 'LICENSE')
$RuntimePacks = @(& (Join-Path $PSScriptRoot 'copy-runtime-notices.ps1') -Project $Project -Runtime $Runtime -Destination $PublishRoot)
Copy-Item -LiteralPath $PublishRoot -Destination (Join-Path $StageRoot 'app') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install.ps1') -Destination (Join-Path $StageRoot 'Install-CursorHalo.ps1')
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'LICENSE') -Destination (Join-Path $StageRoot 'LICENSE')
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'README.md') -Destination (Join-Path $StageRoot 'README.md')
foreach ($Document in @('CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md')) {
    Copy-Item -LiteralPath (Join-Path $ProjectRoot $Document) -Destination (Join-Path $StageRoot $Document)
}
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'docs') -Destination (Join-Path $StageRoot 'docs') -Recurse
$Manifest = @{
    schemaVersion = 1
    appId = 'local.personal.CursorHalo'
    version = $Version
    runtime = $Runtime
    runtimePacks = $RuntimePacks
    executableSha256 = (Get-FileHash -LiteralPath $Executable -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json -Depth 6
$Utf8 = [System.Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $StageRoot 'package-manifest.json'), $Manifest, $Utf8)
$ArchiveName = "CursorHalo-$Version-$Runtime.zip"
$Archive = Join-Path $DistRoot $ArchiveName
Compress-Archive -Path (Join-Path $StageRoot '*') -DestinationPath $Archive -CompressionLevel Optimal -Force
$Hash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$Archive.sha256", "$Hash  $ArchiveName" + [Environment]::NewLine, $Utf8)
Write-Host "Packaged: $Archive"
Write-Host 'Windows executable is unsigned. No login item or installed copy was changed.'
