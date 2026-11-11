[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$env:DOTNET_CLI_HOME = Join-Path $ProjectRoot '.build/dotnet-home'
$env:NUGET_PACKAGES = Join-Path $ProjectRoot '.build/nuget'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
& dotnet run --project (Join-Path $ProjectRoot 'windows/CursorHalo.Tests') -c Release
if ($LASTEXITCODE -ne 0) { throw "Tests failed with exit code $LASTEXITCODE." }
