# Mesting Music 1.0.27 / code48 本地交付与接续

日期：2026-10-31，Asia/Shanghai。唯一工程 D:/AnLi，beta / b6bcd5425e0df3e03febdd460b56d0ed42004c52。基于本机 1.0.26 的全部工作源码继续更新；1.0.25、1.0.26 及此前改动仍在未提交工作区，不 reset/clean、不从旧远端覆盖。没有提交推送、GitHub Release、music 发布或手机安装。

用户最新反馈：1.0.26 仍无法显示 10/30 一起听结束消息，收到“当前版本无法显示该信息”；原 Tab 动画感觉反向。本次明确确认实施 1.0.27/code48，并增加仅手动导出的单条消息脱敏诊断。用户暂不方便连接手机，没有手机/ADB/真实账号授权。分享附件是官方海报，二维码为通用一起听入口，不含这次记录的原始消息或详情地址。

## 交付

- [原签名双 ARM APK](release/Mesting-Music-v1.0.27.apk)，107484878 字节，SHA256 `52d1b27298b2226ddb9c9db29050e56cdb8210f2755b6258d491397226b09aa0`。
- [完整源码 ZIP](Mesting-Music-v1.0.27-source.zip)，包括全部当前工作改动与固定引擎/许可证，不只包含 Git HEAD。
- [APK 核验](release/Mesting-Music-v1.0.27-verification.json)、[源码核验](release/Mesting-Music-v1.0.27-source-verification.json)、[摘要汇总](release/Mesting-Music-v1.0.27-SHA256.txt)。源码 ZIP 自身摘要只在外置资料中保存，避免自引用。
- [安装验收](docs/INSTALL-v1.0.27.md)、[修改说明](docs/fixes-2026-10-31-v1.0.27.md)、[验证](docs/validation-2026-10-31-v1.0.27.json)。

1.0.26 APK/源码 ZIP、原私有签名与其他历史冻结文件保持原字节，最终检查对照 38 项构建前摘要。当前源树与 APK 不含已删除登录插画；旧 1.0.25 源码 ZIP 的历史内容保留。

## 维护入口

私信请求身份集中在 `lib/features/music_platform/netease/messages/netease_message_protocol.dart`，9.5.61/9005061/Android12 与 UA 保持一致，仅两个私信读取接口使用。其他请求、写入和保存的账号身份不改变。公开参考文件及其摘要记录在 validation JSON；没有嵌入上游 Node 实现。

`netease_message_card.dart` 的 contentFields / messageEnvelope 统一消息边界，避免解析器已支持的 extra/payload/record/report 等字段提前丢失。支持受限多层 JSON；`netease_messages_repository.dart` 同时检查旧/新消息体，现代正文优先于旧兼容提示。发送者/接收者资料不能生成卡片，兼容句子和 roomId 不能生成虚构的报告或数值。

`netease_message_diagnostics.dart` 是独立的有损结构导出。未知字段名匿名化，正文/ID/链接值被删除，资料和认证字段跳过，限定 96 节点/深度7/单对象32字段/数组4项/JSON字符串32KiB。保留未知外层的匿名结构，以免新的容器被诊断入口再次丢弃。`netease_message_diagnostic_action.dart` 负责预览和显式复制，检查原账号仍有效，不自动上传/写盘，不读取整段聊天，也不接入自动日志。用户安装后如仍不显示，可把该条下的诊断复制回当前对话，无需手机连接电脑。

`BetaTabMotion.direction` 按最新反馈反转。发现→音乐→音乐库→我的：新页从右入、旧页向左出；反向新页从左入、旧页向右出。这取代 1.0.26 的相反方向约定。继续共享进入页真实进度，保持时长/曲线、玻璃、减少动态效果和最终点击目标。双平台浏览/封面持久化缓存没有改动。

## 验证与未完成验收

79 个 Beta 文件 1276 项、Stable 2 文件 19 项、保留引擎 Android 返回 1 项通过；lib/test 分析 0 问题。全量 Beta 通过后对诊断补查未知外层并跳过认证/资料字段，8 项对应文件补跑通过，统计取每文件最后完整结果，不重复累加。消息夹具全部为合成数据。实际声明式 Navigator 覆盖每个相邻 Tab、跨页跳转、半程一屏衔接及减少动态效果。

14 张生产聊天/详情/账号状态及诊断主机渲染通过；人工查看新增的窄屏聊天与预览图，320 宽/140% 文字下按钮可达、无布局异常。Windows 测试字体只由宿主加载，没有打入 APK。此项不是 Android GPU 或真实消息验证。

APK 已核对包名 com.mesting.music.beta、正式名 Mesting Music、1.0.27/code48、不可调试、min24/target36、双 ARM，原证书 SHA256 `8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333`，V2/V3、16KiB ZIP/ARM64 ELF 对齐、ARM32 ELF 对齐、ZIP CRC 均通过。双份 libflutter.so 匹配固定 manifest；7 个玻璃着色器、8 个 SDK 原生库与本机 1.0.26 原包字节相同。实际最终 APK 的生产 Range 读取器核对 3 条内置说明与离线历史。

用户这条真实记录的全部根因及实际修复尚未确认，官方网页详情手机表现、实际覆盖安装和长期原生稳定性待用户验收。不能把公开协议、合成回归或海报内容当作取得真实原始载荷，也不能称“真实记录已彻底修复”。如果仍失败，先读取用户手动提供的单条脱敏结构诊断再继续定位，避免再次仅凭自造卡片断言成功。

## 重建

Flutter 3.41.9 / Dart3.11.5：D:/CodexCache/flutter-3.41.9；JDK17.0.20.1+1、Android SDK 在 D:/CodexCache/android-build。Build Tools35.0.0、NDK28.2.13676358、Gradle8.14。构建默认入口 `tool/build_android_release_apk.ps1` 已为 1.0.27/48，使用进程局部环境、3GiB 堆/worker1，保持 pub 以重建测试后插件注册表，pubspec.lock 摘要不变。共享 pubspec 的 Stable 历史版本不代表 Beta 交付版本。

私有构建、签名、前后摘要、回归、截图、公开参考及源码冻结助手在 `.codex-artifacts/2026-10-31-release127/`，不进源码 ZIP。私钥/keystore/口令、本机配置、构建缓存、旧 APK/ZIP 也不进源码 ZIP。工作区历史 SOURCE-SNAPSHOT.json 保持 1.0.24，ZIP 内保存为明确 BASELINE 文件，并另生成当前 1.0.27 清单。

后续先读本交接、验证与实际工作区；没有新明确授权，不访问手机/ADB、真实账号或后台，不 Git 提交推送或发布。新需求继续逐题澄清、确认方案后实施；已确认选择不重复询问。
