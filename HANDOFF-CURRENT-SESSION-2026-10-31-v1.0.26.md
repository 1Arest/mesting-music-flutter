# Mesting Music 1.0.26 / code47 本地交付与接续

日期：2026-10-31，Asia/Shanghai。唯一工程根 `D:/AnLi`，分支 beta，HEAD `b6bcd5425e0df3e03febdd460b56d0ed42004c52`。本版基于本机 1.0.25 工作源码，仍是未提交工作区；没有 Git 提交推送、GitHub Release 或 music 后台发布。旧交接中的另一台电脑路径和旧“当前版本”仅代表历史时点。

用户已逐项确认：移除全部新增登录插画；补齐网易云一起听结束记录；网易云/酷狗浏览页面先显示上次成功内容再后台刷新，封面也持久化；底部 Tab 从发现向我的切换时新页由左进入、旧页向右离开，反向镜像。用户明确确认以 1.0.26/code47 实施并交付原签名 APK、完整源码 ZIP 与校验资料，不需重复问答。

## 交付入口

- [原签名双 ARM APK](release/Mesting-Music-v1.0.26.apk)
- [完整源码 ZIP](Mesting-Music-v1.0.26-source.zip)
- [APK 身份、签名、引擎与资源核验](release/Mesting-Music-v1.0.26-verification.json)
- [源码逐文件与 ZIP 核验](release/Mesting-Music-v1.0.26-source-verification.json)
- [APK/源码 SHA256 汇总](release/Mesting-Music-v1.0.26-SHA256.txt)
- [安装验收](docs/INSTALL-v1.0.26.md)、[修改说明](docs/fixes-2026-10-31-v1.0.26.md)、[主机验证](docs/validation-2026-10-31-v1.0.26.json)

大小和摘要以外置核验 JSON 与 SHA256 文件为准，避免把源码 ZIP 自身摘要回写进 ZIP 内造成自引用。ZIP 内 `SOURCE-SNAPSHOT.json` 是 1.0.26 当前完整清单；工作区原有 1.0.24 历史清单保持，另存于 ZIP 内 `SOURCE-SNAPSHOT-v1.0.24-BASELINE.json`。冻结源选择包括当前 Git 跟踪文件与未忽略新文件，不能只取 Git HEAD。

1.0.25 的原签名 APK 和完整源码 ZIP 保留原字节，其源码 ZIP 中的旧插画也保持历史归档；当前源树和 1.0.26 包均不再包含该插画组件与素材。原签名私有档案、此前本机 APK/源码 ZIP 及固定引擎均保留，最终交付核对前后摘要。

## 实现与维护入口

1. 私信读取由 `NeteaseApi.request` 的 `mobileMessages` 路径限定到 private users/history 的 Android eapi 请求，账号 jar 与发送保持隔离。旧桌面身份返回的兼容文本不能直接当作记录。消息边界补留移动端载荷，`NeteaseMessageCard` 受限遍历后优先选择结束报告，沿用实际标题/说明/时长和已验证官方链接。
2. `BrowseResponseCache` 是独立响应快照层，`BrowseCacheRoutes` 是明确只读白名单；`CachedBrowseLoader` 对接分页页面，`cachedBrowse` 对接 FutureProvider。缓存记录平台/账号作用域及规范化查询摘要，不序列化请求认证头。凭据代次与编辑撤销 epoch 同时守卫迟到回调。
3. 首页、分类、搜索、歌单/专辑/歌手歌曲列表、音效、通用内容与已接入评论页按消费的键更新；双平台个人音乐库的数据流直接订阅对应键。个人音乐库仍属于原平台，未写入游客或另一平台数据库。分页替换仅影响该批次，保留后续页、滚动和输入。
4. 每次成功读取落盘，不等退出回调。数据 32 MiB/800 条、单条 8 MiB、解码工作集 4 MiB/24 条，后台刷新最多 3 项，同一成功响应间隔 60 秒，手动刷新跳过间隔。业务拒绝和刷新失败保留旧快照；成功编辑撤销旧缓存，不重放写请求。认证、私信、直播状态、播放/下载 URL 和写操作保持实时。
5. `PersistentNetworkImageCache` 保留校验、按尺寸解码和公开图片头，扩展普通封面，启动恢复索引。图片最多 256 MiB/4000 张，保留 ID/版本/缩略图尺寸，已知签名变化合并。两种缓存启动时仅清理自己精确命名的中断临时文件。存储未就绪的独立入口继续原实时读取；真实应用在音频/视觉启动阶段并行预热。
6. `BetaTabNavigation` 的实际出发/目标与共享进度用于 `BetaRootTabMotion`。声明式路由替换时，旧页自己的动画不一定逆播，因此两页应由进入页的真实进度驱动，不能重新退回固定入场方向。保留原速度、玻璃和减少动态效果；详情/边缘返回继续原逻辑。
7. 登录页恢复原 SafeArea 与表单，删除原图、插画组件和 pubspec 声明；二维码保留。公开版本、离线历史与构建默认值统一 1.0.26/47，共享 pubspec 的 Stable 历史版本不是 Beta 交付版本。

## 已验证与界限

主机结果按每文件最后完整运行合并：78 个 Beta 文件 1267 项通过，Stable 2 文件 19 项通过，保留引擎 Android 返回 1 项通过，lib/test 分析 0 问题。重复运行不累加：最终全量日志中一处测试用固定等待时间检查落盘而失败，已改为等待实际通知/持久化内容，该文件及相关接入用例补跑通过，明细见验证 JSON。

实际首页 Provider、网易云和酷狗个人音乐库在重新创建缓存实例后的旧数据先显和后台更新通过；账号隔离、离线、损坏、中断写入、容量、失败编辑保留与成功编辑撤销通过。私信模拟请求在真实加密传输边界检查移动身份，合成消息卡片与会话预览通过。实际声明式路由在半程核对新旧页方向与一屏宽衔接，反向和减少动态效果通过。20 张登录页/3 张比较图按生产组件渲染，通过字体由私有宿主夹具提供，不作为 Android GPU/字形验收。

最终 APK 使用 `com.mesting.music.beta`、Mesting Music、1.0.26/code47、不可调试、minSdk24/target36、双 ARM。原证书 SHA256 `8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333`；V2/V3、ZIP CRC、16KiB APK 对齐与双 ARM ELF 对齐核对。两份 libflutter.so 匹配固定 manifest，完整引擎许可存在；7 个着色器和 8 个 SDK 原生库与本机 1.0.25 比较一致。包内不含已删除插画、测试字体或 IntegrationTestPlugin，实际 APK 的生产 Range 读取器核对五条版本说明和离线历史。

本次没有手机、ADB、真实平台账号、私信发送或 music 后台操作，没有安装 APK。截图中那条真实记录与官方详情 WebView、手机清后台恢复、双端退出和原生长期稳定性仍需用户验收；合成夹具和磁盘实例重建不等于已经完成真实账号/手机测试。不能声称任意手机零帧显示、持续 120 FPS 或永久修复原生崩溃。

## 重建和私有证据

本机 Flutter `D:/CodexCache/flutter-3.41.9` / Dart 3.11.5，Temurin 17.0.20.1+1 位于 `D:/CodexCache/android-build/jdk/`，SDK 位于 `D:/CodexCache/android-build/sdk`，Build Tools 35.0.0、NDK 28.2.13676358、Gradle 8.14。构建使用进程局部 3GiB 堆和 worker1，未改变全局 Java/Flutter 设置。

入口 `tool/build_android_release_apk.ps1 -VersionName 1.0.26 -VersionCode 47 -FlutterSdkRoot <Flutter3.41.9根目录>`，保留 pub 以重建测试后可能残留的插件注册表，依赖锁不得漂移。最终签名使用用户私有保留密钥与环境变量口令，不能生成新密钥冒充升级。

私有日志、冻结助手、签名核验与旧冻结物前后摘要在 `.codex-artifacts/2026-10-31-release126/`，登录渲染在其 `ui/login/`。此目录不进入完整源码 ZIP；源码包含必要第三方源码、固定引擎及许可，排除应用私钥、keystore、口令、本机配置、构建缓存、旧 APK/ZIP 与私有证据。

新接手先读本交接和验证 JSON，核对工作区及冻结产物，不 reset/clean 或覆盖交付。新需求继续按一次一问、确认方案后实施的约定；没有新的明确授权，不访问手机/真实账号，不 Git 提交推送或发布后台。
