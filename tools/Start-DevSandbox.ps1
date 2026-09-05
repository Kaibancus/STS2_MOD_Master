#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Launch,
    [ValidateSet('Boundary', 'StorageProbe', 'Play')][string]$Mode = 'Play',
    [ValidateRange(5, 300)][int]$ProbeSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevLaunch.psm1') -Force

$layout = Get-DevSandboxLayout -RepositoryRoot (Split-Path -Parent $PSScriptRoot)
Assert-GameBaseline -GameRoot $layout.Game
Assert-SandboxCapability
$runId = [Guid]::NewGuid().ToString('N')
$xml = New-DevSandboxXml -GameRoot $layout.Game -DataRoot $layout.Data `
    -RunId $runId -Mode $Mode -ProbeSeconds $ProbeSeconds

if (-not $Launch) {
    Write-Output 'Preflight only. No directories created and no Sandbox/game launched.'
    Write-Output $xml
    return
}
if ($Mode -eq 'Play') {
    throw 'Sandbox is not the default play workflow. Only explicit boundary or native-storage probes are available.'
}

foreach ($path in @($layout.Control, $layout.Data)) {
    if (-not (Test-Path -LiteralPath $path)) {
        $null = New-Item -ItemType Directory -Path $path
        [IO.File]::WriteAllText((Join-Path $path '.sts2-sandbox'), 'sts2-sandbox-v1')
    }
}
$hasher = [Security.Cryptography.SHA256]::Create()
try {
    $name = [BitConverter]::ToString($hasher.ComputeHash(
        [Text.Encoding]::UTF8.GetBytes($layout.Data.ToUpperInvariant()))).Replace('-', '')
}
finally { $hasher.Dispose() }
$lock = [Threading.Mutex]::new($false, "Local\STS2DevSandbox-$name")
$ownsLock = $false
$sandbox = $null
try {
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] {
        $lock.ReleaseMutex()
        throw 'A previous launcher terminated unexpectedly. Inspect the Sandbox before trying again.'
    }
    if (-not $ownsLock) { throw 'Another launcher owns this persistent development data.' }
    # Recheck after claiming the lock; never reuse a guest-writable launch configuration.
    $layout = Get-DevSandboxLayout -RepositoryRoot (Split-Path -Parent $PSScriptRoot)
    Assert-SandboxCapability
    $runDirectory = Join-Path $layout.Data "control\$runId"
    $null = New-Item -ItemType Directory -Path $runDirectory
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-Guest.ps1') `
        -Destination (Join-Path $runDirectory 'Start-Guest.ps1')
    $configuration = Join-Path $layout.Control "$runId.wsb"
    [IO.File]::WriteAllText($configuration, $xml, [Text.UTF8Encoding]::new($false))
    $sandbox = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsSandbox.exe') `
        -ArgumentList ('"{0}"' -f $configuration) -PassThru
    Write-Output "Started Windows Sandbox launcher PID $($sandbox.Id); private run ID $runId."

    $resultPath = Join-Path $runDirectory 'result.json'
    $deadline = [DateTime]::UtcNow.AddSeconds(180 + $ProbeSeconds)
    while (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $deadline) {
            if (-not $sandbox.HasExited) { Stop-Process -Id $sandbox.Id -ErrorAction Stop }
            throw 'No guest result within the bounded wait. No host game fallback is allowed; inspect the Sandbox window.'
        }
        Start-Sleep -Seconds 2
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.RunId -cne $runId -or $result.Status -cne 'Passed') {
        throw "Guest probe failed. Inspect the private result in: $runDirectory"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $runDirectory 'guest-write.txt') -PathType Leaf) -or
        [IO.File]::ReadAllText((Join-Path $runDirectory 'guest-write.txt')) -cne $runId) {
        throw 'The guest persistence sentinel did not reach the dedicated host data mapping.'
    }
    Write-Output "Guest $Mode probe passed. Evidence remains outside Git in $runDirectory."
}
finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
