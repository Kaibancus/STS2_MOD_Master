# 本地开发与数据边界

## 1. 当前基线

参考游戏为 `v0.111.0`，目标框架 `net9.0`，
GodotSharp 版本 `4.5.1`，随附 Harmony `2.4.2`。
这些信息来自版本文件和静态程序集信息，不代表角色 MOD 已能运行。

游戏是编译发行包，不是原始 C# 源码仓库。
类型/接口分析优先使用 XML 和 PE/CLI 元数据；必要时仅在本地进行方法级参考分析。
不得将游戏代码或提取资源提交到本仓库。

## 2. 目录布局

```text
<workspace>\
  game\
  mod\
  backup\
    normal-saves\
      <snapshot>\
  Godot\
    <pinned-editor-version>\
  offline-data\
    v0.111.0-41cef1ea\
      <slot>\
  dev-data\     私有 Sandbox 探针数据，不是日常离线档
  dev-launch\   私有探针配置，不进入 Git
  probe-state\  原生装载探针构建/部署凭据及专用 CLI 数据
```

只有 `mod` 是 Git 根。Godot 的用户指定安装位置是工作区的 `Godot` 子目录，
实际版本和安装状态记入工程日志。公开文档使用占位路径，不含个人主目录、
实际账户 ID 或备份快照清单。

游戏引用位于外部 `game\data_sts2_windows_x86_64`，例如
`sts2.dll`、`GodotSharp.dll`、`0Harmony.dll`。
未来编译与打包必须防止这些引用以 CopyLocal 等方式进入自身分发包。

编辑器和本机配置不修改系统 PATH，不替换游戏运行时，
不覆盖原 Steam 安装，不导入整个提取的游戏工程到公共仓库。

## 3. 工具准备不是游戏级验收

本轮已准备官方 MegaDot `4.5.1-m.14` C# Windows x64 便携编辑器作为兼容探针候选，
而不是随意下载最新版或不含 C# 的标准版；实际资源兼容性尚待探针。
编辑器、导出模板、原生扩展和音画制作工具分别判断必要性。

完整包大小和 SHA-256 已匹配官方资料，实际来源及公开版本事实见技术评估。
候选目录为 `<workspace>\Godot\megadot-4.5.1-m.14-win64-csharp`。
在可执行文件旁预先配置 `_sc_` 后，仅运行无项目的 console
`--headless --version`，退出码 0，输出 `4.5.1.m.14.mono.custom_build`。
查询后没有生成 `editor_data`；没有启动编辑器 UI/项目或游戏。

后续准备仍须记录官方来源、版本、文件校验和实际位置；版本查询只证明工具能响应，
不能代替自身资源导入、PCK 导出或游戏装载的后续探针。
本批没有验证完整编辑器设置/缓存、自包含数据行为或外部 .NET/NuGet/SDK 缓存边界，
不能笼统称为零外部写入，更不能代替玩家数据和云端隔离。

## 4. 现有普通存档备份

| 来源 | 备份范围 |
| --- | --- |
| `%APPDATA%\SlayTheSpire2\steam\<account>` | 普通 `profileN`、历史和现有备份，账户级 `profile.save` / `settings.save` 及其 `.backup` 变体 |
| `%APPDATA%\SlayTheSpire2\default\<account>` | 实际存在的普通设置及备份 |
| `<Steam>\userdata\<account>\2868840\remote` | 普通 `profileN` 和普通账户级存档文件 |

两类来源分别保存，不合并同名文件。排除 `modded`、`mod_data`、
MOD 专属设置/遥测、日志、运行缓存和 `remotecache.vdf`。
校验清单、原路径、账户信息和所有真实备份只保留在本地 `backup`。

没有恢复存档或修改 Steam 云同步。后续本 MOD 的自建隔离测试数据
与这些真实普通存档、其他 MOD 的真实存档均须区分。

## 5. 首次游戏级调试前的硬门

复制游戏不会自动复制或隔离用户数据。`UserDataPathProvider.IsRunningModded`
表明本版本有 MOD 分区，但不能证明其设置、云端和真实 MOD 档均不受影响。

本批选择轻量的宿主原生离线入口 `tools\Start-OfflineDev.ps1`，而不是要求日常使用 Sandbox。
实际解码的 `--force-steam=off` 使 `NGame.InitializePlatform` 跳过 Steam 初始化；
`SaveManager.ConstructDefault` 只有在 `SteamInitializer.Initialized` 为真时才构造
`SteamRemoteSaveStore` / `CloudSaveStore`。这是内置分支，不修改认证代码或伪装 Steam 身份。

游戏项目启用自定义用户目录 `SlayTheSpire2`；本版本 Windows 原生路径通过
`get_data_path -> get_config_path -> APPDATA` 解析 `user://`。
因此入口用 `ProcessStartInfo` 在创建进程前指定专用环境，而不是在游戏开始后改路径。
启动脚本不修改 `USERPROFILE`、注册表、全局环境或 Steam 设置，
也不写入原安装和源存档；这不等于对所有驱动/第三方工具的环境副作用作保证。

| 内容 | 专用 slot 下的位置 |
| --- | --- |
| 游戏 `user://`、日志和相关 Sentry 本地数据 | `roaming\SlayTheSpire2` |
| 本版本离线账号设置 | `roaming\SlayTheSpire2\default\1\settings.save` |
| profile 选择记录 | 同账号根下的 `[modded\]profile.save` |
| 偏好、进度、当前局和历史 | 同账号根下的 `[modded\]profileN\saves` |
| 本地缓存 | `local`（子进程 `LOCALAPPDATA`） |
| 临时文件 | `temp`（子进程 `TEMP` / `TMP`） |

默认 slot 为 `<workspace>\offline-data\v0.111.0-41cef1ea\main`。
编号 `1` 是本版本无额外身份参数时的实际实验结果，不是跨版本通用约定。
启动前的账号/profile 迁移也使用重定向后的 `user://`；
独立空根没有真实旧数据可迁移。当前不自动从普通备份或其他 MOD 数据播种。

宿主入口每次核对全部 220 个发行文件的路径、长度及内容指纹，拒绝新增/缺失/变更文件，
包括 `override.cfg` 或额外 MOD；游戏升级不能绕过该检查。
唯一显式例外是 `-LoaderProbe`：原 220 文件仍须完整匹配，仅在验证独立构建/部署凭据后，
允许 `mods\sts2modmaster_loader_probe` 下固定的同名 DLL/JSON 两文件。
没有通配排除或 unsafe 模式；未使用该开关时仍把两份探针产物当作额外文件拒绝。
数据按版本和 slot 分开，已有根须有自身归属标记；路径重解析点、数据硬链接、
运行时注入环境及并发游戏/入口均会阻断。预检不创建数据，也不启动进程。
这些约束不防御启动时恶意宿主程序同时修改文件，也不为未来任意 MOD 提供 OS 沙箱保证。

已完成两次一次性 Sandbox 内的真实游戏实验：固定
`--headless --force-steam=off` 与同一专用环境，实际写入设置/偏好/进度，
再次启动到达主菜单且三份存档内容保持一致；客体默认 AppData 未出现游戏目录。
原存档/Steam 缓存/原安装均由独立检查确认未改变。
随后经确认在宿主使用同一固定参数和子进程环境实际到达主菜单并写入专用档，
原源文件再次独立复核不变；S-02 已按当前可信发行版本范围完成。
这不是 `--version` 或模拟文件测试，也不是全部玩法、MOD 或图形表现的验收。

日常命令见根 README。维护者可用 `-ProbeSeconds 60 -Launch` 进行有界无界面验证，
只终止此入口创建的 PID；其强制停止退出码不能冒充自然退出成功。
自身脚本检查使用 `pwsh -NoProfile -File .\tools\tests\Test-DevLaunch.ps1`。
`tools\Start-DevSandbox.ps1` 仅用于显式边界/存储实验，不是日常默认入口。

“离线”在这里表示 **Steam 后端关闭且存档根独立**，不表示宿主整个进程被断网。
Sentry 是独立机制；未增加防火墙规则或全局网络限制。
入口也不控制另行运行的 Steam 客户端：A-01 批次观察到该客户端缓存评估刷新
`remotecache.vdf` 的时间戳，但索引内容及所有受保护存档内容/文件集合不变。
这一元数据例外单独记录，没有重设时间戳或恢复源文件以掩盖变化。
直接运行 EXE、修改入口参数/源码、加入未核准 MOD 或共享未核准版本档位不在保证范围内。
需要系统账户、权限或云设置变更的其他方案仍须另行确认。

### A-01 构建、部署和同意设置

项目为 `src\NativeLoaderProbe\NativeLoaderProbe.csproj`，使用 `Microsoft.NET.Sdk` / `net9.0`。
`global.json` 固定 SDK `9.0.317` 且禁用滚动选择；没有 PackageReference，
仓库 `NuGet.Config` 清空远端包源。唯一游戏引用是外部 `sts2.dll`，`Private=false`，
构建不复制游戏引用，不执行部署或启动操作。

应使用 `tools\Build-LoaderProbe.ps1`：子进程 CLI-home/NuGet 数据位于仓库外专用状态目录，
禁用遥测、HTTPS 开发证书生成、首次运行体验和共享构建服务器。
游戏引用目录显式传入已核对的副本路径。构建前捕获源码/项目/SDK 配置/构建脚本指纹，
编译和打包后再次比对；改变时不签发新凭据，不把新源码配给旧产物。
普通 `dotnet build` 只编译，并不签发启动所需凭据；它不能代替受控构建流程。

显式部署使用 `tools\Deploy-LoaderProbe.ps1`，只暂存/移动已核对的两份自身文件，
不覆盖现有目标，不读取玩家备份，不更改同意设置，也不启动游戏。
构建、部署、移除和运行复用互斥锁。部署存在时必须先精确移除才能重新构建，
不能通过重建把不明游戏目录内容“重新信任”。

实际探针档为 `<workspace>\offline-data\v0.111.0-41cef1ea\loader-probe`。
首次带 `-LoaderProbe -Launch` 时，入口仅为该新档创建
`roaming\SlayTheSpire2\default\1\settings.save`：
`schema_version=8`，`mod_settings.mods_enabled=true`，`mod_list=[]`。
这是显式诊断开关对应的新测试档同意，不复制 `main` 设置。
若已有设置撤销同意、schema 不匹配或包含其他 MOD，则停止而非覆盖。
原生加载成功后，该测试档进入 `default\1\modded\profile1`；
本次原生日志确认没有普通测试存档可复制，因此跳过首次 modded 数据复制。

移除只作用于哈希匹配的自身 DLL/JSON、专用空 leaf 和部署凭据；
篡改/缺失或未知内容会阻断，不通过删除整个目录恢复。
仅可能保留空的 `mods` 父目录，不影响原 220 文件基线。
原生调用结果、受保护源文件核对与有限的 headless 错误观察见本批工程日志；
未将 A-02 至 A-07 或完整 G2 标为完成。

## 6. 发布前的双重边界

一方面审查 Git 跟踪文件及待推送历史；另一方面审查 DLL/PCK/压缩包实际内容。
忽略规则既不能移除历史文件，也不能检查压缩包内部，更不能代替授权判断。

只发布自身或明确授权的内容，不上传真实日志、存档、账户信息、工具安装包、
游戏引用、提取或反编译输出。第三方资源和库的许可证/署名要求另行记录。
