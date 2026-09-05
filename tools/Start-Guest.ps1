#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$RunId,
    [ValidateSet('Boundary', 'StorageProbe', 'Play')][string]$Mode,
    [ValidateRange(5, 300)][int]$ProbeSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$guestVerified = $false
$runDirectory = "C:\Sts2Data\control\$RunId"
$result = [ordered]@{ RunId = $RunId; Mode = $Mode; Status = 'Failed'; Error = $null }

try {
    if ($env:USERNAME -cne 'WDAGUtilityAccount' -or
        (Get-CimInstance Win32_ComputerSystem).Model -notlike '*Virtual Machine*' -or
        $PSScriptRoot -ine $runDirectory -or
        -not (Test-Path -LiteralPath $runDirectory -PathType Container) -or
        -not (Test-Path -LiteralPath 'C:\Sts2Game' -PathType Container)) {
        throw 'This script is guest-only and must run through the protected Sandbox launcher.'
    }
    $guestVerified = $true
    if (@(Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object IPEnabled).Count -ne 0) {
        throw 'An IP-enabled guest adapter exists; refusing to launch.'
    }
    if (@(Get-Process | Where-Object ProcessName -Like 'steam*').Count -ne 0 -or
        (Test-Path -LiteralPath 'C:\Program Files (x86)\Steam') -or
        (Test-Path -LiteralPath 'C:\Program Files\Steam')) {
        throw 'Steam is present in the guest; this offline boundary must not receive a host Steam client or identity.'
    }
    $probeFile = "C:\Sts2Game\.read-only-probe-$RunId"
    $readOnly = $false
    try {
        $stream = [IO.File]::Open($probeFile, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        $stream.Dispose()
    }
    catch [UnauthorizedAccessException] { $readOnly = $true }
    catch [IO.IOException] {
        if (($_.Exception.HResult -band 0xffff) -notin @(5, 19)) { throw }
        $readOnly = $true
    }
    if (-not $readOnly) {
        Remove-Item -LiteralPath $probeFile
        throw 'The game mapping is writable; refusing to launch.'
    }
    $result.GameMappingReadOnly = $true
    $result.IpEnabledAdapters = 0
    $result.SteamPresent = $false
    [IO.File]::WriteAllText((Join-Path $runDirectory 'guest-write.txt'), $RunId)
    if ($Mode -eq 'Play') {
        throw 'Sandbox is not the default play workflow; this guest is for explicit probes only.'
    }
    if ($Mode -eq 'StorageProbe') {
        $root = 'C:\Sts2Data\offline-probe\v0.111.0-41cef1ea'
        $routedRoot = Join-Path $root 'roaming\SlayTheSpire2'
        $beforeSaves = @()
        if (Test-Path -LiteralPath $routedRoot) {
            $beforeSaves = @(Get-ChildItem -LiteralPath $routedRoot -Recurse -File -Filter '*.save')
        }
        $result.BeforeSaveFiles = @($beforeSaves | ForEach-Object {
            [ordered]@{
                RelativePath = $_.FullName.Substring($routedRoot.Length + 1)
                Bytes = $_.Length
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
        foreach ($name in @('roaming', 'local', 'temp')) {
            $path = Join-Path $root $name
            if (-not (Test-Path -LiteralPath $path)) {
                $null = New-Item -ItemType Directory -Path $path
            }
        }
        $normalGuestData = Join-Path $env:APPDATA 'SlayTheSpire2'
        if (Test-Path -LiteralPath $normalGuestData) {
            throw 'The disposable guest already has game data; do not confuse it with the routed probe.'
        }
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = 'C:\Sts2Game\SlayTheSpire2.exe'
        $start.WorkingDirectory = 'C:\Sts2Game'
        $start.Arguments = '--headless --force-steam=off'
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.EnvironmentVariables['APPDATA'] = Join-Path $root 'roaming'
        $start.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $root 'local'
        $start.EnvironmentVariables['TEMP'] = Join-Path $root 'temp'
        $start.EnvironmentVariables['TMP'] = Join-Path $root 'temp'
        $game = [Diagnostics.Process]::new()
        $game.StartInfo = $start
        $gameStarted = $false
        try {
            if (-not $game.Start()) { throw 'The game process did not start.' }
            $gameStarted = $true
            $stdout = $game.StandardOutput.ReadToEndAsync()
            $stderr = $game.StandardError.ReadToEndAsync()
            $result.GameProcessId = $game.Id
            $result.BoundedStop = -not $game.WaitForExit($ProbeSeconds * 1000)
            if ($result.BoundedStop) { Stop-Process -Id $game.Id -ErrorAction Stop }
            $game.WaitForExit()
            $result.GameExitCode = $game.ExitCode
            $output = $stdout.GetAwaiter().GetResult()
            $errors = $stderr.GetAwaiter().GetResult()
            [IO.File]::WriteAllText((Join-Path $runDirectory 'game.stdout.log'), $output)
            [IO.File]::WriteAllText((Join-Path $runDirectory 'game.stderr.log'), $errors)
        }
        finally {
            if ($gameStarted -and -not $game.HasExited) {
                Stop-Process -Id $game.Id -ErrorAction Stop
                $game.WaitForExit()
            }
            $game.Dispose()
        }
        $saves = @()
        if (Test-Path -LiteralPath $routedRoot) {
            $saves = @(Get-ChildItem -LiteralPath $routedRoot -Recurse -File -Filter '*.save')
        }
        $result.RoutedSaveFiles = @($saves | ForEach-Object {
            [ordered]@{
                RelativePath = $_.FullName.Substring($routedRoot.Length + 1)
                Bytes = $_.Length
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
        $result.OriginalGuestDataCreated = Test-Path -LiteralPath $normalGuestData
        $result.SteamSkipObserved = ($output + $errors).Contains('Steam initialization skipped')
        $result.CloudStoreObserved = ($output + $errors).Contains('Steam is enabled, we will write saves to steam storage')
        $result.MainMenuObserved = ($output + $errors).Contains('[Startup] Time to main menu')
        if ($saves.Count -eq 0 -or $result.OriginalGuestDataCreated -or
            -not $result.SteamSkipObserved -or $result.CloudStoreObserved -or -not $result.MainMenuObserved) {
            throw 'Actual game storage routing evidence is incomplete or disagrees with the intended offline path. Inspect private logs.'
        }
    }
    $result.Status = 'Passed'
}
catch {
    $result.Error = $_.Exception.Message
    throw
}
finally {
    if ($guestVerified) {
        $temporary = Join-Path $runDirectory 'result.pending'
        [IO.File]::WriteAllText($temporary, ($result | ConvertTo-Json -Depth 5),
            [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination (Join-Path $runDirectory 'result.json')
        & "$env:WINDIR\System32\shutdown.exe" /s /t 0
    }
}
