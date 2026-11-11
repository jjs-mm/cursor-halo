[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path -LiteralPath $Executable).Path
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$Report = Join-Path $OutputDirectory 'native-smoke.json'
$Screenshot = Join-Path $OutputDirectory 'settings.png'
foreach ($File in @($Report, $Screenshot)) {
    if (Test-Path -LiteralPath $File) { Remove-Item -LiteralPath $File -Force }
}
$Arguments = '--smoke-test --smoke-test-output "{0}" --screenshot "{1}"' -f $Report, $Screenshot
$Process = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru
if (-not $Process.WaitForExit(30000)) {
    $Process.Kill()
    throw 'Native smoke process exceeded 30 seconds.'
}
$Process.Refresh()
if ($Process.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $Report) { Get-Content -LiteralPath $Report | Write-Host }
    throw "Native check failed with exit code $($Process.ExitCode)."
}
if (-not (Test-Path -LiteralPath $Report -PathType Leaf)) { throw 'Native smoke report is missing.' }
$Result = Get-Content -LiteralPath $Report -Raw | ConvertFrom-Json
if (-not $Result.success) { throw "Native smoke check failed: $($Result.error)" }
$Result | ConvertTo-Json -Depth 8 | Write-Host
if (-not (Test-Path -LiteralPath $Screenshot -PathType Leaf)) { throw 'Settings screenshot is missing.' }
Write-Host "Native checks and isolated settings screenshot: $OutputDirectory"
