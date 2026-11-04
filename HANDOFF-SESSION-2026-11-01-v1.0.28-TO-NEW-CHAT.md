# 当前会话总交接：Mesting Music 1.0.28 / code49

交接日期：2026-11-01，Asia/Shanghai。版本实现和构建发生于 2026-10-31。本文件整理整个会话的完成内容、剩余问题、证据和接手边界；不会修改或替换已冻结的 APK/源码 ZIP。

## 接手结论

唯一工程为 `D:/AnLi`。本机最新交付 **1.0.28 / Android code49**，分支 `beta`，HEAD `b6bcd5425e0df3e03febdd460b56d0ed42004c52`。1.0.25～1.0.28 的源码改动仍在工作区，**没有提交、推送或发布**。不要用 Git HEAD 当作当前完整产品源码，不要从远端旧版本覆盖本机。

用户本次只要求编写交接并新建对话移交。接收对话第一轮只读核对本文件、AGENTS、分支和交付资料，简短确认接手后等待用户下一步。不能自动重建、继续修复、连接手机或发布。新对话沿用原目录，不创建新 worktree。

本轮已确认的编码和本地构建任务已交付；**一起听真实结束记录的业务问题仍未确认解决**，手机验收及外部发布也未完成，详见下文。

## 当前会话完成了什么

### 基线与归档

用户此前明确选择使用原目录、不保留当时旧的未提交源码，以最新 1.0.24 开始后续更新；该次同步已经完成，不能将旧授权用于删除现在 1.0.25～1.0.28 的改动。原签名、共享 SDK、定制 Release 引擎和历史冻结交付保留。

本机 2026-10-31 的归档交接记录了 1.0.23 原 R2 正式 Release、1.0.24 预发布及共 31 个附件的核验，见 [归档总交接](HANDOFF-GITHUB-2026-10-31-v1.0.24.md)。这是当时的归档证据；此次移交没有访问 GitHub 重新确认线上现状。当前本地 `origin/beta` 缓存 ref 也为 b6bcd542，未 fetch，不把缓存 ref 称为刚刚读到的远端状态。

### 1.0.25 / code46

- 网易云一起听增加退出入口：退出成功后停止同步，本机继续播放当前音乐。仅补网易云，酷狗一起听不在这次范围。
- 增加一起听聊天卡片与详情解析实现；是否能显示用户真实结束记录，当时没有实际载荷证明。
- 设置的“播放与同步”展示酷狗概念版音源与已保存账号状态，**不新增开关**。
- 按用户先预览、再确认的过程，为登录页面接入原始底部插画；横向铺满、压低高度、避让文字。该插画后来按用户指令在 1.0.26 全部移除，当前版本应保持移除。
- 原签名 APK、完整源码 ZIP 和校验资料已本地交付。主机 Beta 74 文件 1242 项通过。

见 [1.0.25 交接](HANDOFF-CURRENT-SESSION-2026-10-31-v1.0.25.md)。

### 1.0.26 / code47

- 移除登录插画及关联页面组件/资源，历史 1.0.25 冻结 ZIP 保持原字节。
- 补充移动端私信读取、消息容器/嵌套载荷解析及一起听记录卡片/详情实现。
- 网易云、酷狗已接入的浏览页面统一增加持久化响应缓存和封面缓存：先显示上次成功内容，后台刷新；覆盖首页、音乐库、歌单及歌曲/专辑/歌手等已接入浏览详情。
- 按当时确认方向调整 Tab 双向过渡，原签名完整交付；Beta 78 文件 1267 项通过。
- **用户随后明确反馈结束记录仍是“不支持/当前版本无法显示”**，因此本版真实记录修复未成功验收。

见 [1.0.26 交接](HANDOFF-CURRENT-SESSION-2026-10-31-v1.0.26.md)。本版旧 Tab 方向已被下一版最新反馈取代。

### 1.0.27 / code48

- 私信读取的 Android 客户端身份统一为 9.5.61/9005061/Android12，仅作用于两个读取接口，不改账号保存身份、发送接口或其他请求。
- 修正已支持的 extra/payload/record/report 等容器在消息入口提前丢失的问题，补充受限多层 JSON 解码，避免旧兼容提示覆盖现代正文。
- 增加**用户手动预览后显式复制的单条消息脱敏结构诊断**。不自动上传、不自动保存原始私信，不导出正文、账号/房间 ID、Cookie、令牌或链接值；切换账号后旧对话框不能复制。未知字段名匿名化。
- 按用户最新反馈反转 Tab 方向：发现→音乐→音乐库→我的，新页从右进入、旧页向左离开；反向新页从左进入、旧页向右离开。
- 原签名完整交付；Beta 79 文件 1276 项、Stable19、主机返回1、分析0，14 张主机渲染通过。
- 用户提供的是官方分享海报，没有本条原始消息载荷或专属详情地址，不能把海报上的歌曲数、时长硬编码到解析器。**用户真实记录是否恢复，尚未验收**。

见 [1.0.27 交接](HANDOFF-CURRENT-SESSION-2026-10-31-v1.0.27.md)。

### 1.0.28 / code49：当前版本

- 根据用户继续反馈，缓存刷新改为保留旧内容与旧封面，等新响应和对应封面下载、首帧解码就绪后一起发布；失败、超时、预算不足或账号代际改变时保留旧内容。首次没有有效缓存时仍允许占位图。
- 增加只有哈希的封面内容→缩略图文件索引，改善清后台后的磁盘恢复；通过独立 `RetainedArtworkFrame` 保留已解码画面，图源切换或新图失败时不重置为占位图。
- 图片准备有容量、并发和时限约束，发布前核对整组已解码图片仍被保留，防止慢下载期间早期图片被淘汰后仍发布文字。
- 移除 Tab 的动画完成等待门槛，每次有效点击立即选择最新目标；采用保留状态的分支 Navigator 和 PageController，从当前位置连续改向，支持快速连点与半途反向。沿用 1.0.27 方向及完整玻璃效果。
- 隐藏分支不抢底部搜索栏；每日推荐/最近播放等查询根链接转入内部 `/view` 二级页，避免重复 StatefulShell 的 GlobalKey 冲突；搜索返回交接及逻辑父级同步调整并回归。
- 原签名 APK、完整源码 ZIP、校验、安装验收与修改说明均已本地交付。

见 [当前版本总交接](HANDOFF-CURRENT-SESSION-2026-10-31-v1.0.28.md)、[修改与维护](docs/fixes-2026-10-31-v1.0.28.md)、[安装验收](docs/INSTALL-v1.0.28.md)。

## 当前交付与验证

| 文件 | 大小/信息 | SHA256 |
| --- | --- | --- |
| [原签名 APK](release/Mesting-Music-v1.0.28.apk) | 107599566 字节；1.0.28/code49；双 ARM | `7157782d1dc56b000d8a965d33bac3fae4881321806e05aa33208aee4dde5ac1` |
| [完整源码 ZIP](Mesting-Music-v1.0.28-source.zip) | 62034866 字节；1970 份文件加当前清单/历史基线 | `5fa03d3d87fb5bc3ff6bd9f9a9ef36ae9453b0a46edbbb4dfbeab7b984218196` |

原应用名 `Mesting Music`，包名 `com.mesting.music.beta`，原证书 SHA256 `8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333`。已核对 V2/V3、不可调试、min24/target36、16KiB ZIP/ARM64 ELF 对齐及 ARM32 ELF 对齐；两个 libflutter.so 匹配固定 manifest。7 个玻璃着色器和 8 个 SDK 原生库与本机 1.0.27 包字节相同，最终 APK 的生产 Range 读取器确认内置 3 条更新说明与离线历史一致。签名身份兼容不等于实际手机覆盖安装已验收。

1.0.28 已完成 80 文件 **1286 项 Beta**、2 文件 **19 项 Stable**、**1 项 Android 返回主机检查**，lib/test 静态分析 **0 问题**。完整回归后对图片整组留存补跑 8 个相关文件，统计取每文件最后完整结果，不重复累加。7 张主机渲染验证等待期间整页像素保持、新文字首帧已有新封面、Tab 改向瞬间画面不跳变；另覆盖图片失败、账号变化、scope、比例、并发容量、分支状态和搜索归属。合成夹具与主机渲染不等于真实手机、实际私信或 Android GPU 验收。

证据入口：[APK核验](release/Mesting-Music-v1.0.28-verification.json)、[源码核验](release/Mesting-Music-v1.0.28-source-verification.json)、[SHA256汇总](release/Mesting-Music-v1.0.28-SHA256.txt)、[主机验证](docs/validation-2026-10-31-v1.0.28.json)。本机私有详细日志及最终交付检查位于 `.codex-artifacts/2026-10-31-release128/`。

2026-11-01 本次移交只读复核：1.0.25～1.0.28 的 APK/ZIP 共 8 份文件摘要匹配各自核验资料；写本次交接前，1.0.28 清单中的 1970 份文件与工作区全部相同。核对时 Git 为 58 个已跟踪变更、63 个未跟踪文件、暂存区为空。本次只新增本交接并在 AGENTS 顶部追加接续指针，不改产品源码，也不回写旧冻结包。该交接和 AGENTS 新指针写于冻结之后，不包含在原 1.0.28 ZIP 中；后续对照冻结清单时应明确允许本次文档差异，不能重打包覆盖原 ZIP。

## 未完成的任务与验收

| 事项 | 当前状态与后续动作 |
| --- | --- |
| 网易云一起听真实结束记录 | **仍未确认解决，是剩余业务问题。** 1.0.26 用户已反馈失败，1.0.27/1.0.28 没有真实载荷或安装后成功反馈。等待用户手动提供该条脱敏结构诊断，再定位是否还缺消息类型/容器/官方目标；先逐题澄清并确认具体方案，不继续凭合成数据猜测。 |
| 官方一起听详情 | 官方 App 可以打开是用户已提供事实；本 App 的真实记录卡片和官方详情在手机中能否正常打开，仍待验收。只有消息实际带有受支持地址时使用，不拼造专属记录链接。 |
| 清后台后的缓存替换与 Tab 快切 | 主机实现和回归已完成；网易云/酷狗真实页面、实际网络、手机 GPU 下的无占位闪现、连续快切/改向、搜索及返回仍待用户安装验收。 |
| 一起听退出与账号音源状态 | 已实现退出后继续本机播放、停止同步和账号状态展示；真实账号、双端同步停止、好友侧状态及音源状态变更仍由用户验收。 |
| 原生稳定性 | 原签名和定制引擎保持，不能把本轮主机测试写成历史 GPU/native_crash 已永久修复、所有页面长期稳定或持续120FPS。 |
| Git/GitHub 与 music 发布 | 1.0.25～1.0.28 尚未 Git 提交推送、独立归档或上传发布。本轮只要求移交，不是发布授权；后续按用户新指令处理，区分本地准备、GitHub 归档、music 后台上线。 |

没有正在运行的构建/测试任务需要接力，也没有已确认但漏构建的下一版。**未指定 1.0.29，不自动分配新版本。** 当前先等待用户新的反馈/任务。

## 后续必须注意

- 保留全部工作区、未跟踪源码/文档、1.0.25～1.0.28 和更早冻结物。不 reset、clean、stash、切分支或直接 pull 覆盖。此前“不保留旧源码”只适用于已经完成的 1.0.24 同步。
- 没有新的明确授权，不访问手机/ADB，不安装或读取设备，不访问真实账号、music 后台，不自动提交/推送/打标签/发布，不重建冻结版本。
- 新需求或修复按 AGENTS 一次一个问题澄清，达到理解后给方案，用户确认后编码；当前已经确认的行为不要反复询问。必要注释、解耦和既有按钮公共约定继续执行。
- 保留完整玻璃、胶囊、原签名和固定定制引擎，不以去材质/去动画替代性能优化。新增 Beta 按钮遵守 `docs/BETA-CONTROL-CONVENTIONS.md`。
- 缓存准备器为前屏和可见条目服务，有界工作：冷启动只读已有磁盘封面，前12张/2秒；刷新选中封面最多64张/20秒，最多3路并行、24MiB解码池。首次无缓存或损坏仍允许占位。不要承诺整个音乐库无限预加载；变更账号时保留凭据代际与图片 scope 隔离。
- 图像与数据缓存不用于播放实时控制/写操作，不绕过账号或下载权益校验。单条消息诊断必须由用户预览并明确复制，不扩大为自动上传原始私信/认证信息。
- 当前根路由与搜索绑定是保留状态架构；改路由时同时验证快速改向、搜索归属、查询二级页、播放器/详情和 Android 返回，避免重复 StatefulShell GlobalKey。
- 内置 Beta 版本由构建参数、`assets/data/release-notes.json`、离线 release_history 和默认构建脚本共同控制。共享 pubspec 的 Stable 历史版本不表示当前 APK 版本。

## 维护与环境入口

| 区域 | 入口 |
| --- | --- |
| 一起听退出 | `lib/features/music_platform/netease/together/netease_together_exit.dart`、controller、panel |
| 消息卡片/诊断 | `lib/features/music_platform/netease/messages/netease_message_card.dart`、`netease_message_protocol.dart`、`netease_message_diagnostics.dart`、`netease_message_diagnostic_action.dart` |
| 酷狗概念版音源状态 | `lib/features/music_platform/netease/netease_account_source_info.dart` 与 `netease_source_settings_panel.dart` |
| 浏览响应缓存 | `lib/core/cache/browse_response_cache.dart`、`lib/features/music_platform/platform_browse_cache.dart`；Beta 启动接线在 `lib/main.dart` |
| 封面准备/持久化 | `lib/shared/media/artwork_refresh_coordinator.dart`、`persistent_network_image_cache.dart`、`lib/shared/utils/media_uri.dart` |
| 最后可见封面帧 | `lib/shared/widgets/retained_artwork_frame.dart`、`artwork_image.dart` |
| Tab/路由/搜索 | `lib/app/router/beta_tab_shell.dart`、app_router、`lib/shared/widgets/beta_root_tab_viewport.dart`、beta_tab_navigation、beta_bottom_search、`lib/features/experience/presentation/beta_music_shell.dart` |
| 新增回归 | `test/release_128_presentation_test.dart`、release_126_tab_motion、release_121_navigation；返回主机用例在 beta5_ui |
| 构建 | `tool/build_android_release_apk.ps1`，当前默认1.0.28/49；`third_party/flutter_engine/android-release/engine-manifest.json` 固定引擎 |

Flutter3.41.9 / Dart3.11.5 位于 `D:/CodexCache/flutter-3.41.9`；JDK17.0.20.1+1 与 Android SDK 位于 `D:/CodexCache/android-build`，Build Tools35.0.0、NDK28.2.13676358、Gradle8.14。构建使用进程局部环境、3GiB堆/worker1，并保留 pub 重建插件注册表。`pubspec.lock` SHA256 为 `6316dd4a0989c4a89b32d2a9a82bf603203743175909b52395a2d97cc4f2b5cc`。

私有构建/签名/冻结助手和证据分别在 `.codex-artifacts/2026-10-31-release125/`～`release128/`；原签名材料在本机私有签名目录，不能复制到公共源码或输出口令。源码 ZIP 已包括固定引擎/许可，排除私钥、本机配置、缓存、旧 APK/ZIP。工作区 SOURCE-SNAPSHOT.json 仍为历史1.0.24，交付 ZIP 内有独立1.0.28清单及1.0.24 BASELINE，不能把历史清单误当作当前版本。

本次移交的只读核对结果另存于 `.codex-artifacts/2026-11-01-session-handoff/verification.json`。新对话无需重跑全部回归来证明接手；先读以上材料、核对当前状态并等待用户。
