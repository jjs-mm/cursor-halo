[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][ValidateSet('win-x64', 'win-arm64')][string]$Runtime,
    [Parameter(Mandatory = $true)][string]$Destination
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Query the SDK's resolved packs after publish, rather than guessing a framework
# version from the SDK version or taking notices from an unrelated installation.
$Raw = & dotnet msbuild $Project -nologo -target:ResolveFrameworkReferences -getItem:ResolvedRuntimePack "-p:RuntimeIdentifier=$Runtime" -p:SelfContained=true -p:PublishSingleFile=true
if ($LASTEXITCODE -ne 0) { throw 'Could not resolve runtime packs for redistribution notices.' }
$Resolved = ($Raw -join [Environment]::NewLine) | ConvertFrom-Json
$Packs = @($Resolved.Items.ResolvedRuntimePack)
$Expected = @("Microsoft.NETCore.App.Runtime.$Runtime", "Microsoft.WindowsDesktop.App.Runtime.$Runtime")
foreach ($Id in $Expected) {
    if (@($Packs | Where-Object { $_.NuGetPackageId -eq $Id }).Count -ne 1) {
        throw "Expected exactly one resolved runtime pack: $Id"
    }
}
foreach ($Pack in $Packs) {
    $Id = [string]$Pack.NuGetPackageId
    $Version = [string]$Pack.NuGetPackageVersion
    if ($Id -notmatch '^[A-Za-z0-9.-]+$' -or $Version -notmatch '^[0-9A-Za-z.+-]+$') {
        throw 'Unexpected runtime pack identity.'
    }
    $PackRoot = [string]$Pack.PackageDirectory
    if (-not (Test-Path -LiteralPath $PackRoot -PathType Container)) { throw "Runtime pack directory is missing: $Id $Version" }
    $Files = @(Get-ChildItem -LiteralPath $PackRoot -File | Where-Object {
        $_.Name -match '^LICENSE(?:\.TXT)?$' -or $_.Name -match '^THIRD[-_ ]?PARTY.*' -or $_.Name -match '^ThirdPartyNotices.*'
    })
    if (@($Files | Where-Object { $_.Name -match '^LICENSE(?:\.TXT)?$' }).Count -eq 0) {
        throw "Runtime license is missing: $Id $Version"
    }
    $NoticeDirectory = Join-Path $Destination "notices/$Id-$Version"
    New-Item -ItemType Directory -Path $NoticeDirectory -Force | Out-Null
    foreach ($File in $Files) { Copy-Item -LiteralPath $File.FullName -Destination $NoticeDirectory }
    $NoticeNames = @($Files.Name)
    $Sources = @()
    if (@($Files | Where-Object { $_.Name -match '^THIRD[-_ ]?PARTY.*' -or $_.Name -match '^ThirdPartyNotices.*' }).Count -eq 0) {
        # WindowsDesktop 10.0.12 ships LICENSE but omits its notices. Read
        # WinForms/WPF notices from the exact repository commit in its NuSpec.
        if (-not $Id.StartsWith('Microsoft.WindowsDesktop.App.Runtime.', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Runtime third-party notices are missing: $Id $Version"
        }
        $NuSpecPath = Join-Path $PackRoot ($Id.ToLowerInvariant() + '.nuspec')
        [xml]$NuSpec = Get-Content -LiteralPath $NuSpecPath -Raw
        $Repository = $NuSpec.package.metadata.repository
        $Commit = [string]$Repository.commit
        if ($Repository.url -ne 'https://github.com/dotnet/dotnet' -or $Commit -notmatch '^[0-9a-f]{40}$') {
            throw "Cannot identify the exact Microsoft source revision for $Id $Version."
        }
        foreach ($Component in @('winforms', 'wpf')) {
            $Name = "$Component-THIRD-PARTY-NOTICES.TXT"
            $Url = "https://raw.githubusercontent.com/dotnet/dotnet/$Commit/src/$Component/THIRD-PARTY-NOTICES.TXT"
            Invoke-WebRequest -Uri $Url -OutFile (Join-Path $NoticeDirectory $Name) -UseBasicParsing -TimeoutSec 30
            $NoticeNames += $Name
            $Sources += [PSCustomObject]@{ file = $Name; url = $Url; commit = $Commit }
        }
        $Provenance = $Sources | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText((Join-Path $NoticeDirectory 'notice-sources.json'), $Provenance, ([System.Text.UTF8Encoding]::new($false)))
        $NoticeNames += 'notice-sources.json'
    }
    Write-Host "Included redistribution notices: $Id $Version"
    [PSCustomObject]@{ id = $Id; version = $Version; notices = $NoticeNames }
}
