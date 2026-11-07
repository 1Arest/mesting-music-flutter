# Ring Download SDK

Flutter Android APK 下载 SDK。已有更新后台选版本和来源，SDK 自动完成 HTTPS、P2P/P8P、安装级设备标识、下载会话、续传、校验、取消和下载诊断。App 保留更新 UI、资格判断和系统安装流程。

**[完整开发者手册](https://download.csnas.asia/sdk)** · **[后台接口参考](https://download.csnas.asia/docs)** · [平台维护的文档源](../../docs/sdk-integration.md)

## 当前版本

当前正式源码版为 [1.1.2](https://download.csnas.asia/static/ring-download-sdk-1.1.2.zip)。包含取消竞态修复、Android定向接收缓冲、已授权缓存恢复和手机轻量分享。HTTPS立即开始，外部COS独立；`enableP8P`默认false，由接入方明确开启。

Android分享仅在明确前台、非计费Wi-Fi、业务许可、文件校验和资源状态都允许时运行。手机进程共享1个接收方、正文256KiB/s预算及最多256KiB突发；信令、协议头和重传另计。低电量、省电或温度异常暂停，退后台停止资源观察，不创建后台常驻。B/Linux不采用手机限速。宿主仍须保存收据、重新授权并调用`restoreSharing`；开启配置不会自动找到分享文件。

新接收器按手机的单片容量调度。旧端边界和本版固定输入验收见`validation/release-1.1.2.json`；源码、实验室和单台平板通过不代表正式宿主、所有公网或蜂窝已验收。App开发者替换依赖、执行flutter pub get并沿用原签名打包，已安装App不会因SDK发布自动更新。

原 [1.1.1](https://download.csnas.asia/static/ring-download-sdk-1.1.1.zip)、[1.1.0](https://download.csnas.asia/static/ring-download-sdk-1.1.0.zip) 与 [1.0.3原P2P](https://download.csnas.asia/static/ring-download-sdk-1.0.3.zip) 归档保留原文件和摘要。

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
  enableP8P: true, // 1.1.2 正式版显式开启 P8P
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

本版晚到节点补查最多追加 8 次查询，包含启动阶段最多尝试 2 个节点身份；下载完成、取消或退出时停止补查并收尾。它只在 P8P 多源已接管后运行，不延迟纯 HTTPS 下载。

Android API24+ / arm64，完整平台范围见 [ENTERPRISE.md](docs/ENTERPRISE.md)，构建见 [BUILD_ENVIRONMENT.md](docs/BUILD_ENVIRONMENT.md)，交付检查见 [RELEASE_GATE.md](docs/RELEASE_GATE.md)。SDK 不提供原生 AAR、iOS 或私有租户权限系统。

新接入验证本站/P8P、无节点 HTTPS、本站停机且后台主字段切 COS、COS 无摘要、错误摘要拒绝、取消/恢复、前后台/网络切换、旧版升级和正式签名安装。源码/回环与实验室通过不等于正式宿主和所有公网/蜂窝通过；结果按固定输入与验证范围记录，不承诺固定倍数或成功率。

执行 `tool/verify.ps1`；示例发布构建沿用 `example/package.cmd`。历史稳定归档及 `validation/summary.json` 保留原验证范围；本版证据见 `validation/release-1.1.2.json`。按发布方决定不追加长期耐久测试，不承诺所有网络成功率或固定提速比例。许可、provenance 和第三方通知随源码保留。
