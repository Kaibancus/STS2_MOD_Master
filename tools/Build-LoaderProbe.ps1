#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevLaunch.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'LoaderProbe.psm1') -Force
$layout = Get-LoaderProbeLayout (Split-Path -Parent $PSScriptRoot)
$mutex = New-OfflineMutex
try {
    Assert-OfflineEnvironment
    Assert-OfflineBaseline $layout.Game
    if (Test-Path -LiteralPath $layout.DeploymentReceipt) {
        throw 'Remove the verified deployment before rebuilding; build never changes deployed trust.'
    }
    Initialize-LoaderProbeState $layout
    if (Test-Path -LiteralPath $layout.Artifacts) {
        $files = @(Get-PhysicalTree $layout.Artifacts)
        Assert-SingleLinkFiles -Files $files
        if (@($files | Where-Object Name -NotIn @('sts2modmaster_loader_probe.dll','sts2modmaster_loader_probe.json')).Count -gt 0) {
            throw 'Unexpected build output files; no cleanup or overwrite will be attempted.'
        }
    }
    if (Test-Path -LiteralPath $layout.BuildReceipt) {
        $null = Read-LoaderProbeReceipt -Path $layout.BuildReceipt -Layout $layout -Kind build
        Remove-Item -LiteralPath $layout.BuildReceipt
    }
    $cliHome = Join-Path $layout.State 'cli-home'
    if (-not (Test-Path -LiteralPath $cliHome)) { $null = New-Item -ItemType Directory -Path $cliHome }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Get-Command dotnet -CommandType Application).Source
    $start.WorkingDirectory = $layout.Repository
    $start.UseShellExecute = $false
    foreach ($argument in @('build','src\NativeLoaderProbe\NativeLoaderProbe.csproj',
        '--configuration','Release','--no-dependencies','--no-incremental','--disable-build-servers','--verbosity','minimal',
        '-p:UseSharedCompilation=false','-p:ImportDirectoryBuildProps=false','-p:ImportDirectoryBuildTargets=false')) {
        $start.ArgumentList.Add($argument)
    }
    $start.ArgumentList.Add("-p:GameReferenceDirectory=$(Join-Path $layout.Game 'data_sts2_windows_x86_64')")
    foreach ($entry in @{
        DOTNET_CLI_HOME = $cliHome
        DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
        DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
        DOTNET_NOLOGO = '1'
        DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
        DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE = 'true'
        MSBUILDDISABLENODEREUSE = '1'
        NUGET_PACKAGES = (Join-Path $layout.State 'packages')
    }.GetEnumerator()) { $start.Environment[$entry.Key] = $entry.Value }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $sourceBefore = Get-LoaderProbeSourceFingerprint $layout.Repository
    $buildStarted = $false
    try {
        if (-not $process.Start()) { throw 'The pinned SDK build could not start.' }
        $buildStarted = $true
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Probe build failed with exit $($process.ExitCode); no receipt was issued." }
    }
    finally {
        if ($buildStarted -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -ErrorAction Stop
            $process.WaitForExit()
        }
        $process.Dispose()
    }
    Copy-Item -LiteralPath (Join-Path $layout.Repository 'src\NativeLoaderProbe\sts2modmaster_loader_probe.json') `
        -Destination (Join-Path $layout.Artifacts 'sts2modmaster_loader_probe.json')
    Assert-LoaderProbeSourceUnchanged -RepositoryRoot $layout.Repository -ExpectedFingerprint $sourceBefore
    $receipt = New-LoaderProbeReceipt -Layout $layout -SourceFingerprint $sourceBefore
    [IO.File]::WriteAllText($layout.BuildReceipt, ($receipt | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    $null = Assert-LoaderProbeBuild $layout
    Write-Output 'Built and packed only the own DLL/manifest. No deployment, consent change or game launch occurred.'
    $receipt.artifacts | Format-Table name,length,sha256 -AutoSize
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
