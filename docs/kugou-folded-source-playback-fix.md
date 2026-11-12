# 折叠音源首次切换卡住与酷狗缓存代理错误

## 复现环境与准确路径

2026-11-11，OPPO 平板，已安装 App 1.0.98（119），非计费 Wi-Fi，当前界面登录网易云。
搜索《天龙八部之宿敌》→ 第一条“网易云 · 原唱 · 完整版”→“选择音源（2）”→“酷狗 · 原唱”。
这里指同一首歌折叠组中的酷狗候选，不是列表中另一条独立酷狗结果。

实机旧包观察：22:17:12 点选后，22:18:03 仍为 CONNECTING，播放位置和缓冲均为 0，未见新的 ExoPlayer 初始化。重新打开同一折叠菜单，再选择当前酷狗候选后才进入播放器初始化；随后缓存代理报错，直连重试后可以播放。两段现象分别处理。

## Bug 1：列表行替换取消了自己的异步播放

搜索行用 `ValueKey(track.id)`。`chooseSongSource` 把该行从网易云歌曲 ID 换成酷狗歌曲 ID，旧行随之销毁；旧代码随后仍用旧行的 `context/ref` 调用 `playBetaSelection`。
播放入口把 `context.mounted` 传给处理器作为任务有效条件。异步登录/地址解析期间，该条件随行销毁而失效，任务中断；如果此前已经发布 loading，旧代码没有在这条提前退出路径清理 `_pendingQueueEpoch`，界面会一直显示加载。
同一酷狗候选再选一次不改变行 ID，因此能绕过第一处问题。这与实机行为一致；回归测试专门让解析结果在旧行销毁后返回。

修复：

- 换源选择及播放任务由稳定的搜索结果页面持有，列表行仅触发回调。
- 保留候选有效性、查询和账号校验；解析过程中切换查询、切换账号或退出页面仍取消旧任务。
- 异步队列加载退出时只清理属于自己的 pending 标记。旧任务不得清除新任务的 loading，也不得用旧结果覆盖新选择。

## Bug 2：重复 Accept-Ranges 导致本机缓存代理返回 500

实机日志直接记录 `HttpHeaders.value` 读取多值 `Accept-Ranges` 抛出 `HttpException`，本机代理返回 500。现有直连降级随后成功，但多付出重试等待。
问题位于仓库内固定版本 `just_audio` 的 `LockCachingAudioSource._fetch`，不是要求整首下载完成才播放。

修复：遍历所有响应头值，再按逗号拆分，忽略大小写和边缘空格，仅明确的 `bytes` 声明表示支持字节范围。兼容重复行、合并行；`none`、缺失或不认识的单位不声明范围支持。
代理仍边接收边缓存并交付音频；保留原有网络超时与直连降级。

## 回归覆盖

- 真实搜索列表、折叠选择弹层、网易云当前账号和已保留酷狗登录，延迟解析直到旧行卸载，验证首次换源能继续。
- 查询改变、账号改变和页面退出仍取消旧解析。
- 真实音频处理器：失效任务的晚成功/晚失败清理加载状态；旧任务完成不能影响新加载。
- 本机真实 HTTP：重复头、逗号合并、大小写/空格、none、未知单位和缺失头；首批字节在完整缓存产生之前可读，完成后缓存字节一致。

## 本次验证结果

- 旧代码 e6c94be：4 个关键用例按预期失败，分别为折叠换源首次播放、失效加载的晚成功/晚失败、重复响应头。失败断言包括加载一直停在 `loading`，以及 `More than one value for header accept-ranges`。
- 修复后：7 个测试文件共 **40 项通过**，包含本次新增的 13 项与既有播放过渡、缓存降级、融合搜索、跨平台账号/音源范围回归。
- 修改的应用源码和新增测试静态分析：`No issues found`；`git diff --check`（兼容既有 CRLF）通过。
- 验证使用已缓存依赖的独立工作目录，没有改动项目依赖、SDK 或版本号。

可复核命令（依赖准备完成后，在项目根目录执行）：

```text
flutter test --no-pub --flavor beta test/kugou_cache_headers_test.dart test/playback_load_owner_test.dart test/search_source_playback_owner_test.dart test/playback_transition_test.dart test/release_153_audio_test.dart test/search184_fusion_test.dart test/playback184_source_scope_test.dart
dart analyze lib/features/search/presentation/apple_search_results.dart lib/core/audio/mesting_audio_handler.dart test/search_source_playback_owner_test.dart test/playback_load_owner_test.dart test/kugou_cache_headers_test.dart
```

## 发布边界

本次独立修复基于公开 `beta` 分支 e6c94be，不包含此前播放器外观 PR 的改动，不更换账号权限策略，不改第三方会员校验，不包含 token、真实音频地址或完整设备日志。
自动化回归与静态检查结果记录于本次 PR。未构建/安装新 APK；作者合并并打包后，仍需在上述准确路径做 Android 实机确认。旧包的失败复现不能算作修复后实机验收。
