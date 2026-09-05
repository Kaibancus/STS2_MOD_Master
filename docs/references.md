# 资料来源与证据分级

研究基线日期：2026-09-05。只汇总和链接资料，不复制第三方完整教程、
游戏代码或资产。版本、分支和提交固定信息优先于随时变化的默认分支。

证据优先级：目标版本本地契约与实际验证 → 对应版本官方公告 →
固定版本框架源码 → 作者维护文档 → 其他教程。
公开源码证明实现存在，不证明本项目已在目标环境运行成功。

## 官方游戏资料

| ID | 来源 | 用途和边界 |
| --- | --- | --- |
| S01 | [Mega Crit v0.107.1](https://store.steampowered.com/news/app/2868840/view/1835871199305790) | 原生加载器、Workshop 和移除/失败 MOD 时的进度处理。 |
| S02 | [Mega Crit June Neowsletter](https://store.steampowered.com/news/app/2868840/view/1835871199312310) | 官方推荐 Alchyr 社区模板 Wiki；推荐不等于官方稳定 SDK 契约。 |
| S03 | [Mega Crit v0.108.0](https://store.steampowered.com/news/app/2868840/view/1836506165569491) | 多程序集、类型发现、XML 文档、模型/保存排序和首次 modded 存档复制。 |
| S04 | [Mega Crit v0.109.0](https://store.steampowered.com/news/app/2868840/view/1838407329258348) | 保存/ModelId 缓存及哈希变化。 |
| S05 | [Mega Crit v0.111.0](https://store.steampowered.com/news/app/2868840/view/1840944183778277) | 目标版本 MOD 存档复制及角色表现变更；公告标题为 Beta Patch Notes。 |

## 编辑器与资源包

| ID | 来源 | 用途和边界 |
| --- | --- | --- |
| S06 | [MegaDot 官方站](https://megadot.megacrit.com/) / [4.5.1-m.14 元数据](https://megadot.megacrit.com/api/4.5.1-m.14/) | 官方定制编辑器候选；有分发记录，不等于证明匹配本地全部资源流程。 |
| S07 | [MegaDot Windows C# 校验文件](https://megadot.megacrit.com/4.5.1-m.14/megadot-4.5.1-m.14-windows-x86_64-llvm-editor-csharp.zip.sha256) | 官方公布 SHA-256；下载实体仍须本地校验。 |
| S08 | [Godot 4.5.1 官方发行](https://github.com/godotengine/godot-builds/releases/tag/4.5.1-stable) / [校验清单](https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/SHA512-SUMS.txt) | stock Godot .NET 的后备分发来源；本批不并行安装。 |
| S09 | [Godot 4.5 C# 基础](https://docs.godotengine.org/en/4.5/tutorials/scripting/c_sharp/c_sharp_basics.html) | .NET 版编辑器与独立 SDK 的要求；不能安装不含 C# 的 standard 包代替。 |
| S10 | [Godot 自包含模式](https://docs.godotengine.org/en/4.5/tutorials/io/data_paths.html#self-contained-mode) | `_sc_` / `._sc_` 与编辑器数据；不等于 exported game 或 NuGet/Cloud 隔离。 |
| S11 | [Godot PCK/补丁/MOD 导出](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_pcks.html) | PCK/ZIP 与 `--export-pack` 工作流，需要有效 preset。 |
| S12 | [4.5.1 editor_node.cpp](https://github.com/godotengine/godot/blob/4.5.1-stable/editor/editor_node.cpp#L1234-L1264) / [export_pack](https://github.com/godotengine/godot/blob/4.5.1-stable/editor/export/editor_export_platform.cpp#L2217-L2224) / [C# 导出插件](https://github.com/godotengine/godot/blob/4.5.1-stable/modules/mono/editor/GodotTools/GodotTools/Export/ExportPlugin.cs) | pack-only 与完整项目导出的不同路径；不能把完整模板设为所有 MOD PCK 的硬前置。 |

## 社区工程与框架

| ID | 来源及固定版本 | 用途和边界 |
| --- | --- | --- |
| S13 | [ModTemplate Wiki](https://github.com/Alchyr/ModTemplate-StS2/wiki)；[基础](https://github.com/Alchyr/ModTemplate-StS2/wiki/Modding-Basics)；[Setup](https://github.com/Alchyr/ModTemplate-StS2/wiki/Setup)；[调试](https://github.com/Alchyr/ModTemplate-StS2/wiki/Testing-and-Debugging) | 官方推荐的作者维护社区入口；Wiki 会变化，关键结论须对照版本。Setup 当前优先 MegaDot。 |
| S14 | [BaseLib-StS2 3.4.5](https://github.com/Alchyr/BaseLib-StS2/tree/22757933ba10adc4322a628519a233a567507d87) | MIT 候选；原生能力之外的角色/UI/资源/保存适配。不是当前已安装依赖。 |
| S15 | [ModTemplate-StS2 2.5.2](https://github.com/Alchyr/ModTemplate-StS2/tree/55ca2c606e6c78dd39689a5cf979b243a49652e7) | 工程/Manifest 示例；包工程声明 MIT，仓库许可识别与各素材授权仍需具体审查。 |
| S16 | [BaseLib-Wiki 固定提交](https://github.com/Alchyr/BaseLib-Wiki/tree/5801b60d5f899f411581fc84d1e84d947155a255) | 普通图片/场景、非 Spine 动画、本地化；其中自定义接口不应写成游戏原生接口。 |
| S17 | [RitsuLib stable 0.5.18](https://github.com/BAKAOLC/STS2-RitsuLib/tree/f224961a9392e010335da092240b90ee8235317f) | MIT 候选；声明包括 0.111.0 的兼容目标；默认回退和网络相关能力需单独审查。 |
| S18 | [TheSorceress 固定提交](https://github.com/wyrdautumn/TheSorceress-StS2/tree/9fe8adfe18149063d708198dfe3f971d912da962) | 同目标版本的真实角色工程参考；未发现可直接推定复制授权的项目许可，不复制其代码或美术。 |
| S19 | [中文教程固定提交](https://github.com/GlitchedReme/SlayTheSpire2ModdingTutorials/tree/c898460c99b2082db51dd2f05296653baa52725c) | 寻找待核查主题的补充索引；部分内容标注 AI 整理，不能直接作为时序和命令行契约。 |

## 分析工具、云与后续发布

| ID | 来源 | 用途和边界 |
| --- | --- | --- |
| S20 | [ILSpy v9.1](https://github.com/icsharpcode/ILSpy/releases/tag/v9.1) / [v11.0](https://github.com/icsharpcode/ILSpy/releases/tag/v11.0) / [CLI 版本索引](https://api.nuget.org/v3-flatcontainer/ilspycmd/index.json) | v11 涉及 .NET10；v9.1 的 CLI/runtime 能力另查，不随意把新参数套在旧版上；只认官方来源。 |
| S21 | [Steamworks Cloud](https://partner.steamgames.com/doc/features/cloud) | 云同步边界及按游戏设置；禁用云也不等于本地文件隔离。 |
| S22 | [Mega Crit MOD uploader](https://github.com/megacrit/sts2-mod-uploader/tree/d7b7e6b16c413d5a124f474f9e5104ef01f76ab1) | 后续 Workshop 发布参考，本批不安装或执行。 |
| S23 | [Godot 4.5.1 OS 路径](https://github.com/godotengine/godot/blob/4.5.1-stable/core/os/os.cpp) / [Windows 实现](https://github.com/godotengine/godot/blob/4.5.1-stable/platform/windows/os_windows.cpp) | 自定义用户目录、APPDATA、LOCALAPPDATA 的公开对照；已另行核对实际游戏 EXE，不仅依赖 stock 实现。 |
| S24 | [Microsoft Windows Sandbox 配置](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file) | 一次性隔离验证的禁网、只读映射和 ProtectedClient；不是日常原生离线入口的必需组件。 |
| S25 | [Iced 1.21.0 官方 NuGet 包](https://api.nuget.org/v3-flatcontainer/iced/1.21.0/iced.1.21.0.nupkg) | 缺少现成原生分析工具时的固定版本本地工具；包与派生输出不进入仓库，不是 MOD 运行依赖。 |

## 本地证据

| ID | 位置/方法 | 已支持的结论 |
| --- | --- | --- |
| L01 | `game\release_info.json` 与 `sts2.runtimeconfig.json` | `v0.111.0 / 41cef1ea`、`net9.0` 与发行运行时信息。 |
| L02 | DLL 文件版本及 PE/CLI 静态元数据 | GodotSharp 4.5.1、Harmony 2.4.2；角色可见性/abstract/virtual；Manifest JSON 字段和依赖对象类型。没有执行游戏代码。 |
| L03 | `sts2.xml:88038-88466, 91409-91462, 91625-91720, 92281-92460` | 原生装载、模型/池、可变性、角色和资源契约。 |
| L04 | `sts2.xml:79056-80350, 88468-88820, 91229-91267` | 命令、事件和玩法/表现边界。 |
| L05 | `sts2.xml:87084-87276, 87489-87525, 99248-99346` | 本地化动态变量和随机流。 |
| L06 | `sts2.xml:102340-102426, 102477-102676` 及 UserDataPathProvider 元数据 | 保存入口、分区与云风险；不证明开发隔离。 |
| L07 | 本版本局部 IL：`CommandLineHelper` `0x06004D0C`、`NGame.InitializePlatform` 状态机 `0x0600B5A9`、`SaveManager.ConstructDefault` `0x06000732`、`NullPlatformUtilStrategy` `0x060010B4` | force-steam=off 的实际分支、云后端构造条件、默认离线 ID=1、存储及早期迁移路径。只公开结论，不公开 IL。 |
| L08 | 实际 EXE 的 Windows config/data/user-dir getter RVA `0x00481730`、`0x004818B0`、`0x00482170` 与必要项目配置；受控存储实验 | vtable 连接与 APPDATA/custom_user_dir_name=SlayTheSpire2；以实际文件写入佐证，原始配置/反汇编/日志仅本地保存。 |

本次 `sts2.dll` SHA-256：
`0861BFA1DF347538D932F22D580E75420F08082792EB914E53B4882764ACDBE9`。

本次 `sts2.xml` SHA-256：
`A88331870D38CDB84D8FC371AB3D7FB619AFA25C8C7249A47AAA77E1C7BF4286`。

本地 XML 行号与结论绑定这些指纹。游戏更新后重新采集，
不上传 XML、程序集、完整 API dump、反编译输出或真实玩家数据来“补齐引用”。

S-01 实际 EXE SHA-256：
`8602C26BFFD2937E3841835FD8360EF8E974624A543E05977229FD3D062BE231`。
实际 PCK SHA-256：
`C60F672EE7804E6AEFA1E19A582FA1C80B126A7B0EEF4D084D3ABF110DF2EAB7`。
入口另外核对全部发行文件的稳定摘要，既检查内容也检查增删；
任何基线更新都必须重新核对，不能仅以显示版本字符串放行。
