#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Capture)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repo 'tools\DevLaunch.psm1') -Force
$workspace = Split-Path -Parent $repo
$game = Assert-PhysicalDirectory (Join-Path $workspace 'game')
Assert-OfflineBaseline $game
$feature = @(Get-CimInstance Win32_OptionalFeature -Filter "Name='Containers-DisposableClientVM'")
if ($feature.Count -ne 1 -or $feature[0].InstallState -ne 1 -or
    -not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent -or
    -not (Test-Path -LiteralPath "$env:WINDIR\System32\WindowsSandbox.exe")) {
    throw 'The report requires an already available Windows Sandbox; no OS changes are made.'
}
if (@(Get-Process | Where-Object ProcessName -In @('WindowsSandbox','WindowsSandboxClient',
    'WindowsSandboxServer','vmmemWindowsSandbox')).Count -gt 0) { throw 'A Sandbox is already running.' }
if ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory -lt 12GB / 1KB) {
    throw 'The report needs 8 GiB guest memory plus at least 4 GiB free host headroom.'
}
# Unlike a host-game launch, this report maps no live user data and may coexist with unrelated host gameplay.
$inputs = Join-Path $workspace "report-inputs\$Capture"
$output = Join-Path $workspace "report-data\$Capture"
foreach ($path in @($inputs, $output)) {
    if (Test-Path -LiteralPath $path) { throw "Capture paths must be new: $path" }
    $null = New-Item -ItemType Directory -Path $path
    $null = Assert-PhysicalDirectory $path
}
Copy-Item -LiteralPath (Join-Path $repo 'artifacts\catalog-reader\sts2_catalog_reader.dll'),
    (Join-Path $repo 'artifacts\catalog-reader\sts2_catalog_reader.json') -Destination $inputs
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Start-CatalogGuest.ps1') -Destination $inputs
$xml = [xml]'<Configuration><vGPU>Disable</vGPU><Networking>Disable</Networking><AudioInput>Disable</AudioInput><VideoInput>Disable</VideoInput><ProtectedClient>Enable</ProtectedClient><PrinterRedirection>Disable</PrinterRedirection><ClipboardRedirection>Disable</ClipboardRedirection><MemoryInMB>8192</MemoryInMB><MappedFolders/><LogonCommand><Command>powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\ReportInput\Start-CatalogGuest.ps1</Command></LogonCommand></Configuration>'
foreach ($mapping in @(
    @{host=$game; guest='C:\Sts2Game'; readOnly='true'},
    @{host=$inputs; guest='C:\ReportInput'; readOnly='true'},
    @{host=$output; guest='C:\ReportData'; readOnly='false'}
)) {
    $folder = $xml.CreateElement('MappedFolder')
    foreach ($pair in @{HostFolder=$mapping.host; SandboxFolder=$mapping.guest; ReadOnly=$mapping.readOnly}.GetEnumerator()) {
        $child = $xml.CreateElement($pair.Key); $child.InnerText=$pair.Value; $null=$folder.AppendChild($child)
    }
    $null=$xml.SelectSingleNode('/Configuration/MappedFolders').AppendChild($folder)
}
$configuration = Join-Path $workspace "report-data\$Capture.wsb"
$xml.Save($configuration)
Write-Output "Prepared only; launching this reviewed configuration requires explicit approval: $configuration"
Get-ChildItem -LiteralPath $inputs -File | ForEach-Object {
    [pscustomobject]@{Name=$_.Name; Bytes=$_.Length; Sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
}
