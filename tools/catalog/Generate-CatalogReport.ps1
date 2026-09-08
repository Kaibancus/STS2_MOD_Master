#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dataPath=Join-Path $repo 'reports\sts2-v0.111.0-data.json'
$json=[IO.File]::ReadAllText($dataPath)
$data=$json|ConvertFrom-Json -AsHashtable
if($data.schemaVersion-ne1-or$data.characters.Count-ne5-or$data.cards.Count-ne595-or$data.relics.Count-ne298){throw 'Incomplete or unexpected dataset.'}
$safe=$json.Replace('&','\u0026').Replace('<','\u003c').Replace('>','\u003e').Replace([string][char]0x2028,'\u2028').Replace([string][char]0x2029,'\u2029')
$template=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'catalog-template.html'))
if([regex]::Matches($template,'<!--CATALOG_DATA-->').Count-ne1){throw 'Template needs exactly one data marker.'}
$html=$template.Replace('<!--CATALOG_DATA-->','<script type="application/json" id="catalog-data">'+$safe+'</script>')
$output=Join-Path $repo 'reports\sts2-v0.111.0-cards.html'
[IO.File]::WriteAllText($output,$html,[Text.UTF8Encoding]::new($false))
Write-Output $output
