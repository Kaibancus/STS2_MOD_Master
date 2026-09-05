#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'DevLaunch.psm1') -Force
$passed = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:passed++
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Expected)
    $errorText = $null
    try { & $Action | Out-Null }
    catch { $errorText = $_.Exception.Message }
    if ($null -eq $errorText -or $errorText -notlike "*$Expected*") {
        throw "Expected rejection '$Expected', got '$errorText'."
    }
    $script:passed++
}

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('sts2-launcher-check-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $temporary
try {
    $repo = Join-Path $temporary 'mod'
    $game = Join-Path $temporary 'game'
    $data = Join-Path $temporary 'dev-data'
    $null = New-Item -ItemType Directory -Path $repo, $game
    [IO.File]::WriteAllText((Join-Path $game 'own-fixture.txt'), 'original test fixture, not game data')
    $layout = Get-DevSandboxLayout $repo
    Assert-True ($layout.Game -ceq $game -and $layout.Data -ceq $data) 'Unexpected sibling layout.'
    Assert-True (-not (Test-Path -LiteralPath $data)) 'Preflight created persistent data.'
    Assert-Rejected { Assert-PhysicalDirectory '\\server\share' } 'local, absolute'
    Assert-Rejected { Assert-PhysicalDirectory 'C:\' } 'drive root'
    Assert-Rejected { Assert-PhysicalDirectory (Join-Path $temporary '%APPDATA%') } 'expansion'
    Assert-Rejected { Assert-GameBaseline $game } 'Required sts2.dll is missing'
    $assemblyDirectory = Join-Path $game 'data_sts2_windows_x86_64'
    $null = New-Item -ItemType Directory -Path $assemblyDirectory
    [IO.File]::WriteAllText((Join-Path $assemblyDirectory 'sts2.dll'), 'not a game assembly')
    Assert-Rejected { Assert-GameBaseline $game } 'Unsupported sts2.dll fingerprint'

    $runId = '0123456789abcdef0123456789abcdef'
    $xml = [xml](New-DevSandboxXml -GameRoot "$game & safe" -DataRoot $data -RunId $runId -Mode Boundary)
    Assert-True ($xml.Configuration.MappedFolders.MappedFolder.Count -eq 2) 'Unexpected extra mapping.'
    Assert-True ($xml.Configuration.MappedFolders.MappedFolder[0].HostFolder -ceq "$game & safe") 'XML escaping failed.'
    Assert-True ($xml.Configuration.MappedFolders.MappedFolder[0].ReadOnly -ceq 'true') 'Game mapping is writable.'
    Assert-True ($xml.Configuration.MappedFolders.MappedFolder[1].ReadOnly -ceq 'false') 'Data persistence is disabled.'
    Assert-True ($xml.Configuration.MappedFolders.MappedFolder[1].SandboxFolder -ceq 'C:\Sts2Data') 'Wrong guest data path.'
    foreach ($setting in @('Networking', 'ClipboardRedirection', 'AudioInput', 'VideoInput', 'PrinterRedirection', 'vGPU')) {
        Assert-True ($xml.Configuration.$setting -ceq 'Disable') "Unsafe default: $setting"
    }
    Assert-True ($xml.Configuration.ProtectedClient -ceq 'Enable') 'ProtectedClient not enabled.'
    Assert-True ($xml.Configuration.LogonCommand.Command -like '*-Mode Boundary*') 'Wrong guest mode.'
    Assert-Rejected { New-DevSandboxXml -GameRoot $game -DataRoot $data -RunId '"; shutdown' } 'pattern'
    Assert-Rejected { Get-DevSandboxLayout $game } 'must be separate'

    $null = New-Item -ItemType Directory -Path $data
    Assert-Rejected { Get-DevSandboxLayout $repo } 'ownership marker'
    [IO.File]::WriteAllText((Join-Path $data '.sts2-sandbox'), 'unknown-version')
    Assert-Rejected { Get-DevSandboxLayout $repo } 'ownership marker'
    [IO.File]::WriteAllText((Join-Path $data '.sts2-sandbox'), 'sts2-sandbox-v1')
    $null = Get-DevSandboxLayout $repo
    $fixture = Join-Path $data 'own-fixture.txt'
    [IO.File]::WriteAllText($fixture, 'own persistent fixture')
    $null = New-Item -ItemType HardLink -Path (Join-Path $data 'linked.txt') -Target $fixture
    Assert-Rejected { Get-DevSandboxLayout $repo } 'hard links'
    Remove-Item -LiteralPath (Join-Path $data 'linked.txt')
    $junction = Join-Path $data 'junction'
    $null = New-Item -ItemType Junction -Path $junction -Target $repo
    Assert-Rejected { Get-DevSandboxLayout $repo } 'reparse points'
    [IO.Directory]::Delete($junction)
    $gameJunction = Join-Path $game 'junction'
    $null = New-Item -ItemType Junction -Path $gameJunction -Target $repo
    Assert-Rejected { Get-DevSandboxLayout $repo } 'reparse points'
    [IO.Directory]::Delete($gameJunction)
    $null = Get-DevSandboxLayout $repo
    Assert-True ([IO.File]::ReadAllText($fixture) -ceq 'own persistent fixture') 'Preflight modified development data.'

    $offline = Get-OfflineLayout -RepositoryRoot $repo
    Assert-True ($offline.Profile -ceq (Join-Path $temporary 'offline-data\v0.111.0-41cef1ea\main')) 'Wrong versioned offline root.'
    Assert-True (-not (Test-Path -LiteralPath $offline.Root)) 'Offline preflight created data.'
    Assert-Rejected { Get-OfflineLayout -RepositoryRoot $repo -Slot '..\backup' } 'pattern'
    Assert-Rejected { Get-OfflineLayout -RepositoryRoot $repo -Slot 'con' } 'Reserved'
    $appData = $env:APPDATA
    $localAppData = $env:LOCALAPPDATA
    $tempData = $env:TEMP
    try {
        $env:APPDATA = Join-Path $offline.Root 'source-roaming'
        Assert-Rejected { Get-OfflineLayout $repo } 'overlaps a protected'
    }
    finally { $env:APPDATA = $appData }
    $start = New-OfflineStartInfo -GameRoot $game -ProfileRoot $offline.Profile
    Assert-True ($start.Arguments -ceq '--force-steam=off') 'Offline args are not fixed.'
    Assert-True (-not $start.UseShellExecute) 'Offline launch must supply a child-only environment.'
    Assert-True ($start.EnvironmentVariables['APPDATA'] -ceq (Join-Path $offline.Profile 'roaming')) 'APPDATA was not redirected.'
    Assert-True ($start.EnvironmentVariables['LOCALAPPDATA'] -ceq (Join-Path $offline.Profile 'local')) 'LOCALAPPDATA was not redirected.'
    Assert-True ($start.EnvironmentVariables['TEMP'] -ceq (Join-Path $offline.Profile 'temp')) 'TEMP was not redirected.'
    Assert-True ($start.EnvironmentVariables['TMP'] -ceq $start.EnvironmentVariables['TEMP']) 'TMP differs from TEMP.'
    Assert-True ($env:APPDATA -ceq $appData -and $env:LOCALAPPDATA -ceq $localAppData -and $env:TEMP -ceq $tempData) 'Parent environment changed.'
    $probe = New-OfflineStartInfo -GameRoot $game -ProfileRoot $offline.Profile -Headless
    Assert-True ($probe.Arguments -ceq '--headless --force-steam=off') 'Probe arguments are wrong.'
    $fingerprint = Get-GameFingerprint $game
    [IO.File]::WriteAllText((Join-Path $game 'override.cfg'), 'own override test')
    $extra = Get-GameFingerprint $game
    Assert-True ($extra.FileCount -eq ($fingerprint.FileCount + 1) -and $extra.Sha256 -cne $fingerprint.Sha256) 'Extra settings file escaped the inventory.'
    Remove-Item -LiteralPath (Join-Path $game 'override.cfg')
    [IO.File]::WriteAllText((Join-Path $game 'own-fixture.txt'), 'changed fixture')
    Assert-True ((Get-GameFingerprint $game).Sha256 -cne $fingerprint.Sha256) 'Changed runtime input escaped the inventory.'
    $null = New-Item -ItemType Directory -Path $offline.Root
    Assert-Rejected { Get-OfflineLayout $repo } 'not an owned offline runtime root'
    [IO.File]::WriteAllText((Join-Path $offline.Root '.sts2-offline'), 'sts2-offline-v1')
    $null = New-Item -ItemType HardLink -Path (Join-Path $offline.Root 'linked.txt') -Target $fixture
    Assert-Rejected { Get-OfflineLayout $repo } 'hard links'
    Remove-Item -LiteralPath (Join-Path $offline.Root 'linked.txt')
    $null = New-Item -ItemType Junction -Path (Join-Path $offline.Root 'redirected') -Target $repo
    Assert-Rejected { Get-OfflineLayout $repo } 'reparse points'
    [IO.Directory]::Delete((Join-Path $offline.Root 'redirected'))
    $oldHook = [Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('DOTNET_STARTUP_HOOKS', 'own-test-hook', 'Process')
        Assert-Rejected { Assert-OfflineEnvironment } 'Unexpected runtime injection'
    }
    finally { [Environment]::SetEnvironmentVariable('DOTNET_STARTUP_HOOKS', $oldHook, 'Process') }
    $mutex = New-OfflineMutex
    try {
        $modulePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'DevLaunch.psm1').Replace("'", "''")
        $childCommand = "Import-Module '$modulePath'; try { `$m = New-OfflineMutex; `$m.ReleaseMutex(); `$m.Dispose(); exit 1 } catch { if (`$_.Exception.Message -notlike '*Another offline launcher*') { throw }; exit 0 }"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
        & (Get-Process -Id $PID).Path -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded
        Assert-True ($LASTEXITCODE -eq 0) 'Concurrent offline launcher was not rejected.'
    }
    finally { $mutex.ReleaseMutex(); $mutex.Dispose() }

    foreach ($file in Get-ChildItem -LiteralPath (Split-Path -Parent $PSScriptRoot) -Recurse -File -Include '*.ps1', '*.psm1') {
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        Assert-True ($parseErrors.Count -eq 0) "Parser errors in $($file.Name): $parseErrors"
    }
    Write-Output "$passed launcher checks passed. No Sandbox, game, source save, or Steam operation was performed."
}
finally {
    # Only this uniquely created fixture tree is removed; never traverse a test junction.
    foreach ($path in @((Join-Path $data 'junction'), (Join-Path $game 'junction'),
        (Join-Path $temporary 'offline-data\redirected'))) {
        if (Test-Path -LiteralPath $path) { [IO.Directory]::Delete($path) }
    }
    Remove-Item -LiteralPath $temporary -Recurse
}
