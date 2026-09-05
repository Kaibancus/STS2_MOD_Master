#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Remove)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'DevLaunch.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'LoaderProbe.psm1') -Force
$layout = Get-LoaderProbeLayout (Split-Path -Parent $PSScriptRoot)
$mutex = New-OfflineMutex
$staging = $null
$receiptCreated = $false
$activated = $false
try {
    Assert-OfflineEnvironment
    if ($Remove) {
        Assert-LoaderProbeDeployment -Layout $layout -ForRemoval
        foreach ($name in @('sts2modmaster_loader_probe.dll','sts2modmaster_loader_probe.json')) {
            Remove-Item -LiteralPath (Join-Path $layout.Deployment $name)
        }
        [IO.Directory]::Delete($layout.Deployment)
        Remove-Item -LiteralPath $layout.DeploymentReceipt
        Assert-OfflineBaseline $layout.Game
        Write-Output 'Removed only the verified probe DLL, manifest and owned leaf directory; clean 220-file baseline restored.'
        return
    }
    Assert-OfflineBaseline $layout.Game
    $build = Assert-LoaderProbeBuild $layout
    if ((Test-Path -LiteralPath $layout.Deployment) -or (Test-Path -LiteralPath $layout.DeploymentReceipt)) {
        throw 'Probe destination/receipt already exists. Refusing to overwrite; use explicit verified removal first.'
    }
    $staging = Join-Path $layout.State ('deploy-stage-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $staging
    foreach ($name in @('sts2modmaster_loader_probe.dll','sts2modmaster_loader_probe.json')) {
        [IO.File]::Copy((Join-Path $layout.Artifacts $name), (Join-Path $staging $name), $false)
    }
    Assert-LoaderProbeSourceUnchanged -RepositoryRoot $layout.Repository -ExpectedFingerprint $build.source_fingerprint
    $receipt = New-LoaderProbeReceipt -Layout $layout -Kind deployment -SourceFingerprint $build.source_fingerprint
    Assert-LoaderProbeArtifactMatch -Receipt $receipt -Directory $staging
    $parent = Split-Path -Parent $layout.Deployment
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
    $stream = [IO.File]::Open($layout.DeploymentReceipt, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $receiptCreated = $true
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($receipt | ConvertTo-Json -Depth 5))
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
    [IO.Directory]::Move($staging, $layout.Deployment)
    $activated = $true
    $staging = $null
    Assert-LoaderProbeDeployment $layout
    Write-Output 'Explicit probe deployment complete. No game launch or player settings change occurred.'
    Write-Output 'Default non-probe launch remains blocked until the probe is explicitly removed.'
}
finally {
    if (-not $activated -and $receiptCreated) { Remove-Item -LiteralPath $layout.DeploymentReceipt }
    if ($null -ne $staging -and (Test-Path -LiteralPath $staging)) {
        $null = @(Get-PhysicalTree $staging)
        Remove-Item -LiteralPath $staging -Recurse
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
