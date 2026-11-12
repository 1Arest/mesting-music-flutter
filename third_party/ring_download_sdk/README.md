# Ring Download SDK

Flutter Android APK 下载 SDK。已有更新后台选版本和来源，SDK 自动完成 HTTPS、P2P/P8P、安装级设备标识、下载会话、续传、校验、取消和下载诊断。App 保留更新 UI、资格判断和系统安装流程。

**[完整开发者手册](https://download.csnas.asia/sdk)** · **[后台接口参考](https://download.csnas.asia/docs)** · [平台维护的文档源](../../docs/sdk-integration.md)

## 当前版本

当前正式源码发布版本为 **1.2.0**。服务端声明候补能力时，建连或握手失败后整轮最多尝试4个不同普通身份；默认同时最多2个普通原生所有者，显式四路竞速时最多4个，已接纳普通正文仍最多2路，共享4片/4MiB。创建未返回或释放失败继续占位，前缀优先和既有请求预算保持。

将 `p8pPeerRaceLimit` 显式设为 3 且服务端支持候补时，SDK 先尝试两路普通节点，约 2 秒尚无普通节点交付校验首片时可补试第三路，已打开但没有校验首片的通道也可触发补位。默认两路，普通节点正文最多两路。SDK 实例内短期优先尝试已交付校验首片的在线登记，并输出建连和首片失败的分阶段诊断。源端口增强默认关闭。晚到的有效 Trickle 候选可获得一次至多 1 秒的检查余量，仍受原始总期限约束。失败诊断可提供不含地址、端口和候选标识的 ICE 检查收发计数。 两路和三路模式下，握手后未交付校验首片的普通节点可在实际释放后补位。正文传输中，失败节点释放出的名额会立即唤醒候补发现，另一条仍在协商的 ICE 连接可继续。种子重试会并行关闭旧连接的两端，等待双方确认后再建立新连接。协商批量候选后，候选队列暂满或处理超时可重发同一批一次。沿用原建连期限、并发上限和发现次数预算。上述连接策略沿用 1.1.9，历史验证见 `validation/release-1.1.9.json`；本版统计接口与 Android 验收见 `validation/release-1.2.0.json`。

1.1.5 对已供过校验片的 RTC 来源增加一次请求级软救援：仅取消卡住前缀，不误伤同源其他请求；真实取消确认或关闭前仍占槽位，完成一次试片SHA后才重新加入，重复停滞退役。默认 `p8pPeerRaceLimit: 2`；显式设为4时只扩大建连竞速，普通正文仍最多两路，原整轮四身份、四槽/4MiB及服务端种子独立计数不变。`p8pSourcePortDiversity: false` 保持默认，开启需要对端及服务端协商和预算支持，不能保证穿透或绕过VPN。

已有连续正文且仅剩一个本地RTC接收帧、并不超过片长四分之一时，按替代来源近期已校验速率保留有界恢复机会，最多增加一个既有救援周期；原硬截止、物理退役、HTTPS立即开始和外部COS独立保持。部分正文不计校验贡献，HTTP、零进度及非尾部沿用原救援规则。已接纳普通来源在正文传输中失败时，等请求、来源和原生所有者实际退役后可在原四次普通候选预算内补位；保留旧来源身份与历史统计，不重试已消耗身份。

1.1.5 历史验收：精确候选1.1.5-dev.5完整635项回归和静态检查通过，正式版只调整版本文字。平板实际冷下载155305939字节并通过整包SHA、App取消与资源释放；另以真实Android原生WebRTC和本机HTTP完成三种9MiB+31字节合成文件救援场景，均通过整文件SHA、槽位和原生对象归零。原诊断夹具在扣住get后错误地转发cancel的失败和修正、构建器仅因声明版本元数据写回而失败的记录均保留。详见`validation/release-1.1.5.json`；这些结果不证明历史公网0B根因、所有NAT、固定速度、长期能耗或正式宿主签名安装。

源码包：[1.2.0](https://download.csnas.asia/static/ring-download-sdk-1.2.0.zip)。`enableP8P`默认false，由接入方明确开启。

Android分享仅在明确前台、非计费Wi-Fi、业务许可、文件校验和资源状态都允许时运行。手机进程共享1个接收方、正文256KiB/s预算及最多256KiB突发；信令、协议头和重传另计。低电量、省电或温度异常暂停，退后台停止资源观察，不创建后台常驻。B/Linux不采用手机限速。宿主仍须保存收据、重新授权并调用`restoreSharing`；开启配置不会自动找到分享文件。

新接收器按手机的单片容量调度。旧端边界和本版固定输入验收见`validation/release-1.1.5.json`；源码、实验室和单台平板通过不代表正式宿主、所有公网或蜂窝已验收。App开发者替换依赖、执行flutter pub get并沿用原签名打包，已安装App不会因SDK发布自动更新。

历史 [1.1.9](https://download.csnas.asia/static/ring-download-sdk-1.1.9.zip)、[1.1.8](https://download.csnas.asia/static/ring-download-sdk-1.1.8.zip)、[1.1.7](https://download.csnas.asia/static/ring-download-sdk-1.1.7.zip)、[1.1.4](https://download.csnas.asia/static/ring-download-sdk-1.1.4.zip)、[1.1.3](https://download.csnas.asia/static/ring-download-sdk-1.1.3.zip)、[1.1.2](https://download.csnas.asia/static/ring-download-sdk-1.1.2.zip)、[1.1.1](https://download.csnas.asia/static/ring-download-sdk-1.1.1.zip)、[1.1.0](https://download.csnas.asia/static/ring-download-sdk-1.1.0.zip) 与 [1.0.3原P2P](https://download.csnas.asia/static/ring-download-sdk-1.0.3.zip) 归档保留原文件和摘要。

新 App 使用下载平台分配的自己的 `appId/slug`、Android 包名和发布 APK。App 开发者准备原安装签名、业务更新响应及 UI/安装入口；业务后台准备可修改的完整主下载链接和自己的 COS/CDN 地址。新 App 沿用 LifeRing 相同的下载字段契约，无需复制其业务后台或其他功能。

## 最小接入

```yaml
dependencies:
  ring_download_sdk:
    path: ../ring_download_sdk
```

```dart
import 'package:flutter/widgets.dart';
import 'package:ring_download_sdk/ring_download_sdk.dart';

WidgetsFlutterBinding.ensureInitialized();
final sdk = RingDownloadSdk(const RingDownloadConfig(
  appId: 'your-app',
  enableP8P: true, // 1.1.4 正式版显式开启 P8P
  allowSharing: false, // 接入方明确选择；LifeRing 沿用 true
));
// 业务后台先完成 hasUpdate、账号、灰度和来源选择。
final task = sdk.download(RingDownloadRequest.fromLifeRing(response));
final result = await task.completed;
await result.revalidate();
// 调用 App 原安装器，核对包名、签名与系统授权。
// 更新协调器不再使用时：await sdk.dispose();
```

执行 `flutter pub get`，沿用宿主的构建、签名和发布流程。一个更新协调器持有一套 SDK，不在页面中重复创建。稳定版 1.0.3 的初始化不传 `enableP8P`。

## SDK 自动处理与宿主配合

| 已封装，不用 App 重写 | 宿主仍需做 |
|---|---|
| 随机安装级 X-Device-Id 的生成和保存；不读取 IMEI | 配置 appId、版本、SDK 与原安装签名 |
| App 版本读取、HTTP 会话、幂等键和 P2P token | 先按业务规则选定更新，传入响应 |
| Range/ETag 续传、节点发现、ICE、信令与数据通道 | 绑定 task.progress、取消和错误显示 |
| 分片及整包校验、收据、请求取消与资源释放 | completed 后 revalidate，并调用原安装器 |
| 网络插件和默认生命周期观察、分享限制 | 明确分享授权；选择自管生命周期时传状态 |
| 下载/流量结果及固定诊断字段 | 需要安装统计时调用安装记忆、核对或失败回报 API |

只有导入依赖不会替换原下载入口；完成上面的标准接入后，无需按旧文档另写下载底层功能。

## 业务字段和路由

`RingDownloadRequest.fromLifeRing` 只做字段适配，不调用 LifeRing 业务接口。字段名不同的后台可映射同名字段或直接构造 `RingDownloadRequest`。

| 来源 | 必要信息 | 行为 |
|---|---|---|
| 本站主副站的本应用 /appId/download | releaseId、versionName、downloadUrl、准确 fileSize 和 sha256 | HTTPS 立即开始，按实际能力加入 P2P/P8P |
| 外部 COS/CDN HTTPS 直链 | downloadUrl；大小/SHA 可省略或为 0/空 | 直接 HTTPS，不请求本站 health、manifest、会话或统计 |

可选字段：downloadBackupUrl、downloadEtag、downloadVersionCode。业务 versionCode 不作为实际 APK 构建号；downloadProtocol 不是 P8P 开关。URL 要求 HTTPS443、无用户名密码和 fragment、文件上限 1 GiB。

主下载地址选本站时，业务后台从本应用 health 取得主副地址、SHA、大小、文件名和版本；选 COS 时直接下发，不统一前置 health。LifeRing 当前授权后台 health 失败不会自动采用另存的 COS 字段，需要把主字段改成 COS。SDK 不猜测灾备地址，不新增第三个 COS 候选。

已有业务更新 API 使用 `download(request)`；`downloadLatest()` 默认依赖本站 health，适合允许下载本站公开最新版的入口，不替代原业务选源。COS 签名刷新可通过业务 `refreshRelease` 回调完成，文件变更则创建新任务。

没有业务更新后台的公开 App 可用 `latestRelease()` 异步查本站更新，将返回的 `androidVersionCode` 与系统实际安装的构建号比较；更高时提示，用户确认后用 `download(release)` 下载同一份快照。SHA 用于文件身份和校验，不以“上次下载的 SHA”代替已安装版本。查版失败不能阻塞首页或其他业务，也不能显示“已是最新版”；下载后取消安装不应消除下次更新提示。完整示例见[无业务后台接入](https://download.csnas.asia/sdk#public-updates)。

该模式不自动提供账号灰度或独立 COS 取址；本站停机时跳过检查保持主业务可用，不代表仍可发现新的更新。历史 SDK ZIP 保持原文件和摘要。

## 进度、分享和安装

`task.progress` 显示真实字节，未知总长显示不确定进度；以 `task.completed` 成功为完成条件。取消使用 `task.cancel()`，等待收尾；不再使用时等待 `sdk.dispose()`。混合下载中单条 HTTPS 流不完整并不等于整包失败。

收据 `verification` 区分 sha256、sizeOnly、transportOnly。没有业务预期摘要时，本地 SHA 是文件指纹，不是发布方摘要比对证明；有预期摘要则仍强制校验。

通用 SDK 默认不分享，LifeRing 显式开启 true。开启后仅在前台、非计费 Wi-Fi、服务许可和已校验文件同时满足时上传；蜂窝可接收但不上传，退后台/撤权停止上传，不创建后台常驻服务。

安装由宿主管理。可选统计使用 `rememberInstallation(request)`、启动时 `reconcileInstalledBuild(build)` 和确认失败时 `reportInstallationFailure(request)`；打开安装器不算安装成功。外部 COS 不因统计接口不可用而阻断下载。

## 验证和维护

旧正式1.1.2的晚到节点补查最多追加8次查询、整轮最多2个普通身份；1.1.4在服务端声明候补能力时整轮最多4次不同普通身份尝试，同时仍最多2个普通原生所有者。下载完成、取消或退出时停止补查并收尾，纯HTTPS下载不额外等待。

Android API24+ / arm64，完整平台范围见 [ENTERPRISE.md](docs/ENTERPRISE.md)，构建见 [BUILD_ENVIRONMENT.md](docs/BUILD_ENVIRONMENT.md)，交付检查见 [RELEASE_GATE.md](docs/RELEASE_GATE.md)。SDK 不提供原生 AAR、iOS 或私有租户权限系统。

新接入验证本站/P8P、无节点 HTTPS、本站停机且后台主字段切 COS、COS 无摘要、错误摘要拒绝、取消/恢复、前后台/网络切换、旧版升级和正式签名安装。源码/回环与实验室通过不等于正式宿主和所有公网/蜂窝通过；结果按固定输入与验证范围记录，不承诺固定倍数或成功率。

执行 `tool/verify.ps1`；示例发布构建沿用 `example/package.cmd`。历史稳定归档及 `validation/summary.json` 保留原验证范围；本版证据见 `validation/release-1.1.4.json`，历史1.1.2证据保留于 `validation/release-1.1.2.json`。按发布方决定不追加长期耐久测试，不承诺所有网络成功率或固定提速比例。许可、provenance 和第三方通知随源码保留。


### 任务级传输统计（SDK 1.2.0）

更新页使用 `task.statistics` 和 `task.latestStatistics`，不要从日志文本推断连接状态。快照类型为 `RingTransferStatistics`，单节点类型为 `RingNodeTransferStatistics`。每个任务的快照和流独立；结束后保留最后快照并关闭流，重新下载产生新计数。活动下载约每 500ms 更新一次，状态变化和取消额外发布，不按每个数据块刷新 UI，不增加网络请求或磁盘日志。

```dart
renderTransfer(task.latestStatistics);
final statisticsListener = task.statistics.listen(renderTransfer);
try {
  final verifiedFile = await task.completed;
  renderTransfer(task.latestStatistics);
  // 沿用既有安装前校验与系统确认。
} finally {
  await statisticsListener.cancel();
}
```

| 字段 | 口径 |
|---|---|
| available | 完整统计是否可用；false 时显示未记录，不把零值当成零流量证据 |
| state / cancelling | 下载状态，以及取消请求正在等待原有清理完成 |
| receivedBytes / totalBytes | 文件进度，可能含续传前缀；总大小未知为 0 |
| httpsReceivedBytes / peerReceivedBytes / seedReceivedBytes | 本任务实际接收的正文负载，可能含重试、重复或校验失败的数据，不含握手/协议控制开销，不是网卡计费量 |
| peerVerifiedBytes / seedVerifiedBytes | 本任务通过分片 SHA 并成功写入的独立分片覆盖；重复索引不叠加，HTTP 200 重写清除旧覆盖。跨任务续传的既有前缀不冒充本轮接收 |
| bytesPerSecond / httpsBytesPerSecond / peerBytesPerSecond / seedBytesPerSecond | 约两秒滑动窗口的正文接收速率，停流后衰减；校验、取消和终态为 0 |
| estimatedRemaining | 根据文件进度推进估算的剩余时间；起步、未知总大小、停滞和校验时可为空 |
| connectingNodes / connectedNodes / receivingNodes | 下载侧逻辑连接数量；已连接不等于正在供片，接收中按最近窗口内实际正文判断 |
| nodes | 最多 32 个本任务连接历史，含安全别名 node1…node32、peer/seed 来源、连接状态、正文/校验量、近期速度；不含节点身份、IP、URL、账号、SDP 或 ICE 地址 |

单节点的 `closed` 描述任务侧停止接收，不是原生 socket 已释放的证明；原生释放仍以既有清理结果验收。统计读取错误不改变下载和校验结果。`available=false` 的兼容自定义传输实现仍可按原进度下载。

界面在有连接但没有实际正文时显示“节点已连接 · 等待数据”；有近期正文且有校验贡献时可显示“P2P 协同传输”；没有活跃节点时显示服务器下载。查找/回退的精确原因继续使用既有 `onDiagnostic` 的固定阶段/原因码，不把尝试连接写成加速成功。正文接收占比与有效分片覆盖是两种口径，不混加；校验完成以 `task.completed` 的回执为准。
