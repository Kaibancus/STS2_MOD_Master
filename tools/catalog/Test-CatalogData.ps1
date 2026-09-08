#Requires -Version 7.0
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$path=Join-Path $repo 'reports\sts2-v0.111.0-data.json'
$d=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable
$checks=0
function Check([bool]$condition,[string]$message){if(-not$condition){throw $message};$script:checks++}
Check ($d.schemaVersion-eq1-and$d.characters.Count-eq5-and$d.cards.Count-eq595-and$d.relics.Count-eq298) 'Full dataset counts differ.'
foreach($kind in @('cards','relics','characters')){
    $rows=@($d[$kind]);Check (@($rows|ForEach-Object id|Sort-Object -Unique).Count-eq$rows.Count) "Duplicate $kind IDs"
    foreach($row in $rows){Check (-not[string]::IsNullOrWhiteSpace($row.nameZh)-and-not[string]::IsNullOrWhiteSpace($row.nameEn)) "Missing short name $($row.id)"}
}
$cardIds=@($d.cards|ForEach-Object id);$relicIds=@($d.relics|ForEach-Object id);$characterIds=@($d.characters|ForEach-Object id)
Check (@($d.cards|ForEach-Object memberships).Count-eq595) 'Card membership sum differs.'
Check (@($d.relics|ForEach-Object memberships).Count-eq301) 'Relic membership sum differs.'
Check (@($d.cards|Where-Object ownershipBasis -EQ 'character-pool').Count-eq454) 'Direct character pool sum differs.'
Check (@($d.cards|Where-Object ownershipBasis -EQ 'related-generation').Count-eq9) 'Generated association count differs.'
foreach($r in @($d.cards)+@($d.relics)){
    Check ($r.memberships.Count-gt0) "Unpooled included model $($r.id)"
    foreach($owner in $r.owners){Check ($owner-in$characterIds) "Unknown owner $owner"}
}
foreach($c in $d.characters){
    $direct=@($d.cards|Where-Object {$_.ownershipBasis-eq'character-pool'-and$c.id-in$_.owners})
    Check ($direct.Count-eq$(if($c.model-eq'Ironclad'){90}else{91})) "Wrong direct card count $($c.id)"
    Check (@($d.relics|Where-Object {$_.ownershipBasis-eq'character-pool'-and$c.id-in$_.owners}).Count-eq8) 'Direct exclusive relic count'
    Check (@($d.relics|Where-Object {$_.ownershipBasis-eq'starter-refinement'-and$c.id-in$_.owners}).Count-eq1) 'Refinement count'
    Check ($c.startingGold-eq99-and$c.maxEnergy-eq3-and$c.startingHp-eq$c.maxHp) 'Base attributes differ'
    foreach($entry in $c.startingDeck){Check ($entry.id-in$cardIds-and$entry.count-gt0) 'Invalid starting deck ID/count'}
    foreach($id in $c.startingRelics){Check ($id-in$relicIds) 'Invalid starting relic ID'}
}
foreach($c in $d.cards){
    Check ($c.energy.kind-in@('numeric','x','none','unplayable','unknown')) "Unknown energy kind $($c.id)"
    Check ($c.stars.kind-in@('numeric','x','none','unknown')) "Unknown stars kind $($c.id)"
    Check ($c.energy.kind-ne'numeric'-or($null-ne$c.energy.value-and$c.energy.value-ge0)) 'Numeric energy must be nonnegative'
    Check ($c.stars.kind-ne'numeric'-or($null-ne$c.stars.value-and$c.stars.value-ge0)) 'Numeric star cost must be nonnegative'
    Check ($c.energy.kind-eq'numeric'-or$null-eq$c.energy.value) 'Special energy category has numeric value'
    Check ('Unplayable'-notin$c.keywords-or$c.energy.kind-eq'unplayable') 'Canonical Unplayable ignored'
    Check ($null-eq$c.upgradeCost) 'Unverified upgrade cost was invented'
}
foreach($id in @('CARD.BURN','CARD.WOUND','CARD.ASCENDERS_BANE')){Check (($d.cards|Where-Object id -EQ $id).energy.kind-eq'unplayable') 'Unplayable sample misclassified'}
Check (($d.cards|Where-Object id -EQ 'CARD.CASCADE').energy.kind-eq'x') 'Cascade X misclassified'
Check (($d.cards|Where-Object id -EQ 'CARD.STARDUST').stars.kind-eq'x') 'Stardust X stars misclassified'
foreach($id in @('CARD.CLASH','CARD.GRAND_FINALE','CARD.HIGH_FIVE')){Check (($d.cards|Where-Object id -EQ $id).energy.kind-eq'numeric') 'Context exception corrupted stable cost'}
Check ($d.issues.Count-eq3) 'Getter issue count differs'
Check ($d.exclusions.Count-eq18) 'Exclusion accounting differs'
Check (@($d.exclusions|Where-Object kind -EQ card).Count-eq9) '604 card type inventory does not reconcile'
Check ((595+9)-eq$d.metadata.inventoryCounts.Cards) 'Card raw inventory equation'
Check ((298+@($d.exclusions|Where-Object kind -EQ relic).Count)-eq$d.metadata.inventoryCounts.Relics) 'Relic raw inventory equation'
$overlaps=@($d.relics|Where-Object {$_.memberships.Count-gt1}|ForEach-Object model|Sort-Object)
Check (@(Compare-Object @('LastingCandy','RazorTooth','SparklingRouge') $overlaps).Count-eq0) 'Unexpected relic pool overlap'
foreach($r in $d.relics){foreach($id in $r.replaces){Check ($id-in$relicIds-and$r.ownershipBasis-eq'starter-refinement') 'Invalid refinement relation'}}
$htmlPath=Join-Path $repo 'reports\sts2-v0.111.0-cards.html'
$html=[IO.File]::ReadAllText($htmlPath)
$match=[regex]::Match($html,'<script type="application/json" id="catalog-data">([\s\S]*?)</script>')
Check $match.Success 'Missing embedded canonical dataset'
$embedded=$match.Groups[1].Value|ConvertFrom-Json -AsHashtable
Check (($embedded|ConvertTo-Json -Depth 20 -Compress)-ceq($d|ConvertTo-Json -Depth 20 -Compress)) 'HTML payload differs from JSON'
Check (-not[regex]::IsMatch($html,'(?i)<script[^>]+src=|<link[^>]+href=|\beval\s*\(|\.innerHTML\s*=|\bfetch\s*\(')) 'Unsafe/external HTML dependency'
Check ((Get-Item -LiteralPath (Join-Path $repo 'docs\character-design.md')).Length-eq0) 'User design changed'
Write-Output "$checks factual schema, membership, cost, name, exclusion and embedded-output checks passed."
