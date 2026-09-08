# 五角色、全卡牌与专属遗物事实报告

- [独立离线 HTML](sts2-v0.111.0-cards.html)：完整筛选、搜索、排序、统计和打印。
- [结构化事实 JSON](sts2-v0.111.0-data.json)：唯一模型、实际池成员、归属依据、排除清单与局限。

版本是本机实际安装的 `v0.111.0 / 41cef1ea`，不是报告日的全球最新版。
数据采集时间保存在 JSON/HTML 中。游戏本体、原始配置、完整本地化表、卡牌效果段落、
遗物故事、图像、玩家数据与原始运行日志均不进入报告。

## 可对账的范围

| 角色 | 基础生命 | 初始金币 | 基础能量 | 直接卡池 | 相关衍生牌 | 直接专属遗物 | 事件精炼形态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 铁甲战士 | 80 | 99 | 3 | 90 | 1 | 8 | 1 |
| 静默猎手 | 70 | 99 | 3 | 91 | 1 | 8 | 1 |
| 储君 | 75 | 99 | 3 | 91 | 4 | 8 | 1 |
| 亡灵契约师 | 66 | 99 | 3 | 91 | 1 | 8 | 1 |
| 故障机器人 | 75 | 99 | 3 | 91 | 2 | 8 | 1 |

基础生命/金币/能量采用角色模板，不叠加进阶、进度或初始遗物触发效果。
故障机器人基础充能球槽为 3，其余为 0；独立初始星数、药水容量没有核实，显示 null/未核实。
牌组数量与初始遗物名称见完整报告。

- 604 个卡牌命名空间类型 = 595 个可用卡 + 1 个废弃占位 + 8 个测试类型。
- 595 个可用卡 = 454 个角色直接池成员 + 141 个无色、诅咒、事件、任务、状态、衍生池成员。
  11 个活动池之间没有重复卡；角色相关衍生归属只是附加维度，不新增全局唯一数量。
- 300 个遗物命名空间类型 = 298 个可用遗物 + 1 个废弃占位 + 1 个非遗物辅助类。
  301 条原生池成员关系归并为 298 个唯一遗物；LastingCandy、RazorTooth、SparklingRouge 各属于两个池。
- 每个角色专属池包含 8 个成员；原生 `TouchOfOrobas.RefinementUpgrades` 字典另外明确
  5 组初始遗物精炼对应关系，分别归属五角色，保留事件池而非伪称常规掉落。
- Deprived/Mock/Deprecated 卡池及 Deprecated 遗物池生成器不执行；其库存与理由仍展示。
  合法的 Token/Event/Quest/Colorless/Status/Curse 池没有因此遗漏。

## 费用和可得性

主统计为未升级 canonical 基准；X 先于原始数值 -1 判定。
`Unplayable` 关键字决定基准不可打出分类，不能用 `IsPlayable` 条件钩子替代。
其他负能量且无 X/Unplayable 声明的卡明确归为“无常规能量费”，不归零。
星费独立：`HasStarCostX=true` 是 X 星，否则 -1 表示无星费，不混入能量均值。
均值只含固定数字能量费用，包含 0，显示实际分母与被排除类别。

Clash、GrandFinale、HighFive 的上下文 `IsPlayable` getter 在 canonical 上拒绝求值，
这三项保留 null/问题记录；其基准费用、类型、稀有度和目标已完整采集。
没有修改 canonical、执行 OnPlay、升级或创建战斗来绕过限制。
升级费用未验证，统一 null；费用相关方法存在不代表基准费用必然动态。

模型存在、图鉴显示、玩家解锁和当前对局奖励资格分别处理。
报告没有按玩家进度过滤，不将生成标志或普通稀有度当作所有对局必可获得的保证。
Token 角色关系来自明确模型创建/引用链，仍保留 TokenPool；共享事件/怪物生成内容不摊入各角色。

## 重新生成和验证

从已提交事实数据重新生成 HTML，不运行游戏：

```powershell
pwsh -NoProfile -File .\tools\catalog\Generate-CatalogReport.ps1
pwsh -NoProfile -File .\tools\catalog\Test-CatalogData.ps1
pwsh -NoProfile -File .\tools\catalog\Test-CatalogBrowser.ps1
```

浏览器检查使用已安装 Edge、独立临时浏览器配置和本机回环 CDP；
不下载测试框架，不复用用户浏览器配置，结束后清除自己创建的临时目录。
页面使用内嵌 JSON、`textContent` 和安全 JSON 转义，没有 `fetch`、CDN、遥测或 `eval`。

重新采集只允许在再次审查过的独立离线 Windows Sandbox 中执行，不能在宿主直接加载游戏程序集：

1. `Build-CatalogReader.ps1` 用现有 SDK 编译自身只读诊断，游戏引用保持外部 `Private=false`。
2. `Prepare-CatalogCapture.ps1 -Capture <new-name>` 只准备新的输入/输出和配置，不启动。
3. 审查三个输入哈希、只读游戏/只读精确输入/新报告输出的映射、禁网和内存边界后，另行批准运行。
4. `Read-CatalogNames.ps1`、`Read-CatalogInventory.ps1`、`Read-CatalogRelations.ps1` 静态读取固定包的必要事实，
   所有中间结果输出到仓库外；名称脚本只导出短标题，不写出效果正文。
5. `Normalize-Catalog.ps1 -RawPath <raw> -NamesPath <names> -InventoryPath <inventory> -RelationsPath <relations>`
   核对完整库存后生成事实 JSON，再生成 HTML。

报告运行没有改变既有 loader probe 或通用离线启动保护。报告专用能力检查可以与无关的宿主原版游戏并存，
因为只映射独立开发副本和新报告目录，不映射原安装、Steam 或用户数据。
提取期间宿主实际有人游玩，原源存档不是恒定快照；不能宣称所有源文件不变。
独立核对的开发副本及既有 offline-data 保持不变，报告配置没有访问活跃原源数据的映射通道。
详细失败、更正和实际运行记录见[工程日志](../docs/engineering/log.md)。
