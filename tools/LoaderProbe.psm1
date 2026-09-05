#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevLaunch.psm1')

$script:ProbeId = 'sts2modmaster_loader_probe'
$script:BaseFingerprint = 'FE774EDA1B68A73F6D3B224199462B4428C0612041B237F38794C7B118EF0524'
$script:ArtifactNames = @("$script:ProbeId.dll", "$script:ProbeId.json")

function Get-LoaderProbeLayout {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $offline = Get-OfflineLayout -RepositoryRoot $RepositoryRoot -Slot 'loader-probe'
    $stateParent = Join-Path $offline.Workspace 'probe-state'
    if (Test-Path -LiteralPath $stateParent) { $null = Assert-PhysicalDirectory $stateParent }
    $state = Join-Path $stateParent 'loader-probe'
    if (Test-Path -LiteralPath $state) {
        Assert-SingleLinkFiles -Files @(Get-PhysicalTree $state)
        $marker = Join-Path $state '.sts2-loader-probe'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
            [IO.File]::ReadAllText($marker) -cne 'sts2-loader-probe-v1') {
            throw 'Existing probe state is not owned by this workflow.'
        }
    }
    [pscustomobject]@{
        Repository = $offline.Repository
        Game = $offline.Game
        Offline = $offline
        State = $state
        Artifacts = Join-Path $offline.Repository 'artifacts\loader-probe'
        Deployment = Join-Path $offline.Game "mods\$script:ProbeId"
        BuildReceipt = Join-Path $state 'build-receipt.json'
        DeploymentReceipt = Join-Path $state 'deployment-receipt.json'
    }
}

function Initialize-LoaderProbeState {
    param([Parameter(Mandatory)]$Layout)

    if (-not (Test-Path -LiteralPath $Layout.State)) {
        $null = New-Item -ItemType Directory -Path $Layout.State
        [IO.File]::WriteAllText((Join-Path $Layout.State '.sts2-loader-probe'), 'sts2-loader-probe-v1')
    }
}

function Get-LoaderProbeSourceFingerprint {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $inputs = @('global.json', 'NuGet.Config', 'src\NativeLoaderProbe\NativeLoaderProbe.csproj',
        'src\NativeLoaderProbe\LoaderProbe.cs', "src\NativeLoaderProbe\$script:ProbeId.json",
        'tools\Build-LoaderProbe.ps1')
    $rows = foreach ($relative in $inputs) {
        $path = Join-Path $RepositoryRoot $relative
        $null = Assert-PhysicalDirectory (Split-Path -Parent $path)
        $item = Get-Item -LiteralPath $path
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Probe inputs cannot be links.' }
        Assert-SingleLinkFiles -Files @($item)
        "$relative`t$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)"
    }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($rows -join "`n") + "`n")))
}

function Assert-LoaderProbeManifest {
    param([Parameter(Mandatory)][string]$Path)

    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $keys = @('id','name','author','description','version','has_pck','has_dll',
        'dependencies','affects_gameplay','min_game_version') | Sort-Object
    if (@(Compare-Object $keys @($manifest.Keys | Sort-Object)).Count -ne 0 -or
        $manifest.id -cne $script:ProbeId -or $manifest.version -cne '0.1.0' -or
        $manifest.min_game_version -cne '0.111.0' -or
        $manifest.has_dll -isnot [bool] -or -not $manifest.has_dll -or
        $manifest.has_pck -isnot [bool] -or $manifest.has_pck -or
        $manifest.affects_gameplay -isnot [bool] -or $manifest.affects_gameplay -or
        $manifest.dependencies -isnot [array] -or $manifest.dependencies.Count -ne 0) {
        throw 'The manifest is not the approved code-only, non-gameplay loader probe.'
    }
}

function Get-LoaderProbeArtifacts {
    param([Parameter(Mandatory)][string]$Directory)

    $files = @(Get-PhysicalTree $Directory)
    Assert-SingleLinkFiles -Files $files
    if (@(Get-ChildItem -LiteralPath $Directory -Directory -Force).Count -ne 0 -or
        $files.Count -ne 2 -or
        @(Compare-Object ($script:ArtifactNames | Sort-Object) @($files.Name | Sort-Object)).Count -ne 0) {
        throw 'Probe artifact directory must contain exactly the own DLL and manifest, with no extra files or directories.'
    }
    Assert-LoaderProbeManifest (Join-Path $Directory "$script:ProbeId.json")
    foreach ($name in $script:ArtifactNames) {
        $file = Get-Item -LiteralPath (Join-Path $Directory $name)
        [pscustomobject]@{ name = $name; length = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
}

function New-LoaderProbeReceipt {
    param([Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$SourceFingerprint,
        [ValidateSet('build','deployment')][string]$Kind = 'build')

    [ordered]@{
        schema = 1
        kind = $Kind
        probe_id = $script:ProbeId
        repository_root = $Layout.Repository
        game_root = $Layout.Game
        base_fingerprint = $script:BaseFingerprint
        source_fingerprint = $SourceFingerprint
        artifacts = @(Get-LoaderProbeArtifacts $Layout.Artifacts)
    }
}

function Assert-LoaderProbeSourceUnchanged {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$ExpectedFingerprint)

    if ((Get-LoaderProbeSourceFingerprint $RepositoryRoot) -cne $ExpectedFingerprint) {
        throw 'Probe source inputs changed during the operation; no new receipt is authorized.'
    }
}

function Read-LoaderProbeReceipt {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Layout,
        [Parameter(Mandatory)][ValidateSet('build','deployment')][string]$Kind)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing $Kind probe receipt." }
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Probe receipt cannot be a link.' }
    Assert-SingleLinkFiles -Files @($item)
    $receipt = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $keys = @('schema','kind','probe_id','repository_root','game_root','base_fingerprint',
        'source_fingerprint','artifacts') | Sort-Object
    if (@(Compare-Object $keys @($receipt.Keys | Sort-Object)).Count -ne 0 -or
        $receipt.schema -ne 1 -or $receipt.kind -cne $Kind -or $receipt.probe_id -cne $script:ProbeId -or
        $receipt.repository_root -ine $Layout.Repository -or $receipt.game_root -ine $Layout.Game -or
        $receipt.base_fingerprint -cne $script:BaseFingerprint -or
        $receipt.source_fingerprint -notmatch '^[A-F0-9]{64}$' -or
        $receipt.artifacts -isnot [array] -or $receipt.artifacts.Count -ne 2) {
        throw "Invalid $Kind probe receipt."
    }
    for ($i = 0; $i -lt 2; $i++) {
        $artifact = $receipt.artifacts[$i]
        if (@(Compare-Object @('length','name','sha256') @($artifact.Keys | Sort-Object)).Count -ne 0 -or
            $artifact.name -cne $script:ArtifactNames[$i] -or
            ($artifact.length -isnot [long] -and $artifact.length -isnot [int]) -or
            $artifact.length -le 0 -or $artifact.sha256 -notmatch '^[A-F0-9]{64}$') {
            throw "Invalid artifact allowlist in $Kind receipt."
        }
    }
    return $receipt
}

function Assert-LoaderProbeArtifactMatch {
    param([Parameter(Mandatory)]$Receipt, [Parameter(Mandatory)][string]$Directory)

    $actual = @(Get-LoaderProbeArtifacts $Directory)
    for ($i = 0; $i -lt 2; $i++) {
        if ($actual[$i].name -cne $Receipt.artifacts[$i].name -or
            $actual[$i].length -ne $Receipt.artifacts[$i].length -or
            $actual[$i].sha256 -cne $Receipt.artifacts[$i].sha256) {
            throw 'Probe artifact hash/length differs from its explicit receipt.'
        }
    }
}

function Assert-LoaderProbeBuild {
    param([Parameter(Mandatory)]$Layout)

    $receipt = Read-LoaderProbeReceipt -Path $Layout.BuildReceipt -Layout $Layout -Kind build
    if ($receipt.source_fingerprint -cne (Get-LoaderProbeSourceFingerprint $Layout.Repository)) {
        throw 'Probe build receipt is stale relative to the current source/build inputs.'
    }
    Assert-LoaderProbeArtifactMatch -Receipt $receipt -Directory $Layout.Artifacts
    $manifestSource = Join-Path $Layout.Repository "src\NativeLoaderProbe\$script:ProbeId.json"
    if ((Get-FileHash -LiteralPath $manifestSource -Algorithm SHA256).Hash -cne $receipt.artifacts[1].sha256) {
        throw 'Packaged manifest does not match its reviewed source.'
    }
    return $receipt
}

function Assert-LoaderProbeBase {
    param([Parameter(Mandatory)][string]$GameRoot)

    Assert-GameBaseline $GameRoot
    $files = @(Get-PhysicalTree $GameRoot)
    if ($files.Count -ne 222) { throw 'Probe deployment must contain exactly 220 base files and two own artifacts.' }
    Assert-SingleLinkFiles -Files $files
    $base = Get-GameFingerprint -GameRoot $GameRoot -ExcludeLoaderProbe
    if ($base.FileCount -ne 220 -or $base.Sha256 -cne $script:BaseFingerprint) {
        throw 'Probe profile has a modified base or an unapproved extra file.'
    }
}

function Assert-LoaderProbeDeployment {
    param([Parameter(Mandatory)]$Layout, [switch]$ForRemoval)

    $receipt = Read-LoaderProbeReceipt -Path $Layout.DeploymentReceipt -Layout $Layout -Kind deployment
    Assert-LoaderProbeArtifactMatch -Receipt $receipt -Directory $Layout.Deployment
    Assert-LoaderProbeBase $Layout.Game
    if (-not $ForRemoval) {
        $build = Assert-LoaderProbeBuild $Layout
        if ($receipt.source_fingerprint -cne $build.source_fingerprint) {
            throw 'Deployment receipt is not tied to the current reviewed build receipt.'
        }
        for ($i = 0; $i -lt 2; $i++) {
            if ($receipt.artifacts[$i].sha256 -cne $build.artifacts[$i].sha256 -or
                $receipt.artifacts[$i].length -ne $build.artifacts[$i].length) {
                throw 'Deployment artifacts differ from the current reviewed build receipt.'
            }
        }
    }
}

function Initialize-LoaderProbeConsent {
    param([Parameter(Mandatory)]$Layout)

    if ($Layout.Slot -cne 'loader-probe') { throw 'Probe consent is restricted to the loader-probe slot.' }
    $settingsPath = Join-Path $Layout.Profile 'roaming\SlayTheSpire2\default\1\settings.save'
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        $mods = $settings.mod_settings
        if ($settings.schema_version -ne 8 -or
            $null -eq $mods -or $mods.mods_enabled -isnot [bool] -or -not $mods.mods_enabled -or
            $mods.mod_list -isnot [array] -or $mods.mod_list.Count -gt 1 -or
            @($mods.mod_list | Where-Object { $_.id -cne $script:ProbeId -or $_.is_enabled -isnot [bool] -or -not $_.is_enabled }).Count -gt 0) {
            throw 'Existing probe consent is absent/disabled or contains unexpected mods; it will not be overwritten.'
        }
        return
    }
    $directory = Split-Path -Parent $settingsPath
    if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory }
    # This is new test-slot consent, not a copy of any player settings.
    $settings = @{ schema_version = 8; mod_settings = @{ mods_enabled = $true; mod_list = @() } }
    $stream = [IO.File]::Open($settingsPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($settings | ConvertTo-Json -Depth 5))
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

Export-ModuleMember -Function Get-LoaderProbeLayout, Initialize-LoaderProbeState,
    Get-LoaderProbeSourceFingerprint, Assert-LoaderProbeManifest, Get-LoaderProbeArtifacts,
    New-LoaderProbeReceipt, Read-LoaderProbeReceipt, Assert-LoaderProbeArtifactMatch,
    Assert-LoaderProbeBuild, Assert-LoaderProbeBase, Assert-LoaderProbeDeployment,
    Initialize-LoaderProbeConsent, Assert-LoaderProbeSourceUnchanged
