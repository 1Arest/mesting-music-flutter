# Mesting Music 1.0.99

Android versionCode 120. This archive contains the product source corresponding to the original signed APK.

Build with Flutter 3.41.9 and JDK 17 using tool/build_android_release_apk.ps1. The pinned engine, dependencies and licenses are included. Supply your own private signing configuration.

Physical device and account acceptance remains pending. See PRODUCT-SOURCE-MANIFEST.json for the original APK digest and exact archived file hashes.

- 修复重新打开后播放进度在点击播放前显示为零的问题，进入播放器即可查看上次保存的位置。
- 暂停时可点击或拖动进度条，保存选定位置，再次播放或重新打开后从该位置继续。
- 进度和时间在拖动时跟随手指，松手后跳转；改进连续拖动与音频进度回调的交接，避免旧结果回拉。
- 网易云与酷狗的播放模式、筛选标签、设置开关和诊断弹窗统一现有 Apple 风格；汽水界面保留。
- 两套人物启动页新增平板横屏与竖屏构图，经典启动页同步适配平板尺寸，并随实际窗口自动切换。
