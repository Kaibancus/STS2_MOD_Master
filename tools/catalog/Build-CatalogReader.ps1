#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repository 'tools\DevLaunch.psm1') -Force
$workspace = Split-Path -Parent $repository
$game = Assert-PhysicalDirectory (Join-Path $workspace 'game')
Assert-OfflineBaseline $game
$state = Join-Path $workspace 'report-data'
if (-not (Test-Path -LiteralPath $state)) { $null = New-Item -ItemType Directory -Path $state }
$null = Assert-PhysicalDirectory $state
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Command dotnet -CommandType Application).Source
$start.WorkingDirectory = $repository
$start.UseShellExecute = $false
foreach ($arg in @('build','tools\catalog\CatalogReader.csproj','-c','Release',
    '--no-incremental','--disable-build-servers','--verbosity','minimal',
    '-p:UseSharedCompilation=false','-p:ImportDirectoryBuildProps=false','-p:ImportDirectoryBuildTargets=false',
    "-p:GameReferenceDirectory=$(Join-Path $game 'data_sts2_windows_x86_64')")) { $start.ArgumentList.Add($arg) }
foreach ($item in @{
    DOTNET_CLI_HOME = (Join-Path $state 'cli-home')
    DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
    DOTNET_NOLOGO = '1'
    DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
    MSBUILDDISABLENODEREUSE = '1'
}.GetEnumerator()) { $start.Environment[$item.Key] = $item.Value }
$process = [Diagnostics.Process]::Start($start)
try {
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Catalog reader build failed: $($process.ExitCode)" }
}
finally { $process.Dispose() }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'sts2_catalog_reader.json') `
    -Destination (Join-Path $repository 'artifacts\catalog-reader\sts2_catalog_reader.json')
Get-ChildItem -LiteralPath (Join-Path $repository 'artifacts\catalog-reader') -File |
    ForEach-Object { [pscustomobject]@{ Name=$_.Name; Bytes=$_.Length; Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash } }
