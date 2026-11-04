# Mesting Music 1.0.25 / code46 本地交付与接续

日期：2026-10-31，Asia/Shanghai。唯一工程根为 `D:/AnLi`，不是旧交接中的嵌套工程或另一台电脑路径。分支 beta，HEAD `b6bcd5425e0df3e03febdd460b56d0ed42004c52`；以已归档 1.0.24 为基线，本轮修改仍在工作区，未提交、推送或发布。

用户已确认本版为 1.0.25 / Android code46，并要求原签名 APK、完整源码 ZIP 和校验资料。此前旧代码的不保留/原地同步授权已经完成；当前 1.0.25 工作区、源码与交付应保留，不能据此再次 reset 或 clean。

## 完成内容

- 网易云一起听增加统一退出入口与确认，退出后停止同步、本机音乐继续播放；失败或未知结果保留房间，旧请求、命令和错误由会话代次隔离。酷狗一起听不在本次修改范围。
- 一起听聊天记录卡片、会话摘要及原生详情共用受限解析器；消息提供受支持的官方链接时可打开官方详情。未读取用户真实私信，真实卡片与详情仍待用户验收。
- 设置的播放与同步展示酷狗概念版账号音源及已保存账号状态，不新增开关。
- 八种登录方式与两个方式选择页使用用户原始插画，浅深色一致；横向铺满、缩小高度并贴底，表单避让，键盘或高度不足时隐藏插画并保留输入状态。
- 公开版本、内置更新说明、离线版本历史及构建默认值统一为 1.0.25 / 46。共享 pubspec 的 Stable 历史版本保持。

实现边界与维护入口见 [修改说明](docs/fixes-2026-10-31-v1.0.25.md)。先前源码更新阶段的 [followup](docs/followup-2026-10-31-v1.0.24.md) 与验证保留原时间点，当时的“未分配版本/未构建”不覆盖本版状态。

## 本地交付

- [原签名 APK](release/Mesting-Music-v1.0.25.apk)：108705597 字节，SHA256 `e05efc603eecf946e9aace3752c4bf9016af7ea011d826b9bd82f5f2698cf217`。
- [完整源码 ZIP](Mesting-Music-v1.0.25-source.zip)：含本轮全部工作源码、素材、第三方源码/许可及双 ARM 定制引擎。大小、摘要和全部文件校验结果见 [源码核验](release/Mesting-Music-v1.0.25-source-verification.json)。
- [APK 核验](release/Mesting-Music-v1.0.25-verification.json)、[汇总摘要](release/Mesting-Music-v1.0.25-SHA256.txt)、[安装验收](docs/INSTALL-v1.0.25.md)、[主机验证](docs/validation-2026-10-31-v1.0.25.json)。

源码 ZIP 内 `SOURCE-SNAPSHOT.json` 属于 1.0.25，逐文件记录原始字节摘要；工作区原有 1.0.24 清单保持，归档内另存为 `SOURCE-SNAPSHOT-v1.0.24-BASELINE.json`。源码 ZIP 自身摘要放在外置核验和 SHA256 文件，避免回写至归档内产生自引用。源选择包括 Git 跟踪文件与未忽略的新文件，排除缓存、应用签名材料、本机配置及私有证据，不是只交付 Git HEAD。

## 已验证

本轮功能主机回归按每文件最后一次完整结果合并：74 个 Beta 文件共 1242 项通过，Stable 2 文件 19 项通过，Android 返回注册 1 项通过，lib/test 静态分析 0 问题。分配 1.0.25 后补跑的更新说明和升级隔离 7 项包含在 1242 中，不能重复相加；历史/当前实际 APK 更新说明一致性另经生产 Range 读取器验证，通过 3 次局部读取取得全部 4 条说明，共 66085 字节，无网络访问。

最终 APK 核对了包名 `com.mesting.music.beta`、应用名 Mesting Music、1.0.25/code46、minSdk24/target36、不可调试、V2/V3 原证书、ZIP CRC、16KiB APK 对齐和双 ARM ELF 对齐。原证书 SHA256 为 `8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333`，覆盖升级身份条件匹配，实际手机安装仍待验收。

包内两份 libflutter.so 与固定 manifest 原生摘要匹配，完整引擎许可存在，未替换或重建引擎。7 个着色器及 8 个 SDK 原生库逐字节与本机保留的 1.0.22 包比较一致，区别于把不存在的本机 1.0.24 APK 说成已直接比较。登录插画与原始 PNG 字节一致；69 项正式版专用素材不进入 Beta 包；测试字体、IntegrationTestPlugin 和私有诊断编译标记未打入最终 APK。

## 尚待用户验收

本次未访问手机、ADB、真实平台账号或 music 后台，未安装 APK，也未执行 Together 双端或官版互通测试。用户反馈的真实记录消息未被提取；合成卡片夹具通过不能证明该条私信已经兼容。需用户检查实际记录、官方详情 WebView、退出后双方同步与本机继续播放，以及手机登录键盘、字号和 GPU 玻璃表现。不能声称持续 120 FPS、原生闪退永久修复或真实账号权益已确认。

## 构建与继续维护

本机 Flutter `D:/CodexCache/flutter-3.41.9` / Dart 3.11.5、Temurin JDK `D:/CodexCache/android-build/jdk/jdk-17.0.20.1+1`、SDK `D:/CodexCache/android-build/sdk`，Build Tools 35.0.0、NDK 28.2.13676358、Gradle 8.14。本轮进程局部使用 3GiB 堆和 worker1，未修改全局 Flutter/Java 或用户内存设置。

正式入口 `tool/build_android_release_apk.ps1 -VersionName 1.0.25 -VersionCode 46 -FlutterSdkRoot <Flutter3.41.9根目录>`。保留 pub 阶段以更新插件注册，依赖锁必须保持；Gradle 会校验固定引擎与 Flutter 引擎修订。原签名从用户私有保留材料提供，公共签名助手通过环境变量接收口令，禁止把口令或 keystore 放入源码。

私有构建日志、签名核验、原有冻结物前后摘要和冻结助手位于 `.codex-artifacts/2026-10-31-release125/`；功能截图与回归日志见 `.codex-artifacts/2026-10-31-v124-followup/`，登录真实组件截图见 `.codex-artifacts/2026-10-31-login-art-preview/`。这些目录不进入源码归档。旧本机 APK/源码 ZIP 与签名档案原字节保留。

后续接手先读本文件、安装说明和验证 JSON，核对工作区与产物，不重复已确认的需求问答。重大新歧义继续一次一问、确认方案后实施，保留注释与独立组件。没有新的明确授权，不访问手机、真实账号、提交推送或发布后台。
