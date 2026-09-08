#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$game = Join-Path (Split-Path -Parent $repo) 'game'
$pck = Join-Path $game 'SlayTheSpire2.pck'
if ((Get-FileHash -LiteralPath $pck).Hash -cne 'C60F672EE7804E6AEFA1E19A582FA1C80B126A7B0EEF4D084D3ABF110DF2EAB7') {
    throw 'The localization package is not the pinned installed version.'
}
$stream = [IO.File]::OpenRead($pck)
$reader = [IO.BinaryReader]::new($stream)
$result = [ordered]@{}
try {
    if ($reader.ReadUInt32() -ne 0x43504447 -or $reader.ReadUInt32() -ne 3) { throw 'Unsupported PCK header.' }
    $null=$reader.ReadUInt32(); $null=$reader.ReadUInt32(); $null=$reader.ReadUInt32()
    $flags=$reader.ReadUInt32(); $base=$reader.ReadInt64()
    if ($flags -band 1) { throw 'Encrypted archive is outside this reader scope.' }
    $stream.Position=$reader.ReadInt64()
    $count=$reader.ReadInt32()
    $entries=@()
    for ($i=0; $i -lt $count; $i++) {
        $length=$reader.ReadInt32()
        if ($length -lt 0 -or $length -gt 65536) { throw 'Invalid PCK name length.' }
        $name=[Text.Encoding]::UTF8.GetString($reader.ReadBytes($length)).TrimEnd([char]0)
        $offset=$reader.ReadInt64(); $bytes=$reader.ReadInt64(); $null=$reader.ReadBytes(16)
        $entryFlags=$reader.ReadUInt32()
        if ($name -match '^localization/(eng|zhs)/(cards|relics|characters)\.json$') {
            if ($entryFlags -ne 0 -or $bytes -gt 4MB) { throw 'Unsupported localization entry.' }
            $entries+=@{name=$name; language=$Matches[1]; category=$Matches[2]; offset=$base+$offset; bytes=$bytes}
        }
    }
    if ($entries.Count -ne 6) { throw 'Expected exactly six versioned localization tables.' }
    foreach ($entry in $entries) {
        $stream.Position=$entry.offset
        $table=[Text.Encoding]::UTF8.GetString($reader.ReadBytes([int]$entry.bytes)) | ConvertFrom-Json -AsHashtable
        $shortNames=[ordered]@{}
        # Export titles only. Effect/lore text is never written to disk or the report.
        foreach ($key in @($table.Keys | Sort-Object)) {
            if ($key -cmatch '\.title$') { $shortNames[$key]=[string]$table[$key] }
        }
        $result["$($entry.language)/$($entry.category)"]=$shortNames
        Write-Output "$($entry.name): $($shortNames.Count) title keys"
    }
}
finally { $reader.Dispose(); $stream.Dispose() }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), ($result | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
