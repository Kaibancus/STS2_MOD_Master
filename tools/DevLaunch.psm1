#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-PhysicalDirectory {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[*?"<>|%]' -or
        $Path.Substring(2).Contains(':')) {
        throw "A local, absolute drive path without expansion characters is required: $Path"
    }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full.Length -le 3) { throw 'A drive root is not an allowed workspace.' }
    $item = Get-Item -LiteralPath $full -Force
    if (-not $item.PSIsContainer) { throw "Expected a directory: $full" }
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Reparse points are not allowed in a mapped path or its parents: $($item.FullName)"
        }
        $item = $item.Parent
    }
    return $full
}

function Get-PhysicalTree {
    param([Parameter(Mandatory)][string]$Path)

    $null = Assert-PhysicalDirectory $Path
    $pending = [Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($Path)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Dequeue() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Mapped trees must not contain reparse points: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
            else { $item }
        }
    }
}

function Assert-SingleLinkFiles {
    param([Parameter(Mandatory)][AllowEmptyCollection()][IO.FileInfo[]]$Files)

    if (-not ('Sts2Sandbox.FileLinks' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Sts2Sandbox {
    public static class FileLinks {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileInfo {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);
        public static uint Count(string path) {
            using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                FileInfo info;
                if (!GetFileInformationByHandle(file.SafeFileHandle, out info))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return info.Links;
            }
        }
    }
}
'@
    }
    foreach ($file in $Files) {
        if ([Sts2Sandbox.FileLinks]::Count($file.FullName) -ne 1) {
            throw "Persistent data must not contain hard links: $($file.FullName)"
        }
    }
}

function Get-DevSandboxLayout {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $repo = Assert-PhysicalDirectory $RepositoryRoot
    $workspace = Assert-PhysicalDirectory (Split-Path -Parent $repo)
    $game = Assert-PhysicalDirectory (Join-Path $workspace 'game')
    $data = Join-Path $workspace 'dev-data'
    $control = Join-Path $workspace 'dev-launch'
    $paths = @($repo, $game, $data, $control)
    for ($i = 0; $i -lt $paths.Count; $i++) {
        for ($j = $i + 1; $j -lt $paths.Count; $j++) {
            if ($paths[$i].Equals($paths[$j], [StringComparison]::OrdinalIgnoreCase) -or
                $paths[$i].StartsWith($paths[$j] + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $paths[$j].StartsWith($paths[$i] + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Repository, game, persistent data, and launch control paths must be separate.'
            }
        }
    }
    foreach ($path in @($data, $control)) {
        if (Test-Path -LiteralPath $path) {
            $files = @(Get-PhysicalTree $path)
            Assert-SingleLinkFiles -Files $files
            $marker = Join-Path $path '.sts2-sandbox'
            if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
                [IO.File]::ReadAllText($marker) -cne 'sts2-sandbox-v1') {
                throw "Existing development directories need the launcher ownership marker: $path"
            }
        }
    }
    $gameFiles = @(Get-PhysicalTree $game)
    if ($gameFiles.Count -eq 0) { throw 'The external game directory is empty.' }
    [pscustomobject]@{
        Repository = $repo
        Workspace = $workspace
        Game = $game
        Data = $data
        Control = $control
    }
}

function Assert-GameBaseline {
    param([Parameter(Mandatory)][string]$GameRoot)

    $assembly = Join-Path $GameRoot 'data_sts2_windows_x86_64\sts2.dll'
    if (-not (Test-Path -LiteralPath $assembly -PathType Leaf)) {
        throw 'Required sts2.dll is missing from the external game directory.'
    }

    if ((Get-FileHash -LiteralPath $assembly -Algorithm SHA256).Hash -ine
        '0861BFA1DF347538D932F22D580E75420F08082792EB914E53B4882764ACDBE9') {
        throw 'Unsupported sts2.dll fingerprint. Re-evaluate storage routing before launching.'
    }
    foreach ($path in @('SlayTheSpire2.exe', 'SlayTheSpire2.pck', 'release_info.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $GameRoot $path) -PathType Leaf)) {
            throw "Required game distribution file is missing: $path"
        }
    }
}

function Get-GameFingerprint {
    param([Parameter(Mandatory)][string]$GameRoot, [switch]$ExcludeLoaderProbe)

    $files = @(Get-PhysicalTree $GameRoot)
    $rows = [Collections.Generic.List[string]]::new()
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($GameRoot.TrimEnd('\').Length + 1).ToLowerInvariant()
        if ($ExcludeLoaderProbe -and $relative -in @(
            'mods\sts2modmaster_loader_probe\sts2modmaster_loader_probe.dll',
            'mods\sts2modmaster_loader_probe\sts2modmaster_loader_probe.json')) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add("$relative`t$($file.Length)`t$hash")
    }
    $rows.Sort([StringComparer]::Ordinal)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = [BitConverter]::ToString($hasher.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes(($rows -join "`n") + "`n"))).Replace('-', '')
    }
    finally { $hasher.Dispose() }
    [pscustomobject]@{ FileCount = $rows.Count; Sha256 = $digest }
}

function Assert-SandboxCapability {
    $feature = @(Get-CimInstance Win32_OptionalFeature -Filter "Name='Containers-DisposableClientVM'")
    if ($feature.Count -ne 1 -or $feature[0].InstallState -ne 1) {
        throw 'Windows Sandbox is not already enabled. No Windows features will be changed.'
    }
    if (-not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
        throw 'The Windows hypervisor is not available. No system settings will be changed.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsSandbox.exe') -PathType Leaf)) {
        throw 'WindowsSandbox.exe is unavailable.'
    }
    $existing = @(Get-Process | Where-Object {
        $_.ProcessName -in @('WindowsSandbox', 'WindowsSandboxClient', 'WindowsSandboxServer',
            'vmmemWindowsSandbox', 'SlayTheSpire2')
    })
    if ($existing.Count -gt 0) {
        throw 'A Sandbox or game process is already running. Close it yourself before using this launcher.'
    }
}

function Assert-OfflineBaseline {
    param([Parameter(Mandatory)][string]$GameRoot)

    Assert-GameBaseline $GameRoot
    $fingerprint = Get-GameFingerprint $GameRoot
    if ($fingerprint.FileCount -ne 220 -or $fingerprint.Sha256 -cne
        'FE774EDA1B68A73F6D3B224199462B4428C0612041B237F38794C7B118EF0524') {
        throw 'Unverified game distribution: changed, extra or missing files (including mods/override.cfg) are not allowed.'
    }
}

function Assert-OfflineEnvironment {
    foreach ($name in @('DOTNET_STARTUP_HOOKS', 'DOTNET_ADDITIONAL_DEPS', 'DOTNET_SHARED_STORE',
        'CORECLR_ENABLE_PROFILING', 'CORECLR_PROFILER', 'CORECLR_PROFILER_PATH',
        'COR_ENABLE_PROFILING', 'COR_PROFILER', 'COR_PROFILER_PATH')) {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($name, 'Process'))) {
            throw "Unexpected runtime injection environment: $name"
        }
    }
    if (@(Get-Process | Where-Object ProcessName -EQ 'SlayTheSpire2').Count -gt 0) {
        throw 'A game process is already running. Close it yourself before launching or importing.'
    }
}

function Get-OfflineLayout {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [ValidatePattern('^[a-z][a-z0-9-]{0,31}$')][string]$Slot = 'main'
    )

    if ($Slot -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') { throw 'Reserved Windows slot name.' }
    $repo = Assert-PhysicalDirectory $RepositoryRoot
    $workspace = Assert-PhysicalDirectory (Split-Path -Parent $repo)
    $game = Assert-PhysicalDirectory (Join-Path $workspace 'game')
    $root = Join-Path $workspace 'offline-data'
    $profile = Join-Path $root "v0.111.0-41cef1ea\$Slot"
    foreach ($protected in @($repo, $game, (Join-Path $workspace 'backup'),
        (Join-Path $env:APPDATA 'SlayTheSpire2'))) {
        if ($root.Equals($protected, [StringComparison]::OrdinalIgnoreCase) -or
            $root.StartsWith($protected.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $protected.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Offline data overlaps a protected repository, game, backup or original save directory.'
        }
    }
    if (Test-Path -LiteralPath $root) {
        $files = @(Get-PhysicalTree $root)
        Assert-SingleLinkFiles -Files $files
        $marker = Join-Path $root '.sts2-offline'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or
            [IO.File]::ReadAllText($marker) -cne 'sts2-offline-v1') {
            throw 'Existing offline-data is not an owned offline runtime root; no data will be adopted or overwritten.'
        }
    }
    [pscustomobject]@{ Repository = $repo; Workspace = $workspace; Game = $game; Root = $root; Profile = $profile; Slot = $Slot }
}

function Initialize-OfflineRoot {
    param([Parameter(Mandatory)]$Layout)

    if (-not (Test-Path -LiteralPath $Layout.Root)) {
        $null = New-Item -ItemType Directory -Path $Layout.Root
        [IO.File]::WriteAllText((Join-Path $Layout.Root '.sts2-offline'), 'sts2-offline-v1')
    }
    foreach ($name in @('roaming', 'local', 'temp', 'diagnostics')) {
        $path = Join-Path $Layout.Profile $name
        if (-not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path }
    }
}

function New-OfflineStartInfo {
    param([Parameter(Mandatory)][string]$GameRoot, [Parameter(Mandatory)][string]$ProfileRoot, [switch]$Headless)

    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $GameRoot 'SlayTheSpire2.exe'
    $start.WorkingDirectory = $GameRoot
    $start.UseShellExecute = $false
    $start.Arguments = if ($Headless) { '--headless --force-steam=off' } else { '--force-steam=off' }
    $start.EnvironmentVariables['APPDATA'] = Join-Path $ProfileRoot 'roaming'
    $start.EnvironmentVariables['LOCALAPPDATA'] = Join-Path $ProfileRoot 'local'
    $start.EnvironmentVariables['TEMP'] = Join-Path $ProfileRoot 'temp'
    $start.EnvironmentVariables['TMP'] = Join-Path $ProfileRoot 'temp'
    return $start
}

function New-OfflineMutex {
    $mutex = [Threading.Mutex]::new($false, 'Local\STS2OfflineDev-v1')
    try {
        if (-not $mutex.WaitOne(0)) { throw 'Another offline launcher or import is active.' }
    }
    catch [Threading.AbandonedMutexException] {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
        throw 'Previous offline operation ended unexpectedly; inspect its game process and data before retrying.'
    }
    catch {
        $mutex.Dispose()
        throw
    }
    return $mutex
}

function New-DevSandboxXml {
    param(
        [Parameter(Mandatory)][string]$GameRoot,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$RunId,
        [ValidateRange(5, 300)][int]$ProbeSeconds = 30,
        [ValidateSet('Boundary', 'StorageProbe', 'Play')][string]$Mode = 'Play'
    )

    $command = 'powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
        '"C:\Sts2Data\control\' + $RunId + '\Start-Guest.ps1" -RunId ' + $RunId
    $command += " -Mode $Mode -ProbeSeconds $ProbeSeconds"
    $document = [xml]'<Configuration />'
    $root = $document.DocumentElement
    foreach ($setting in ([ordered]@{
        vGPU = 'Disable'
        Networking = 'Disable'
        AudioInput = 'Disable'
        VideoInput = 'Disable'
        ProtectedClient = 'Enable'
        PrinterRedirection = 'Disable'
        ClipboardRedirection = 'Disable'
        MemoryInMB = '8192'
    }).GetEnumerator()) {
        $element = $document.CreateElement($setting.Key)
        $element.InnerText = $setting.Value
        $null = $root.AppendChild($element)
    }
    $mappings = $document.CreateElement('MappedFolders')
    foreach ($mapping in @(
        @{ HostFolder = $GameRoot; SandboxFolder = 'C:\Sts2Game'; ReadOnly = 'true' },
        @{ HostFolder = $DataRoot; SandboxFolder = 'C:\Sts2Data'; ReadOnly = 'false' }
    )) {
        $folder = $document.CreateElement('MappedFolder')
        foreach ($name in @('HostFolder', 'SandboxFolder', 'ReadOnly')) {
            $element = $document.CreateElement($name)
            $element.InnerText = $mapping[$name]
            $null = $folder.AppendChild($element)
        }
        $null = $mappings.AppendChild($folder)
    }
    $null = $root.AppendChild($mappings)
    $logon = $document.CreateElement('LogonCommand')
    $element = $document.CreateElement('Command')
    $element.InnerText = $command
    $null = $logon.AppendChild($element)
    $null = $root.AppendChild($logon)
    return $document.OuterXml
}

Export-ModuleMember -Function Get-DevSandboxLayout, Assert-GameBaseline, Assert-SandboxCapability,
    New-DevSandboxXml, Assert-PhysicalDirectory, Get-PhysicalTree, Assert-SingleLinkFiles,
    Get-GameFingerprint, Assert-OfflineBaseline, Assert-OfflineEnvironment, Get-OfflineLayout,
    Initialize-OfflineRoot, New-OfflineStartInfo, New-OfflineMutex
