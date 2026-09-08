#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$game = $null
$started = $false
try {
    if ($env:USERNAME -cne 'WDAGUtilityAccount' -or
        (Get-CimInstance Win32_ComputerSystem).Model -notlike '*Virtual Machine*' -or
        $PSScriptRoot -ine 'C:\ReportInput') { throw 'Reviewed Sandbox guest only.' }
    if (@(Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object IPEnabled).Count -ne 0) {
        throw 'Networking must be disabled.'
    }
    if (Test-Path -LiteralPath 'C:\ReportGame') { throw 'Guest working copy must be fresh.' }
    if (Test-Path -LiteralPath 'C:\ReportData\profile') { throw 'Report profile must be new; do not reuse a prior data capture.' }
    $null = New-Item -ItemType Directory -Path 'C:\ReportGame'
    Copy-Item -Path 'C:\Sts2Game\*' -Destination 'C:\ReportGame' -Recurse
    $mod = 'C:\ReportGame\mods\sts2_catalog_reader'
    $null = New-Item -ItemType Directory -Path $mod
    Copy-Item -LiteralPath 'C:\ReportInput\sts2_catalog_reader.dll','C:\ReportInput\sts2_catalog_reader.json' -Destination $mod
    foreach ($path in @('C:\ReportData\profile\roaming\SlayTheSpire2\default\1',
        'C:\ReportData\profile\local','C:\ReportData\profile\temp')) {
        $null = New-Item -ItemType Directory -Path $path
    }
    [IO.File]::WriteAllText('C:\ReportData\profile\roaming\SlayTheSpire2\default\1\settings.save',
        '{"schema_version":8,"mod_settings":{"mods_enabled":true,"mod_list":[]}}')
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = 'C:\ReportGame\SlayTheSpire2.exe'
    $info.WorkingDirectory = 'C:\ReportGame'
    $info.Arguments = '--headless --force-steam=off'
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['APPDATA'] = 'C:\ReportData\profile\roaming'
    $info.EnvironmentVariables['LOCALAPPDATA'] = 'C:\ReportData\profile\local'
    $info.EnvironmentVariables['TEMP'] = 'C:\ReportData\profile\temp'
    $info.EnvironmentVariables['TMP'] = 'C:\ReportData\profile\temp'
    $game = [Diagnostics.Process]::new()
    $game.StartInfo = $info
    if (-not $game.Start()) { throw 'Guest game could not start.' }
    $started = $true
    $stdout = $game.StandardOutput.ReadToEndAsync()
    $stderr = $game.StandardError.ReadToEndAsync()
    $boundedStop = -not $game.WaitForExit(120000)
    if ($boundedStop) { Stop-Process -Id $game.Id -ErrorAction Stop }
    $game.WaitForExit()
    [IO.File]::WriteAllText('C:\ReportData\stdout.log', $stdout.GetAwaiter().GetResult())
    [IO.File]::WriteAllText('C:\ReportData\stderr.log', $stderr.GetAwaiter().GetResult())
    $result = @{ exitCode=$game.ExitCode; boundedStop=$boundedStop;
        outputExists=(Test-Path -LiteralPath 'C:\ReportData\catalog-raw.json') }
    [IO.File]::WriteAllText('C:\ReportData\run-result.json', ($result | ConvertTo-Json))
}
finally {
    if ($started -and -not $game.HasExited) { Stop-Process -Id $game.Id -ErrorAction Stop; $game.WaitForExit() }
    if ($null -ne $game) { $game.Dispose() }
    if ($env:USERNAME -ceq 'WDAGUtilityAccount' -and $PSScriptRoot -ieq 'C:\ReportInput') {
        & "$env:WINDIR\System32\shutdown.exe" /s /t 0
    }
}
