# STS2_MOD_Master

《Slay the Spire 2》新增单人角色 MOD 项目。
当前已有可编译的原生装载技术探针、独立离线入口及工程文档，尚无可游玩的角色。

## 五角色卡牌与专属遗物报告

[打开离线 HTML 报告](reports/sts2-v0.111.0-cards.html) ·
[事实 JSON 数据](reports/sts2-v0.111.0-data.json) ·
[统计口径、生成与验证说明](reports/README.md)

报告依据本机实际安装 `v0.111.0 / 41cef1ea`，不是“全球最新版本”声明。
包含五角色基础属性与初始牌组、595 张唯一卡牌、298 个唯一遗物附录；
角色卡池共 454 张，另标注 9 张角色相关衍生牌，每角色 8 个直接专属遗物加 1 个事件精炼形态。
支持完整列表搜索、类别/费用/稀有度/归属筛选、统计交叉表及打印，直接以 `file://` 打开，无联网依赖。
这是事实报告，不是角色设计或 A-02 至 A-07 的实施验收。

## 文档入口

- [文档总览](docs/README.md)：各文档的职责和阅读顺序。
- [产品需求 PRD](docs/prd.md)：首期范围、待定设计输入和验收门。
- [技术评估](docs/technical-assessment.md)：版本、工具、接口、依赖和主要难点。
- [工程实施计划](docs/implementation-plan.md)：阶段、前置条件与交付要求。
- [工程日志与看板](docs/engineering/README.md)：计划、任务、BUG/FIX 和实际实施记录。
- [角色设计](docs/character-design.md)：初始为零字节，由用户后续填写。
- [资料来源](docs/references.md)：公开资料与本地静态证据的来源和限制。

首期包括角色选择、专属卡牌/遗物、用户设计的机制、表现及受支持的存档续玩。
联机和创意工坊发布后置。没有预设角色设定、卡牌数量、数值或美术方向。

## 本地目录边界

```text
<workspace>\
  game\      合法游戏安装副本，仅作本地参考和后续受控调试
  mod\       本 Git 仓库
  backup\    私有普通存档备份和本地证据
  Godot\     按需准备的隔离编辑器及其本地数据
```

游戏基线为 `v0.111.0`，GodotSharp 为 `4.5.1`，目标框架为 `net9.0`。
官方 MegaDot `4.5.1-m.14` C# Windows x64 候选包已准备并完成版本查询；
自包含标记已配置，但编辑器数据隔离、资源导入、PCK 和游戏兼容性尚未验证。
版本匹配不是运行兼容保证，具体依赖和验证状态见技术评估与工程日志。

**游戏副本、MOD 存档分区和备份都不等于开发数据隔离。**
未来启动游戏前必须通过数据与云端行为隔离门。
详见 [本地开发边界](docs/local-development.md)。

## 独立离线开发入口

在仓库根目录先预检，再显式启动；日常使用不需要 Windows Sandbox：

```powershell
pwsh -NoProfile -File .\tools\Start-OfflineDev.ps1
pwsh -NoProfile -File .\tools\Start-OfflineDev.ps1 -Launch
```

入口固定使用本版本的 `--force-steam=off`，在创建子进程前设置其专用
`APPDATA`、`LOCALAPPDATA`、`TEMP` 和 `TMP`，不修改系统/父进程环境。
默认新建的独立档位位于：

```text
<workspace>\offline-data\v0.111.0-41cef1ea\main\roaming\SlayTheSpire2\default\1\
```

`-Slot <name>` 可选择另一组独立开发数据。备份不作为运行目录，
不会在每次启动时复制真实存档；本批没有导入任何玩家备份。
如需继承进度，应另行明确一个普通备份 profile 和全新 slot，再执行一次性复制，
而非合并账户、覆盖既有档位或反向恢复源文件。

入口拒绝未知发行文件、额外 MOD/`override.cfg`、路径链接、数据硬链接、
并发游戏及未识别数据根。游戏更新或未来加入 MOD 后需重新核准，不能直接共用旧版本可写档。
保护范围是**已核对的可信发行版本、固定入口及独立存档路径**：
不是宿主网络防火墙，不承诺阻止恶意 MOD 任意访问文件。
**直接双击游戏 EXE 或绕过入口不受此保护。**
运行验收与尚未覆盖项见本地开发边界和工程日志。

## A-01：原生装载探针

该探针只通过原生 `ModInitializerAttribute` 输出一次初始化标记，
不注册模型、不改变玩法、不需要 PCK、Godot 编辑器或社区框架。
它不是正式角色实现，`affects_gameplay=false`；原生加载器仍可能把测试档标记为 modded。

在仓库根目录按阶段执行：

```powershell
pwsh -NoProfile -File .\tools\Build-LoaderProbe.ps1
pwsh -NoProfile -File .\tools\Deploy-LoaderProbe.ps1
pwsh -NoProfile -File .\tools\Start-OfflineDev.ps1 -LoaderProbe -Launch -ProbeSeconds 60
pwsh -NoProfile -File .\tools\Deploy-LoaderProbe.ps1 -Remove
```

构建使用已安装且固定的 SDK `9.0.317`，不自动部署或运行。
忽略的 `artifacts\loader-probe` 仅包含自身 DLL 和 Manifest；
构建/部署凭据位于仓库外 `<workspace>\probe-state\loader-probe`。
源码输入在编译前后必须一致，部署与启动都检查当前构建和精确哈希，
不会将游戏目录里任意现有文件自动纳入信任。

`-LoaderProbe` 固定使用独立 `loader-probe` slot，拒绝指定 `main`；
首次仅在该新测试档创建原生 MOD 同意设置，已有禁用或异常设置不会被覆盖。
运行输出应恰好出现一次：
`STS2_MOD_MASTER_NATIVE_LOADER_PROBE/0.1.0 INITIALIZED count=1`。
限时停止的退出码不是自然退出成功；日志保存在该 slot 的 `diagnostics` 下，不进入 Git。

探针部署期间，普通无探针入口仍拒绝额外文件。
`-Remove` 只删除部署凭据匹配的两份产物和自己的空目录，恢复原 220 文件基线，
保留构建产物与测试档；不删除整个 `mods` 目录或修改其他 MOD。
本批运行后已执行移除，默认离线入口恢复可用；后续复现需重新显式部署。

## 公开仓库规则

只提交自身或明确授权的 MOD 源码、源资产和相关文档。
不提交游戏本体、参考程序集、提取/反编译代码或资产、真实存档、
工具分发包、私人配置或未经脱敏的本机日志。

公开仓库不自动授予第三方游戏内容的使用许可。本项目尚未选择发布许可证；
未来引入第三方代码和资产前应确认授权、版本及署名要求。
