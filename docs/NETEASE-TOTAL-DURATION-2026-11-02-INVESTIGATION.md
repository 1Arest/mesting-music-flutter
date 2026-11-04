# 网易云历史总时长：2026-11-02 调试记录

**后续用户验收未通过：用户安装私有候选后确认官版“最近播放”和“今日收听”均不再更新，原有版本可更新这两项。原生文件回执不能证明消费/索引；本次实验未恢复历史累计，且出现功能回退。用户已确认1.0.39保留UI并停用原生试验，新播放恢复原有weblog，旧原生open/queued及已派发/接收/未知记录均保留，不改投、不盲发。以下原生样本和回执仅保留为调查证据。**

本记录属于1.0.37冻结之后的接续资料，不修改原APK或源码ZIP。日期为Asia/Shanghai。

## 已确认的目标及授权

用户确认：手机Mesting Music 1.0.37，普通听歌及一起听均可增加官版今日收听，但隔天仍不计入历史总时长；官版自身播放会计入。用户已确认继续调查和修正，并明确授权连接手机调试；随后将手机交给本次连续调试。该授权不包含Git推送、公开发布或music后台操作。

工程仍为D:/AnLi、beta/b6bcd542，保留全部既有未提交改动。此次没有执行reset/clean/stash/pull或切分支。先前清理的依赖已用`pub get --enforce-lockfile`恢复，pubspec.lock摘要保持。

## 已确定并修正的独立问题

1. 1.0.37把周期报表中的分钟当成秒。手机实测：官版今日6小时12分钟、本周6小时26分钟；Mesting显示今日6分钟、当月6分钟。两端历史总时长都为5609小时31分钟。保存的官版JS模块69650中，`dp`按分钟格式化，`r8`按秒格式化；84513用`dp`消费周期`playDuration`及日明细，82796用`r8`消费历史`totalDuration`。现在仅在周期DTO解析边界把分钟转成内部秒，历史总时长保持原秒数。旧37文档的“全部时长字段按秒解析”为历史错误，不能再沿用。该显示修正不等于历史累计问题解决。
2. 旧上报把HTTP200且业务`code`缺失/非法的结果也当成功。播放日志现在必须收到明确code200；缺失/非法回执归unknown，不自动重发；其他API保留原可选code契约。
3. 若第一次ready+playing发生于seek期间，旧实现可漏掉首次启动上报。seek结束后现在重新检查真实播放条件、当前账号和防重复状态；seek期间不计时。

## 手机实际官版及上传链路

实际安装官版为9.5.12/code9005012，区别于以前调查的9.6.15。只读拉取的实际APK：201332834字节，SHA256 `5082d1ca510ee061bb6b6270c6a2fe0b56a90b7574a023433f3637dede0c0695`。仅分析副本，没有修改/替换手机官版。

- `ms0.w0.R2`仍分别构造真实`realtime`、倍速`time`及原始`startlogtime`。它本身没有Mesting桌面载荷中的`mainsiteWeb`等字段。
- `StatisticImpl.logJSONRealTime`可同时交给实时stub及BI stub；实际`com.netease.cloudmusic.k.h`配置实时stub为null，BI使用`xf2.p.a(1000)`、`StatisticStubServiceImpl.newStatisticStub(s0)`及`m1`。因此不能仅凭“RealTime”名字断言还需额外写一次心跳。
- 实际BI接口为`clientlog/encrypt/upload`。普通旧队列的`clientlog/upload` ZIP封装不是本次实际现代BI配置，不能直接拿来替换。
- `StatisticNetworkAgent`提交多个原生文件，`MultipleUploadEntity.UploadFile.create`规定表单字段`file`、原文件名及`multipart/form-data`类型。服务端JSON的`data.successfiles`逐文件回执与HTTP/code200分开处理。
- 服务端最终纳入总时长的规则仍不可从客户端静态代码推断；没有发现可据以纠正已接收十月旧记录的协议。

关键REA Evidence：实际初始化`ev_180db7a568ab83daa36db2e2df51a7959bafacba40dbe04647419476d9d8bb0f`；实时/BI分发`ev_b306379c1cda18678365970e5e2f756506c8db61a8108200d2c8d6f5633853c8`；现代配置`ev_abe5bf664171a2690585436e965722d7dddaaec6ada8bed8706edf089518c03e`及`ev_b6058913837f2f9bdea0cad51f958036264d21791627bcd6d1362c65839a30c4`；原始逐条格式`ev_ed951de46a909506566514ee7ab1207af5e4a266fe78031fc18d3238398aab71`；逐文件回执`ev_9fc5f7870402bb05c4870d4773a5f552c7367aacb29bb54e038be8dc5962c6dd`；multipart`ev_93f0032d0ca9dea93574f1b28ea6c39948e131271f5ba1b1e10208fd318f48b1`及`ev_3a1eb77824d49a1c4a4cccb20303c16172eefa3fdfcb80b0e5b1413a23f25b25`。

## 原生容器独立实现与边界

当前Windows REA不支持Android ELF深度反编译，未安装其他反编译环境。使用已有NDK的原始反汇编，另在手机`/data/local/tmp`的独立shell进程运行无账号本地fixture。它只写固定`fixture`样本，回调没有任何网络实现，不读取应用数据。另一个明确标记的受控fixture仅替换其私有库副本的随机数函数，用已知非秘密key核对独立编码器；没有替换已安装官版的库。

独立Dart编码器重现NCBL v3头、UUID派生nonce/counter、原协议raw-RSA key封装、ChaCha20、Zstandard原始块及逐块序号。不捆绑官版libbilog/libnblog，不引入新依赖。RFC8439标准向量及受控原生样本逐字节比较通过。大载荷使用同一合法Zstandard原始块格式，而不是宣称完全复现官版压缩器的选择策略。原协议弱key封装仅用于兼容，不可用于本机凭据存储。

新候选通道只有显式`MESTING_NATIVE_PLAYBACK_LOGGING=true`时才给新播放保存protocolVersion3。旧queued/open保持原传输；accepted/dispatched/unknown/rejected不转码、不重发。新序号与dispatched状态在SQLite事务内一次性写入，账号分别计数；失败或未知不切换其他写接口。只保存实际事件时间，重启不改成重传时间。完成标为playend，其余未能确定的边界保留interrupt，不把所有切换冒充自然播放完毕。

Cookie仅在内存中的原生文件头及固定网易云HTTPS请求内使用，不写入日志/公开资料；本地诊断只输出真实秒数、开始/结束类型、通道、规范化结果和数字业务码。

维护入口：`netease_native_log.dart`、`netease_native_transport.dart`、`netease_native_journal.dart`；API账号代次检查、repository路由、reporter新事件标记与claim分别留在原职责层。普通发布构建目前默认不启用候选开关。

## 主机与包验证

- 最终相关回归为10个文件76项全部通过，包含单位/足迹UI、上报安全、原生codec/transport及既有107、112、114、135、137相关行为。早期运行与最终运行有重叠，不叠加计数；没有把旧1.0.37的1404项结果当作本轮全量回归。
- 原生codec包含RFC8439向量和受控原生独立字节向量；transport覆盖逐文件成功/未知/拒绝、无盲发、序号事务、原始事件时间、账号替换及退出登录后的迟到响应。
- 最终`flutter analyze --no-pub`为0问题。完整记录在私有`focused-final.log`、`analyze-final.log`。
- Android Release离线构建及其检查成功。已用原证书签名并于10:45覆盖安装私有候选`1.0.38/code58`。SHA256 `ff7602cdb254845b7eb09c6224b27ba39aee894b34bfa34ca4751a7c904d5452`，85939847字节。
- `libapp.so`为ARM64，保留的引擎/SDK同时包含双ARM共享库。固定64位引擎摘要、7份玻璃shader、原证书及zipalign均核对通过；没有捆绑官版原生库。详见私有`candidate-verification.json`。
- 保留code58用于原1.0.37同码覆盖恢复，不清数据。候选不是正式1.0.38/code59交付；源pubspec/公开版本说明未升级，普通构建默认不开启原生候选开关。
- 原58份冻结APK/ZIP回核全部未变，见私有`frozen-after.json`。

## 手机采样与待验收

10:48:49新播放的启动日志已走`android-bi-v3`，收到当前文件名的成功回执，业务code200。10:51:17切换结束的真实播放日志`mediaSeconds=147`、`realtimeSeconds=147`也收到逐文件成功回执。当时播放器恢复了用户原有的一起听房间；本次没有发起邀请、发送聊天或主动退出该房间，不能将这次采样写成独立普通模式验收。切换后下一首启动回执同样成功，之后已用媒体暂停指令暂停；新鲜UI树确认控制为“播放”、进度0:26。该段真实短播放保留为正常open记录，不为测试强行补造结束或重发。

10:54:07候选足迹读取：今日6小时48分、当前月7小时2分、历史总时长5609小时31分。随后重新进入官版足迹，今日6小时48分、本周7小时2分、历史总时长5609小时31分；两端显示一致，修正后的小时/分钟格式已在真机核对。此基线仅有分钟显示精度，不能反推精确秒数。

09:51至10:54整个区间的今日增量并非隔离的147秒实验，含前期实际播放及账号多端数据，不能全部归因于候选。测试证明的是新容器的真实开始/结束文件被接收，不是总时长累计成功。保留官版历史基线5609小时31分，后续应在只使用Mesting候选的实际听歌后隔天复查；若仍不增长，继续调查服务端纳入条件，不能盲发旧记录。

私有`runtime-safe.json`只含允许的上报字段；首条58秒`weblog`为候选启动后恢复的一条旧真实未结束记录，未转换为原生写入。三个新`android-bi-v3`回执对应新播放开始、147秒结束及下一首开始，均code200、accepted。本轮没有将历史accepted/unknown记录重新发送。完整REA证据最终导出73条、5666015字节到私有bundle；导出工具的unknowns=0只描述其证据容器，不表示本问题没有业务未知。

真实文件回执、新播放今日增量、历史总时长是不同的验收层级。隔天历史总时长及独立普通模式尚待验证，不能以本地向量或HTTP/code200宣布问题已修复。

私有完整证据：`.codex-artifacts/2026-11-02-total-duration-debug/`及`2026-11-02-total-duration-investigation/`，包含原APK、原生fixture、截图、日志、REA导出及候选包。不得纳入公开源码ZIP或批量清理。原58份冻结APK/ZIP的保护清单及最终回核见本次`frozen-before.json`、`frozen-after.json`。

十月683分钟继续保留独立未追回状态；280 accepted、12 unknown、0待发的旧报告不重复索取或盲发。一起听累计此前已验收，结束私信问题仍独立未确认。本轮未提交、推送、打标签或发布。
