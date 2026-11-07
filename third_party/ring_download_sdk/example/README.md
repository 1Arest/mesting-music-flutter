# 独立下载示例

只依赖 ring_download_sdk，无 LifeRing UI/账号/BLE/安装器。无业务界面，在日志输出 RING_SDK_STATUS、RING_SDK_RELEASE、RING_SDK_DIAGNOSTIC 和 RING_SDK_VERIFIED/FAILURE。

```text
flutter pub get
package.cmd --dart-define=RING_APP_ID=lifering --dart-define=RING_DOWNLOAD_LATEST=true
```

示例默认关闭分享，不自动安装下载的 APK；普通 App 按自己的交互调用同一 SDK。传入 RING_DOWNLOAD_URL 等不可变发布元数据仍可验证业务选定来源，格式见 release.example.json。下载开关与 URL 均不提供时只输出状态。必须经 package.cmd 构建，arm64-only，不使用 split-per-abi。
