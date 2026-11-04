# Mesting Music 1.0.28 / code49 本地交付与接续

日期：2026-10-31，Asia/Shanghai。唯一工程 D:/AnLi，beta / b6bcd5425e0df3e03febdd460b56d0ed42004c52。基于本机 1.0.27 的全部工作源码继续更新；1.0.25～1.0.28 的源码改动保留在未提交工作区，不 reset/clean、不从旧远端覆盖。未 Git 提交推送、GitHub Release、music 发布或手机安装。

## 本次确认与交付

用户确认缓存刷新要保留旧内容与封面，等新内容和对应封面就绪后共同替换，失败保留旧内容；首次无有效缓存仍可占位。Tab 每次点击立即响应，允许中途打断或反向，方向沿用 1.0.27。已确认实施 1.0.28/code49，交付原签名 APK、完整源码 ZIP 与校验资料，不再重复询问。

- [原签名双 ARM APK](release/Mesting-Music-v1.0.28.apk)，107599566 字节，SHA256 `7157782d1dc56b000d8a965d33bac3fae4881321806e05aa33208aee4dde5ac1`。
- [完整源码 ZIP](Mesting-Music-v1.0.28-source.zip)，保存当前全部工作源码、固定引擎和许可证，不只是 Git HEAD。
- [APK 核验](release/Mesting-Music-v1.0.28-verification.json)、[源码核验](release/Mesting-Music-v1.0.28-source-verification.json)、[摘要汇总](release/Mesting-Music-v1.0.28-SHA256.txt)。ZIP 自身摘要在外置资料中保存，避免自引用。
- [安装验收](docs/INSTALL-v1.0.28.md)、[修改与维护](docs/fixes-2026-10-31-v1.0.28.md)、[主机验证](docs/validation-2026-10-31-v1.0.28.json)。

构建前保留的 40 项历史 APK/源码 ZIP、私有签名和签名备份逐项核对原字节。登录插画继续移除，旧冻结物中的历史内容保持。

## 维护入口

`BrowseResponseCache` 增加不依赖 Flutter 的缓存预热与刷新准备回调，在新响应写盘/通知前等待图片准备成功。Beta 启动连接 `ArtworkRefreshCoordinator`，网易云和酷狗原有浏览缓存通道共同生效。账号代际变化仍阻止过期结果发布。

准备器根据旧响应字段位置找到当前可见图片的替换，并补充前 12 张种子封面；图片下载、首帧解码、整组留存检查完成后才发布新响应。最多 3 路并行、64 个选中图片、20 秒刷新等待、24 MiB 解码预算；不足时保留旧内容。冷启动只从已有磁盘文件预热前 12 张，最长 2 秒。数据/磁盘图片原有限额继续有效。

`persistent_network_image_cache.dart` 增加只有哈希的内容到文件索引，以及显式等待的索引落盘；不让同步 peek 偷启异步文件写入。`media_uri.dart` 的内容标识归一化仅对已知公开 CDN 移除缩略图/临时参数，未知主机保留查询参数。`RetainedArtworkFrame` 独立持有最后解码帧，图源切换和失败期间保留旧画面，准备好的图片可直接提供替换首帧，图片 owner scope 改变时清空。

根 Tab 使用 `beta_tab_shell.dart` 与 `BetaRootTabViewport`，由 PageController 从实际当前位置即时改向，四个分支保留状态，视口只绘制可见页面；外层完整玻璃保持。`BetaTabNavigation` 只处理有效点击与同帧重复，不等待动画完成。`BetaTabVisibility` 让隐藏分支不抢底部搜索栏。

方向仍为发现→音乐→音乐库→我的：新页从右进入，旧页向左离开；反向从左进入。查询参数根链接进入独立内部 `/view` 二级页，避免压入重复 StatefulShell 导致 GlobalKey 冲突；逻辑父级返回已识别别名。搜索路由使用即时交接，避免暂停的分支 Navigator 在搜索关闭时残留退出动画。详细代码边界与注释见修改说明。

## 已完成验证与待验收

80 个 Beta 文件 1286 项、Stable 2 文件 19 项、保留引擎的 Android 返回主机用例 1 项通过，lib/test 分析 0 问题。完整 Beta 回归后补跑最终图片整组留存相关 8 个文件，统计取每文件最后完整结果，不重复累加。生产返回用例包含搜索、每日推荐、最近播放等层级，并在每个步骤检查异常。

7 张生产缓存/ArtworkImage/Tab 视口的主机渲染通过，已人工查看关键帧。等待封面期间整页 RGBA 与旧画面逐像素一致；新文字首帧已有解码新封面，没有缓存等待占位图；改向瞬间像素不跳变，后续向新方向连续移动。另有合成回归覆盖失败、账号改变、scope、冷磁盘恢复、图片比例、容量并发、快速连点、页面状态和搜索归属。Windows 检查字体不进 APK。这些不代表实际手机 GPU 或真实账号验收。

APK 核对正式名称 Mesting Music、包名 com.mesting.music.beta、1.0.28/code49、不可调试、min24/target36、双 ARM。原证书 SHA256 `8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333`，V2/V3 签名、16KiB ZIP/ARM64 ELF 对齐、ARM32 ELF 对齐和 ZIP CRC 已验证。两个 libflutter.so 匹配固定 manifest，7 个玻璃着色器与 8 个 SDK 原生库同本机 1.0.27 原包字节一致。最终 APK 由生产 Range 读取器读取 3 条内置更新说明，与离线历史一致。

本轮没有访问手机/ADB、真实账号或后台。实际覆盖安装、清后台后的手机封面切换、真实网络与 GPU 下快切、长期原生稳定性由用户验收。一起听真实结束记录问题沿用 [1.0.27交接](HANDOFF-CURRENT-SESSION-2026-10-31-v1.0.27.md) 的未验证状态，未取得用户真实载荷，不能声称已修复；仍失败时读取用户手动提供的单条脱敏结构诊断后再定位。

## 构建与接续

Flutter 3.41.9 / Dart3.11.5：D:/CodexCache/flutter-3.41.9；JDK17.0.20.1+1、Android SDK 位于 D:/CodexCache/android-build。Build Tools35.0.0、NDK28.2.13676358、Gradle8.14。构建入口 `tool/build_android_release_apk.ps1` 默认 1.0.28/49，进程局部环境、3GiB 堆、worker1，保留 pub 重建测试后的插件注册表。pubspec.lock 摘要不变，共享 pubspec 的 Stable 历史版本不代表 Beta 交付版本。

私有构建/测试/渲染/签名/冻结助手位于 `.codex-artifacts/2026-10-31-release128/`，不进入源码 ZIP。变化对照 v1.0.27 原源码 ZIP 记录于该目录的 changes-from-v127.json/diff。源码包包含当前工作改动与源码测试，排除私钥/keystore/口令、本机配置、构建缓存和旧 APK/ZIP。工作区 SOURCE-SNAPSHOT.json 历史基线 1.0.24 保持，ZIP 内另存 BASELINE 文件与当前 1.0.28 清单。

接手先读本交接、验证及实际工作区，不用历史“最新”覆盖当前状态。没有新的明确授权，不访问手机/ADB、账号或后台，不提交推送或发布。新需求按逐题澄清、确认方案后实施；本轮已确认选择不重复询问。
