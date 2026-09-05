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

    $tools = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $tools 'LoaderProbe.psm1') -Force
    $id = 'sts2modmaster_loader_probe'
    foreach ($relative in @('global.json','NuGet.Config','src\NativeLoaderProbe\NativeLoaderProbe.csproj',
        'src\NativeLoaderProbe\LoaderProbe.cs','tools\Build-LoaderProbe.ps1')) {
        $path = Join-Path $repo $relative
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
        [IO.File]::WriteAllText($path, 'own fixture input')
    }
    $manifestSource = Join-Path $repo "src\NativeLoaderProbe\$id.json"
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $tools) "src\NativeLoaderProbe\$id.json") -Destination $manifestSource
    $probeLayout = Get-LoaderProbeLayout $repo
    Initialize-LoaderProbeState $probeLayout
    $null = New-Item -ItemType Directory -Path $probeLayout.Artifacts
    $dll = Join-Path $probeLayout.Artifacts "$id.dll"
    $manifest = Join-Path $probeLayout.Artifacts "$id.json"
    [IO.File]::WriteAllText($dll, 'own receipt fixture, never executed')
    Copy-Item -LiteralPath $manifestSource -Destination $manifest
    $sourceFingerprint = Get-LoaderProbeSourceFingerprint $repo
    $receipt = New-LoaderProbeReceipt -Layout $probeLayout -SourceFingerprint $sourceFingerprint
    $receiptText = $receipt | ConvertTo-Json -Depth 5
    Assert-Rejected { Read-LoaderProbeReceipt -Path $probeLayout.BuildReceipt -Layout $probeLayout -Kind build } 'Missing build'
    [IO.File]::WriteAllText($probeLayout.BuildReceipt, $receiptText)
    $verified = Assert-LoaderProbeBuild $probeLayout
    Assert-True ($verified.artifacts.Count -eq 2) 'Reviewed build did not have exactly two artifacts.'
    [IO.File]::AppendAllText($dll, 'tampered')
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'hash/length differs'
    [IO.File]::WriteAllText($dll, 'own receipt fixture, never executed')
    [IO.File]::WriteAllText((Join-Path $probeLayout.Artifacts 'unexpected.dll'), 'own rejected fixture')
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'exactly the own DLL'
    Remove-Item -LiteralPath (Join-Path $probeLayout.Artifacts 'unexpected.dll')
    $badManifest = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json -AsHashtable
    $badManifest.affects_gameplay = $true
    [IO.File]::WriteAllText($manifest, ($badManifest | ConvertTo-Json))
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'non-gameplay loader probe'
    Copy-Item -LiteralPath $manifestSource -Destination $manifest
    Remove-Item -LiteralPath $dll
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'exactly the own DLL'
    [IO.File]::WriteAllText($dll, 'own receipt fixture, never executed')
    Remove-Item -LiteralPath $manifest
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'exactly the own DLL'
    Copy-Item -LiteralPath $manifestSource -Destination $manifest
    $sourceCode = Join-Path $repo 'src\NativeLoaderProbe\LoaderProbe.cs'
    [IO.File]::AppendAllText($sourceCode, 'changed')
    Assert-Rejected { Assert-LoaderProbeSourceUnchanged -RepositoryRoot $repo -ExpectedFingerprint $sourceFingerprint } 'changed during'
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'stale'
    [IO.File]::WriteAllText($sourceCode, 'own fixture input')
    $badReceipt = $receiptText | ConvertFrom-Json -AsHashtable
    $badReceipt.game_root = 'C:\not-the-development-copy'
    [IO.File]::WriteAllText($probeLayout.BuildReceipt, ($badReceipt | ConvertTo-Json -Depth 5))
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'Invalid build'
    $badReceipt = $receiptText | ConvertFrom-Json -AsHashtable
    $badReceipt.artifacts[0].name = '..\unapproved.dll'
    [IO.File]::WriteAllText($probeLayout.BuildReceipt, ($badReceipt | ConvertTo-Json -Depth 5))
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'Invalid artifact allowlist'
    [IO.File]::WriteAllText($probeLayout.BuildReceipt, $receiptText)
    $null = New-Item -ItemType HardLink -Path (Join-Path $probeLayout.State 'receipt-link') -Target $probeLayout.BuildReceipt
    Assert-Rejected { Assert-LoaderProbeBuild $probeLayout } 'hard links'
    Remove-Item -LiteralPath (Join-Path $probeLayout.State 'receipt-link')
    Assert-Rejected { Assert-LoaderProbeDeployment $probeLayout } 'Missing deployment'

    $cleanFixture = Get-GameFingerprint $game
    $null = New-Item -ItemType Directory -Path $probeLayout.Deployment
    [IO.File]::Copy($dll, (Join-Path $probeLayout.Deployment "$id.dll"))
    [IO.File]::Copy($manifest, (Join-Path $probeLayout.Deployment "$id.json"))
    Assert-True ((Get-GameFingerprint -GameRoot $game -ExcludeLoaderProbe).Sha256 -ceq $cleanFixture.Sha256) 'Exact probe exclusion changed the underlying base.'
    Assert-True ((Get-GameFingerprint $game).Sha256 -cne $cleanFixture.Sha256) 'Default profile started ignoring extra probe files.'
    [IO.File]::WriteAllText((Join-Path $probeLayout.Deployment 'extra.dll'), 'own unapproved fixture')
    Assert-True ((Get-GameFingerprint -GameRoot $game -ExcludeLoaderProbe).Sha256 -cne $cleanFixture.Sha256) 'Probe exclusion ignored an arbitrary extra DLL.'
    Remove-Item -LiteralPath (Join-Path $probeLayout.Deployment 'extra.dll')
    [IO.File]::AppendAllText((Join-Path $game 'own-fixture.txt'), 'base changed')
    Assert-True ((Get-GameFingerprint -GameRoot $game -ExcludeLoaderProbe).Sha256 -cne $cleanFixture.Sha256) 'Probe profile ignored changed base contents.'
    $deploymentReceipt = New-LoaderProbeReceipt -Layout $probeLayout -Kind deployment -SourceFingerprint $sourceFingerprint
    [IO.File]::WriteAllText($probeLayout.DeploymentReceipt, ($deploymentReceipt | ConvertTo-Json -Depth 5))
    [IO.File]::AppendAllText((Join-Path $probeLayout.Deployment "$id.dll"), 'tampered')
    Assert-Rejected { Assert-LoaderProbeDeployment $probeLayout } 'hash/length differs'

    $probeSlot = Get-OfflineLayout -RepositoryRoot $repo -Slot 'loader-probe'
    Initialize-OfflineRoot $probeSlot
    $mainMarker = Join-Path $offline.Profile 'main-owned.txt'
    $null = New-Item -ItemType Directory -Path $offline.Profile
    [IO.File]::WriteAllText($mainMarker, 'main must stay unchanged')
    Assert-Rejected { Initialize-LoaderProbeConsent $offline } 'restricted'
    Initialize-LoaderProbeConsent $probeSlot
    $settingsPath = Join-Path $probeSlot.Profile 'roaming\SlayTheSpire2\default\1\settings.save'
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
    Assert-True ($settings.schema_version -eq 8 -and $settings.mod_settings.mods_enabled -eq $true) 'Fresh native consent schema is wrong.'
    $consentHash = (Get-FileHash -LiteralPath $settingsPath).Hash
    Initialize-LoaderProbeConsent $probeSlot
    Assert-True ((Get-FileHash -LiteralPath $settingsPath).Hash -ceq $consentHash) 'Consent is overwritten on repeat launch.'
    Assert-True ([IO.File]::ReadAllText($mainMarker) -ceq 'main must stay unchanged') 'Probe consent touched main.'
    $settings.mod_settings.mods_enabled = $false
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 5))
    Assert-Rejected { Initialize-LoaderProbeConsent $probeSlot } 'will not be overwritten'
    Assert-Rejected { & (Join-Path $tools 'Start-OfflineDev.ps1') -LoaderProbe -Slot main } 'dedicated'
    Assert-Rejected { & (Join-Path $tools 'Start-OfflineDev.ps1') -Slot loader-probe } 'reserved'
    $project = [xml][IO.File]::ReadAllText((Join-Path (Split-Path -Parent $tools) 'src\NativeLoaderProbe\NativeLoaderProbe.csproj'))
    Assert-True ($project.SelectNodes('//Exec').Count -eq 0 -and $project.SelectNodes('//Copy').Count -eq 0) 'Ordinary build contains deployment/run operations.'
    Assert-True ($project.Project.ItemGroup.Reference.Private -eq 'false') 'Game reference has CopyLocal enabled.'

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
