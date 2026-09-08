#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RawPath,
    [Parameter(Mandatory)][string]$NamesPath,
    [Parameter(Mandatory)][string]$InventoryPath,
    [Parameter(Mandatory)][string]$RelationsPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$raw=Get-Content -LiteralPath $RawPath -Raw | ConvertFrom-Json -AsHashtable
$names=Get-Content -LiteralPath $NamesPath -Raw | ConvertFrom-Json -AsHashtable
$inventory=Get-Content -LiteralPath $InventoryPath -Raw | ConvertFrom-Json -AsHashtable
$relations=Get-Content -LiteralPath $RelationsPath -Raw | ConvertFrom-Json -AsHashtable
if ($raw.gameVersion -cne 'v0.111.0' -or $raw.gameCommit -cne '41cef1ea' -or
    $raw.cards.Count -ne 596 -or $raw.relics.Count -ne 299 -or $raw.characters.Count -ne 5 -or
    $inventory.Count -ne 935) { throw 'Unexpected version or full inventory; do not normalize a partial capture.' }
if (@(Compare-Object @($inventory | ForEach-Object Model | Sort-Object) @($raw.inventory | ForEach-Object model | Sort-Object)).Count -ne 0) {
    throw 'Independent static and runtime type inventories differ.'
}
function Name-Of([string]$language,[string]$category,[string]$entry) {
    $key="$entry.title"
    if (-not $names["$language/$category"].Contains($key)) { throw "Missing exact official short-name key: $language/$category/$key" }
    return $names["$language/$category"][$key]
}
$characterByPool=@{}; $relicCharacterByPool=@{}; $characterByModel=@{}; $startingCardOwners=@{}
foreach($c in $raw.characters) {
    if (-not $c.playable) { throw 'Non-playable character in native five-character list.' }
    $characterByPool[$c.cardPool]=$c.id; $relicCharacterByPool[$c.relicPool]=$c.id; $characterByModel[$c.model]=$c.id
    foreach($id in $c.startingDeck) { $startingCardOwners[$id]=$c.id }
}
$cardMembership=@{}; $relicMembership=@{}
foreach($pool in $raw.cardPools | Where-Object active) {
    foreach($id in $pool.cards) {
        if (-not $cardMembership.ContainsKey($id)) { $cardMembership[$id]=@() }
        $owner=if($characterByPool.ContainsKey($pool.id)){$characterByPool[$pool.id]}else{$null}
        $cardMembership[$id]+=@{pool=$pool.id; characterId=$owner; active=[bool]$pool.active}
    }
}
foreach($pool in $raw.relicPools | Where-Object active) {
    foreach($id in $pool.relics) {
        if (-not $relicMembership.ContainsKey($id)) { $relicMembership[$id]=@() }
        $owner=if($relicCharacterByPool.ContainsKey($pool.id)){$relicCharacterByPool[$pool.id]}else{$null}
        $relicMembership[$id]+=@{pool=$pool.id; characterId=$owner; active=[bool]$pool.active}
    }
}
# These are factual creation/reference links, not extra pool membership or proof of exclusive availability.
$tokenLinks=@{
    Fuel=@{character='Defect'; source='Compact'}
    GiantRock=@{character='Ironclad'; source='PrimalForce'}
    MinionDiveBomb=@{character='Regent'; source='Charge'}
    MinionSacrifice=@{character='Regent'; source='Guards'}
    MinionStrike=@{character='Regent'; source='Begone'}
    Shiv=@{character='Silent'; source='BladeDance'}
    Soul=@{character='Necrobinder'; source='CaptureSpirit'}
    SovereignBlade=@{character='Regent'; source='SummonForth'}
    SweepingGaze=@{character='Defect'; source='SentryMode'}
}
$cards=@()
foreach($c in $raw.cards | Sort-Object id) {
    if ($c.model -ceq 'DeprecatedCard') { continue }
    if (-not $cardMembership.ContainsKey($c.id)) { throw "Real card has no enumerated membership: $($c.id)" }
    $members=@($cardMembership[$c.id])
    $owners=@($members | ForEach-Object characterId | Where-Object { $null -ne $_ } | Sort-Object -Unique)
    $basis=if($owners.Count){'character-pool'}else{'shared-pool'}
    $generation=@()
    if($tokenLinks.ContainsKey($c.model)) {
        $link=$tokenLinks[$c.model]
        $evidence=@($relations | Where-Object {
            $_.source -ceq "MegaCrit.Sts2.Core.Models.Cards.$($link.source)" -and
            $_.target -ceq "MegaCrit.Sts2.Core.Models.Cards.$($c.model)"
        })
        if($evidence.Count-eq0){throw "Missing static generation/reference evidence for $($c.model)"}
        $owners=@($characterByModel[$link.character]); $basis='related-generation'
        $generation=@($evidence|ForEach-Object { @{source=$link.source;method=$_.method;token=$_.token} })
    }
    $unplayable='Unplayable' -in $c.keywords
    $energyKind=if($c.energyX){'x'}elseif($unplayable){'unplayable'}elseif($null-eq$c.canonicalEnergy){'unknown'}elseif($c.canonicalEnergy-lt0){'none'}else{'numeric'}
    $starKind=if($c.starsX){'x'}elseif($null-eq$c.canonicalStars){'unknown'}elseif($c.canonicalStars-lt0){'none'}else{'numeric'}
    $role=if($c.id-in$startingCardOwners.Keys){'starter'}elseif($c.pool-like'*TOKEN*'){'token'}elseif($c.pool-like'*CURSE*'){'curse'}elseif($c.pool-like'*STATUS*'){'status'}elseif($c.pool-like'*QUEST*'){'quest'}elseif($c.pool-like'*EVENT*'){'event'}elseif($c.rarity-in@('Common','Uncommon','Rare')){'reward'}else{'special'}
    $notes=@()
    if($c.playable-eq$null){$notes+='IsPlayable 为战斗上下文条件；canonical 不可求值，未将此牌标成永久不可打出。'}
    if($energyKind-eq'none'){$notes+='原始能量=-1，非X且无Unplayable关键字；作为无常规能量费用类，不计入固定费用均值。'}
    if($c.overriddenCostMethods.Count-gt0){$notes+='存在费用相关覆写（含X/星费声明），不等同于基准费用必然动态变化。'}
    $costOps=@($relations|Where-Object {$_.source-ceq"MegaCrit.Sts2.Core.Models.Cards.$($c.model)"-and$_.kind-in@('energyOperation','starOperation')})
    if($costOps.Count-gt0){$notes+='包含费用设置/升级/结算相关逻辑；本表仅记录未升级canonical基准，不计算实战改费。'}
    $cards+=@{
        id=$c.id;model=$c.model;nameZh=(Name-Of zhs cards $c.entry);nameEn=(Name-Of eng cards $c.entry)
        type=$c.type;rarity=$c.rarity;target=$c.target
        energy=@{kind=$energyKind;value=$(if($energyKind-eq'numeric'){$c.canonicalEnergy}else{$null});raw=$c.canonicalEnergy}
        stars=@{kind=$starKind;value=$(if($starKind-eq'numeric'){$c.canonicalStars}else{$null});raw=$c.canonicalStars}
        memberships=$members;owners=$owners;ownershipBasis=$basis;generationEvidence=$generation
        role=$role;registered=[bool]$c.registered;library=$c.library;keywords=@($c.keywords)
        contextualPlayable=$c.playable;generateCombat=$c.generateCombat;generateModifiers=$c.generateModifiers
        maxUpgradeLevel=$c.maxUpgradeLevel;costNotes=$notes;upgradeCost=$null;visualPool=$c.visualPool
        provenance='v0.111.0 canonical getters after GameStartupComplete; exact title key '+$c.entry+'.title'
    }
}
$relicByModel=@{};foreach($r in $raw.relics){$relicByModel[$r.model]=$r}
$refinements=@($relations|Where-Object {$_.source-ceq'MegaCrit.Sts2.Core.Models.Relics.TouchOfOrobas'-and$_.method-ceq'get_RefinementUpgrades'})
if($refinements.Count-ne10){throw 'Expected five exact starter-refinement dictionary pairs.'}
$replacements=@{}
for($i=0;$i-lt10;$i+=2){
    $starter=$relicByModel[$refinements[$i].target.Split('.')[-1]]
    $upgrade=$relicByModel[$refinements[$i+1].target.Split('.')[-1]]
    $owner=@($raw.characters|Where-Object {$starter.id-in$_.startingRelics})
    if($owner.Count-ne1){throw 'Refinement starter has ambiguous character ownership.'}
    $replacements[$upgrade.id]=@{starter=$starter.id;owner=$owner[0].id;token=$refinements[$i].token}
}
$relics=@()
foreach($r in $raw.relics|Sort-Object id){
    if($r.model-ceq'DeprecatedRelic'){continue}
    if(-not$relicMembership.ContainsKey($r.id)){throw "Real relic has no pool: $($r.id)"}
    $members=@($relicMembership[$r.id]);$owners=@($members|ForEach-Object characterId|Where-Object {$null-ne$_}|Sort-Object -Unique)
    $basis=if($owners.Count){'character-pool'}else{'shared-pool'}
    $starting=@($raw.characters|Where-Object {$r.id-in$_.startingRelics}|ForEach-Object id)
    $replaces=@();$evidence=$null
    if($replacements.ContainsKey($r.id)){
        $replacement=$replacements[$r.id];$owners=@($replacement.owner);$basis='starter-refinement'
        $replaces=@($replacement.starter);$evidence='TouchOfOrobas.get_RefinementUpgrades '+$replacement.token
    }
    $role=if($starting.Count){'starter'}elseif($replaces.Count){'special'}elseif($r.rarity-in@('Ancient','Event')){'event'}elseif($r.rarity-in@('Common','Uncommon','Rare','Shop')){'reward'}else{'special'}
    $relics+=@{id=$r.id;model=$r.model;nameZh=(Name-Of zhs relics $r.entry);nameEn=(Name-Of eng relics $r.entry)
        rarity=$r.rarity;memberships=$members;owners=$owners;ownershipBasis=$basis;role=$role
        registered=[bool]$r.registered;startingFor=$starting;replaces=$replaces;replacementEvidence=$evidence
        allowedInShopsHook=$r.allowedInShops;provenance='Canonical RelicPool membership and rarity; starter refinement relation where explicitly recorded.'}
}
$characters=@($raw.characters|ForEach-Object {
    $c=$_; @{
        id=$c.id;model=$c.model;nameZh=(Name-Of zhs characters $c.entry);nameEn=(Name-Of eng characters $c.entry)
        startingHp=$c.startingHp;maxHp=$c.startingHp;startingGold=$c.startingGold;maxEnergy=$c.maxEnergy
        orbSlots=$c.orbSlots;startingStars=$null;potionSlots=$null;starCounter=$c.showStars
        cardPool=$c.cardPool;relicPool=$c.relicPool
        startingDeck=@($c.startingDeck|Group-Object|Sort-Object Name|ForEach-Object {@{id=$_.Name;count=$_.Count}})
        startingRelics=@($c.startingRelics)
    }
})
$exclusions=@(
    @{kind='card';id='CARD.DEPRECATED_CARD';model='DeprecatedCard';reason='已注册的废弃占位模型；不在11个实际卡池，排除可用卡牌统计。'}
    @{kind='relic';id='RELIC.DEPRECATED_RELIC';model='DeprecatedRelic';reason='已注册的废弃占位遗物；排除可用遗物统计。'}
    @{kind='relic';id=$null;model='VakuuCardSelector';reason='Relics命名空间中的System.Object辅助类，不是RelicModel。'}
)
foreach($item in $inventory){
    if($item.Namespace-like'*.Mocks'){$exclusions+=@{kind='card';id=$null;model=$item.Model;reason='Cards.Mocks测试类型（含抽象基类）；仅库存登记，未实例化或调用测试行为。'}}
    if($item.Namespace-like'*.Characters'-and$item.Model-notin$characterByModel.Keys){$exclusions+=@{kind='character';id=$null;model=$item.Model;reason='不在本版本ModelDb.AllCharacters五名可玩角色列表；不纳入玩家角色。'}}
}
foreach($pool in $raw.cardPools|Where-Object {-not$_.active}){$exclusions+=@{kind='cardPool';id=$null;model=$pool.model;reason='测试/废弃池，明确不执行生成器；不是合法特殊池缺失。'}}
foreach($pool in $raw.relicPools|Where-Object {-not$_.active}){$exclusions+=@{kind='relicPool';id=$null;model=$pool.model;reason='废弃池；不执行生成器。'}}
$metadata=@{
    gameVersion='v0.111.0';gameCommit='41cef1ea';capturedUtc=$raw.capturedUtc
    sourceFingerprint='0861BFA1DF347538D932F22D580E75420F08082792EB914E53B4882764ACDBE9'
    extractionMethod='固定本机发行包：独立PE类型库存 + 禁网一次性Sandbox中的canonical白名单读取 + PCK短标题键 + 局部模型引用/精炼字典。'
    inventoryCounts=@{Cards=604;Relics=300;Characters=8;CardPools=14;RelicPools=9}
    sources=@(
        @{label='sts2.dll / v0.111.0 /41cef1ea';fingerprint='0861BFA1DF347538D932F22D580E75420F08082792EB914E53B4882764ACDBE9'}
        @{label='SlayTheSpire2.pck（仅导出zh/eng对应短名称）';fingerprint='C60F672EE7804E6AEFA1E19A582FA1C80B126A7B0EEF4D084D3ABF110DF2EAB7'}
    )
    definitions=@(
        '版本指本机实际安装v0.111.0/41cef1ea，不声称是报告日全球最新版本。基础属性采用未加进阶/进度/遗物修正的角色模板。'
        '595张可用卡 = 454个五角色直接池成员 + 141个无色/诅咒/状态/事件/任务/衍生池成员；池成员无重复。升级不是第二张卡。'
        '9张衍生牌另外标记角色相关生成来源，仍保留Token池成员关系；不计为新增唯一卡，也不声称其他效果绝不可能获得。'
        '298个可用遗物对应301条池成员关系；LastingCandy/RazorTooth/SparklingRouge各有两个池。每角色8个直接专属池遗物，另有1个经原生字典证实的事件初始遗物精炼形态，共9个归属条目。'
        '费用先识别能量X，再识别Unplayable关键字；其他负原始能量作为无常规能量费用类。IsPlayable只是上下文条件，不能替代关键字或用于永久可用性判断。'
        '星费独立于能量：HasStarCostX为真时为X星；否则原始-1表示没有星费。均值只计算energy.kind=numeric的未升级基准值，0费参与，X/不可打出/无常规能量费/未知排除。'
        '注册存在、可进图鉴、角色解锁和普通奖励可得性是不同维度；未按玩家存档解锁过滤。reward表示常规池稀有度分类，不承诺当前对局一定可抽到。'
        '来源相关字段只公开方法名/类型标识/数值和短名称，不包含卡牌效果段落、遗物故事、游戏图像或玩家档案。'
    )
    limitations=@(
        'Clash/GrandFinale/HighFive的IsPlayable需要战斗/可变模型上下文，原生canonical读取抛错；仅此条件为null，固定费用/类型/稀有度/目标完整。没有创建战斗或修改canonical来绕过。'
        '未执行卡牌升级或实战改费；upgradeCost=null，costNotes仅标明相关逻辑存在，不能把含Cost字样的覆写直接判为动态基础费用。'
        '药水容量与初始星数未作为独立已验证字段输出，保留null；Regent需要星计数器、Defect有3基础充能球槽已证实。初始遗物触发后的资源不混入无遗物修正的角色属性。'
        '事件/古代遗物的全局资格判断可能涉及对局/进度；本报告不列所有条件。LastingCandy有首次Ironclad对局排除，不构成Ironclad专属；角色名称引用/协同不作为专属判断。'
        '提取期间用户在宿主运行原版游戏，真实源存档存在正常变化，不能声称全源快照不变。报告guest无原源/Steam/原安装映射且禁网；开发副本及既有offline-data经独立复核未变。'
    )
}
$data=@{schemaVersion=1;metadata=$metadata;characters=$characters;cards=$cards;relics=$relics
    exclusions=$exclusions;issues=@($raw.issues);pools=@{cards=@($raw.cardPools);relics=@($raw.relicPools)}}
if($cards.Count-ne595-or$relics.Count-ne298){throw 'Normalized unique totals do not match the complete inventory.'}
$output=Join-Path $repo 'reports'
if(-not(Test-Path -LiteralPath $output)){$null=New-Item -ItemType Directory -Path $output}
$path=Join-Path $output 'sts2-v0.111.0-data.json'
[IO.File]::WriteAllText($path,($data|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
Write-Output $path
foreach($c in $characters){
    [pscustomobject]@{Character=$c.nameZh;DirectCards=@($cards|Where-Object {$_.ownershipBasis-eq'character-pool'-and$c.id-in$_.owners}).Count
        RelatedGenerated=@($cards|Where-Object {$_.ownershipBasis-eq'related-generation'-and$c.id-in$_.owners}).Count
        ExclusiveRelics=@($relics|Where-Object {$c.id-in$_.owners}).Count}
}
