# STS2_MOD_Master

《Slay the Spire 2》新增单人角色 MOD 项目。
当前已有中文工程文档和仓库外候选编辑器，尚无可编译的 MOD 工程或可游玩的角色。

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

## 公开仓库规则

只提交自身或明确授权的 MOD 源码、源资产和相关文档。
不提交游戏本体、参考程序集、提取/反编译代码或资产、真实存档、
工具分发包、私人配置或未经脱敏的本机日志。

公开仓库不自动授予第三方游戏内容的使用许可。本项目尚未选择发布许可证；
未来引入第三方代码和资产前应确认授权、版本及署名要求。
