#Requires -Version 7.0
[CmdletBinding()]
param([string]$BrowserPath='C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $BrowserPath)){throw 'An installed Edge browser is required; this script installs nothing.'}
$repo=Split-Path -Parent(Split-Path -Parent $PSScriptRoot)
$file=(Get-Item -LiteralPath(Join-Path $repo 'reports\sts2-v0.111.0-cards.html')).FullName
$profile=Join-Path ([IO.Path]::GetTempPath()) ('sts2-catalog-browser-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $profile
$socket=[Net.WebSockets.ClientWebSocket]::new()
$script:nextId=0
function Cdp([string]$Method,[hashtable]$Params=@{}){
    $script:nextId++;$id=$script:nextId
    $message=@{id=$id;method=$Method;params=$Params}|ConvertTo-Json -Depth 15 -Compress
    $bytes=[Text.Encoding]::UTF8.GetBytes($message)
    $cts=[Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
    try{
        $null=$socket.SendAsync([ArraySegment[byte]]::new($bytes),[Net.WebSockets.WebSocketMessageType]::Text,$true,$cts.Token).GetAwaiter().GetResult()
        while($true){
            $buffer=[byte[]]::new(1048576);$output=[IO.MemoryStream]::new()
            try{
                do{$received=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),$cts.Token).GetAwaiter().GetResult();$output.Write($buffer,0,$received.Count)}while(-not$received.EndOfMessage)
                $response=[Text.Encoding]::UTF8.GetString($output.ToArray())|ConvertFrom-Json -AsHashtable
            }finally{$output.Dispose()}
            if($response.ContainsKey('id')-and$response.id-eq$id){
                if($response.ContainsKey('error')){throw($response.error|ConvertTo-Json)}
                return $response.result
            }
        }
    }finally{$cts.Dispose()}
}
function Js([string]$Expression){
    $result=Cdp 'Runtime.evaluate' @{expression=$Expression;returnByValue=$true;awaitPromise=$true}
    if($result.ContainsKey('exceptionDetails')){throw($result.exceptionDetails|ConvertTo-Json -Depth 8)}
    return $result.result.value
}
$browser=Start-Process -FilePath $BrowserPath -ArgumentList @('--headless=new','--disable-gpu','--no-first-run',
    '--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync',
    '--remote-debugging-port=0',("--user-data-dir=`"$profile`""),'about:blank') -PassThru
try{
    $portFile=Join-Path $profile 'DevToolsActivePort';$deadline=[DateTime]::UtcNow.AddSeconds(30)
    while(-not(Test-Path -LiteralPath $portFile)){if([DateTime]::UtcNow-gt$deadline){throw 'Browser debugger did not start.'};Start-Sleep -Milliseconds 250}
    $port=(Get-Content -LiteralPath $portFile)[0]
    $pages=Invoke-RestMethod "http://127.0.0.1:$port/json/list"
    $page=@($pages|Where-Object type -EQ page)[0]
    $null=$socket.ConnectAsync([uri]$page.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
    $null=Cdp 'Page.enable'
    $null=Cdp 'Runtime.enable'
    $null=Cdp 'Page.navigate' @{url=([uri]$file).AbsoluteUri}
    $deadline=[DateTime]::UtcNow.AddSeconds(30)
    while(-not(Js 'Boolean(window.catalogReport)')){if([DateTime]::UtcNow-gt$deadline){throw 'Offline page did not initialize.'};Start-Sleep -Milliseconds 250}
    $script=@'
(()=>{let checks=0;const data=window.catalogReport.data;
const assert=(ok,why)=>{if(!ok)throw new Error(why);checks++;};
const $=id=>document.getElementById(id), fire=id=>$(id).dispatchEvent(new Event('input',{bubbles:true}));
const cardRows=()=>[...$('card-table').tBodies[0].rows], relicRows=()=>[...$('relic-table').tBodies[0].rows];
assert(location.protocol==='file:','not file protocol');
assert(cardRows().length===595,'full card table');assert(relicRows().length===298,'full relic table');
for(const c of data.characters){
 $('card-character').value=c.id;fire('card-character');
 assert(cardRows().length===data.cards.filter(r=>r.owners.includes(c.id)).length,'character-associated cards');
 $('card-basis').value='character-pool';fire('card-basis');
 assert(cardRows().length===(c.model==='Ironclad'?90:91),'direct-pool filter');
 $('card-reset').click();$('relic-character').value=c.id;fire('relic-character');
 assert(relicRows().length===9,'all exclusive relics');
 $('relic-basis').value='character-pool';fire('relic-basis');assert(relicRows().length===8,'direct relics');
 $('relic-basis').value='starter-refinement';fire('relic-basis');assert(relicRows().length===1,'event upgrade relic');
 $('relic-reset').click();
}
$('card-search').value='not-a-real-model-48395';fire('card-search');assert($('card-count').textContent.includes('0 / 595'),'empty count');assert(cardRows()[0].textContent.includes('没有符合'),'empty state');
$('card-reset').click();assert(cardRows().length===595,'card reset');
$('card-search').value='Clash';fire('card-search');assert(cardRows().some(r=>r.textContent.includes('CARD.CLASH')),'event card searchable');
$('card-reset').click();$('card-cost').value='x';fire('card-cost');assert(cardRows().length===data.cards.filter(r=>r.energy.kind==='x').length,'energy X filter');
$('card-reset').click();$('card-type').value='Skill';$('card-rarity').value='Rare';fire('card-type');assert(cardRows().length===data.cards.filter(r=>r.type==='Skill'&&r.rarity==='Rare').length,'combined type rarity filters');
$('card-reset').click();document.querySelector('#card-table [data-sort="energy"]').click();
let nums=cardRows().map(r=>r.cells[5].textContent).filter(s=>/^\d+$/.test(s)).map(Number);
assert(nums.every((v,i)=>!i||v>=nums[i-1]),'ascending numerical cost sorting');
document.querySelector('#card-table [data-sort="energy"]').click();nums=cardRows().map(r=>r.cells[5].textContent).filter(s=>/^\d+$/.test(s)).map(Number);
assert(nums.every((v,i)=>!i||v<=nums[i-1]),'descending numerical cost sorting');
$('relic-search').value='not-a-relic-78373';fire('relic-search');assert($('relic-count').textContent.includes('0 / 298'),'empty relic state');
$('relic-reset').click();assert(relicRows().length===298,'relic reset');
const saved=data.cards[0].nameZh;data.cards[0].nameZh='<img src=x onerror=alert(1)>';
window.catalogReport.renderCards();assert(!document.querySelector('#card-table img'),'data treated as text, not HTML');
data.cards[0].nameZh=saved;window.catalogReport.renderCards();
assert(document.querySelectorAll('script[src],link[rel="stylesheet"]').length===0,'no external dependencies');
assert(document.querySelector('#overview').textContent.includes('454 + 9'),'headline disambiguates direct and generated');
return {checks,cardRows:cardRows().length,relicRows:relicRows().length};})()
'@
    $result=Js $script
    $null=Cdp 'Emulation.setDeviceMetricsOverride' @{width=390;height=844;deviceScaleFactor=1;mobile=$true}
    $mobile=Js '({width:innerWidth,scroll:document.documentElement.scrollWidth,ok:document.documentElement.scrollWidth<=innerWidth+1})'
    if(-not$mobile.ok){throw "Mobile horizontal page overflow: $($mobile|ConvertTo-Json -Compress)"}
    $null=Cdp 'Emulation.setEmulatedMedia' @{media='print'}
    $print=Js '({controlsHidden:getComputedStyle(document.querySelector(".controls")).display==="none",headersVisible:[...document.querySelectorAll("th button")].every(n=>getComputedStyle(n).display!=="none"),rows:document.querySelector("#card-table").tBodies[0].rows.length})'
    if(-not$print.controlsHidden-or-not$print.headersVisible-or$print.rows-ne595){throw 'Printed controls/headers/full rows are wrong.'}
    Write-Output "$($result.checks) real Edge file:// interaction checks passed; all 595 cards/298 relics, 390px layout and printed column titles verified."
}
finally{
    if($socket.State-eq[Net.WebSockets.WebSocketState]::Open){
        try{$null=Cdp 'Browser.close'}catch{Write-Warning 'Browser close response ended with its process; checking only the owned browser PID.'}
    }
    $socket.Dispose()
    if(-not$browser.WaitForExit(10000)){Stop-Process -Id $browser.Id -ErrorAction Stop;$browser.WaitForExit()}
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $profile -Recurse
}
