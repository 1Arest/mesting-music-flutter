# Mesting Music 1.0.25 / code46 安装与验收

本版交付使用正式应用名 Mesting Music、原包名 `com.mesting.music.beta`、原升级证书及双 ARM Release。安装身份与 1.0.24/code45 一致，Android 版本号递增为 46；覆盖安装的身份条件已作本机核对，实际手机覆盖安装与数据保留仍需用户验收。安装时保留原应用，不先卸载或清除数据。

- [原签名 APK](../release/Mesting-Music-v1.0.25.apk)
- [完整源码 ZIP](../Mesting-Music-v1.0.25-source.zip)
- [APK 身份、签名与资源校验](../release/Mesting-Music-v1.0.25-verification.json)
- [源码 ZIP 与全部文件校验](../release/Mesting-Music-v1.0.25-source-verification.json)
- [APK / 源码 SHA256](../release/Mesting-Music-v1.0.25-SHA256.txt)
- [本版修改](fixes-2026-10-31-v1.0.25.md)
- [完整验证状态](validation-2026-10-31-v1.0.25.json)
- [接续交接](../HANDOFF-CURRENT-SESSION-2026-10-31-v1.0.25.md)

原证书 SHA256：`8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333`。APK 包内版本、原证书、V2/V3、双 ARM、Release 不可调试、ZIP CRC 与对齐结果以校验 JSON 为准。使用既有 Flutter 3.41.9 定制 Release 引擎，保留完整玻璃材质；包内核对不代表手机 GPU 或运行后端已经验收。

## 用户手机验收

1. 网易云一起听：从播放器菜单或房间管理面板退出。取消时房间保持；确认成功后双方停止同步，本机当前歌曲继续播放，检查进度、队列和播放状态。失败提示后应可重试，不能显示已成功退出。同步延迟、网络断开与官版另一端也需要核对。
2. 好友聊天：检查实际结束会话后产生的记录、历史消息及会话预览是否显示卡片；打开后核对内容、时长与官方详情，切换账号不应保留旧账号的详情。真实记录数据本轮没有读取，无法代替这一步验收。
3. 设置 → 播放与同步：检查酷狗概念版账号音源和已保存账号状态，确认不新增开关、不改变当前音乐平台；未登录、退出和更换账号后显示应及时更新。
4. 两平台登录：检查手机、扫码及其他支持方式和方式选择页的浅深色。插画左右铺满并贴底，文字与按钮不被遮挡；弹出键盘、横屏、小屏或增大字号时表单仍可操作，收起键盘后恢复插画且输入不丢失。
5. 原有播放、下载、签到和诊断继续按 [1.0.24 安装验收](INSTALL-v1.0.24.md) 自行复测。若发生退出，保存应用诊断 JSON 和系统可用的脱敏原生退出摘要。

本次只在本机完成源码、构建和校验，没有访问手机或 ADB，没有读取真实平台账号、发送私信、操作 music 后台或发布 GitHub Release；Git 工作区改动保留，尚未提交推送。

## 另一台电脑重建

使用完整源码 ZIP 内的 `SOURCE-SNAPSHOT.json` 核对全部文件摘要。该 ZIP 中的清单属于 1.0.25；原工作区的 1.0.24 历史清单另外保存在 ZIP 内的 `SOURCE-SNAPSHOT-v1.0.24-BASELINE.json`，不作为新版清单使用。

准备 Flutter 3.41.9 / Dart 3.11.5、Java 17、Android SDK 36、NDK 28.2.13676358，以及 Android Build Tools。此机使用 Temurin 17.0.20.1+1 和 Build Tools 35.0.0；SDK 位于 `D:/CodexCache/android-build/sdk`，Flutter 位于 `D:/CodexCache/flutter-3.41.9`，新电脑应使用自己的本机路径。通过进程环境设置 JAVA_HOME、ANDROID_HOME、ANDROID_SDK_ROOT 和 GRADLE_USER_HOME，不将旧电脑的 local.properties 或凭据复制进源码。

正式入口：`tool/build_android_release_apk.ps1 -VersionName 1.0.25 -VersionCode 46 -FlutterSdkRoot <Flutter3.41.9根目录>`。它会检查更新说明版本、固定引擎摘要、依赖锁及正式素材排除。pub 阶段应保留，以更新测试后可能残留的插件注册表。共享 pubspec 中的 Stable 历史版本不等于此 APK 的公开版本。

构建后用原签名材料及 `tool/sign_android_release_apk.ps1`，通过环境变量提供口令。完整源码含双 ARM 定制引擎 JAR、manifest、重建脚本、第三方源码与许可，排除应用私钥、keystore、口令、本机配置、构建缓存和私有诊断证据。源码 ZIP 不提供原签名材料，签名应从用户保留的私有档案恢复，不能生成新密钥冒充覆盖升级。新产物使用新文件名，不覆盖旧冻结交付。
