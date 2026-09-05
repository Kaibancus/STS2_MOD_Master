#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Launch,
    [ValidatePattern('^[a-z][a-z0-9-]{0,31}$')][string]$Slot = 'main',
    [ValidateRange(0, 120)][int]$ProbeSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevLaunch.psm1') -Force
$repository = Split-Path -Parent $PSScriptRoot
$layout = Get-OfflineLayout -RepositoryRoot $repository -Slot $Slot
Assert-OfflineEnvironment
$start = New-OfflineStartInfo -GameRoot $layout.Game -ProfileRoot $layout.Profile -Headless:($ProbeSeconds -gt 0)
if (-not $Launch) {
    Assert-OfflineBaseline $layout.Game
    [pscustomobject]@{
        Status = 'Preflight only; no files created or game started'
        Executable = $start.FileName
        Arguments = $start.Arguments
        AppData = $start.EnvironmentVariables['APPDATA']
        LocalAppData = $start.EnvironmentVariables['LOCALAPPDATA']
        TemporaryData = $start.EnvironmentVariables['TEMP']
    }
    return
}

$mutex = New-OfflineMutex
$game = [Diagnostics.Process]::new()
$started = $false
try {
    $layout = Get-OfflineLayout -RepositoryRoot $repository -Slot $Slot
    Assert-OfflineEnvironment
    Assert-OfflineBaseline $layout.Game
    Initialize-OfflineRoot $layout
    if ($ProbeSeconds -gt 0) {
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
    }
    $game.StartInfo = $start
    if (-not $game.Start()) { throw 'Game process could not be started.' }
    $started = $true
    Write-Output "Offline game PID $($game.Id). Independent data: $($layout.Profile)"
    if ($ProbeSeconds -gt 0) {
        $stdout = $game.StandardOutput.ReadToEndAsync()
        $stderr = $game.StandardError.ReadToEndAsync()
        $stopped = -not $game.WaitForExit($ProbeSeconds * 1000)
        if ($stopped) { Stop-Process -Id $game.Id -ErrorAction Stop }
        $game.WaitForExit()
        $run = Join-Path $layout.Profile ('diagnostics\' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $run
        [IO.File]::WriteAllText((Join-Path $run 'stdout.log'), $stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $run 'stderr.log'), $stderr.GetAwaiter().GetResult())
        [pscustomobject]@{ ExitCode = $game.ExitCode; BoundedStop = $stopped; EvidenceDirectory = $run }
        if (-not $stopped -and $game.ExitCode -ne 0) { throw 'Game initialization exited with an error; inspect the private logs.' }
    }
    else {
        $game.WaitForExit()
        if ($game.ExitCode -ne 0) { throw "Game exited with code $($game.ExitCode)." }
    }
}
finally {
    if ($started -and -not $game.HasExited) {
        Stop-Process -Id $game.Id -ErrorAction Stop
        $game.WaitForExit()
    }
    $game.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
