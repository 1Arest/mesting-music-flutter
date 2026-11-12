# Mesting Music 1.1.0

Android versionCode 121. This archive contains the product source corresponding to the original signed APK.

Build with Flutter 3.41.9 and JDK 17 using tool/build_android_release_apk.ps1. The pinned engine, dependencies and licenses are included. Supply your own private signing configuration.

Physical device and account acceptance remains pending. See PRODUCT-SOURCE-MANIFEST.json for the original APK digest and exact archived file hashes.

- 修复融合搜索中切换酷狗音源后卡在加载的问题，并兼容音频服务器重复的 Accept-Ranges 响应头。
- 新增网易云、酷狗双平台消息提醒与通知栏展示，可按平台和类别管理私信互动、关注歌手新作品和音乐推荐。
- 无需额外部署服务端：前台定期检查、后台由系统任务安排检查；提醒可能受系统省电和后台限制影响。
- 桌面长按新增我的收藏、听歌识曲与搜索，沿用上次使用的网易云或酷狗，并处理启动与账号恢复后的跳转。
- 保留 1.0.99 的播放进度恢复、暂停定位、拖动交接及手机和平板启动页适配。
- 修复装扮弹层切换深浅色后背景与文字不更新的问题，保持弹层、滚动位置与播放状态。
