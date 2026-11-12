# Mesting Music 1.0.94

Android versionCode 115. This archive contains the product source corresponding to the original signed APK.

Build with Flutter 3.41.9 and JDK 17 using tool/build_android_release_apk.ps1. The pinned engine, dependencies and licenses are included. Supply your own private signing configuration.

Physical device and account acceptance remains pending. See PRODUCT-SOURCE-MANIFEST.json for the original APK digest and exact archived file hashes.

- 播放设置的音乐平台和默认音质改用 Apple 玻璃下拉框。装扮恢复原有预览，角色和轨道目录可按需展开。
- 个人页新增飘落的音符、星屑和暖色萤光。头像光环和音律声环按当前播放位置读取音频，各频段分别推动波环。
- 覆盖更新后重新打开会恢复胶囊、歌曲、队列和已保存的进度，点播放继续。应用内更新在打开系统安装器前保存进度。
- 同步歌词支持滚动选句、从该句播放及单曲时间微调。歌曲红心显示音乐平台返回的收藏总数。
- 播放封面上滑进入评论。发送评论成功后自动切到最新评论并刷新。
- 下载 SDK 升级至 1.1.9，改进下载断流时的换源与重试。
