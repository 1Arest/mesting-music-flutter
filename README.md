# Mesting Music

**当前维护代码：1.0.24 / Android code45，开发分支 beta，待手机验收。** 新电脑先读[跨电脑总交接](HANDOFF-GITHUB-2026-10-31-v1.0.24.md)、[接续入口](docs/CONTINUE-BETA.md)与AGENTS.md。

[1.0.23 R2 正式归档](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.23)和[1.0.24 预发布](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.24)均附原签名APK、完整源码ZIP及校验资料，全部31个附件摘要已回读核验。1.0.23源码为本次恢复且通过回归/构建的资料，业务二进制完全重现未证明；1.0.24直接采用原冻结交付。详情见[归档来源](docs/version-archive/RELEASE-ARCHIVE-2026-10-31-v123-v124.md)。

1.0.24 包含双平台签到、酷狗账号补源、下载页改版、公共分页/底栏与音效整理、手机内自动诊断。70文件1197项Beta、Stable19、Android返回1项及分析0问题已验证，实际手机和账号行为按验收清单复测。[本版修改](docs/fixes-2026-10-31-v1.0.24.md) · [安装验收](docs/INSTALL-v1.0.24.md) · [诊断场景](docs/DIAGNOSTIC-SCENARIOS-v1.0.24.md)。

源码保留完整SDK、定制引擎和第三方许可；原签名材料私下转移。本次仅Git/GitHub归档，未操作music后台或手机。以下Beta.19和stable介绍保留历史产品背景。

## Beta.19 本次更新

- 保留完整玻璃模糊、折射、形变和胶囊开合，优化几何缓存、离屏合成和角色动画开销。
- 修复震动/手机登录蓝色按钮、签到页三个白色按钮的滑动变色，保留回弹和点击反馈。
- Beta 移除 Mesting 登录入口及正式专用入包素材，APK 减少约18%；正式版功能保留。
- 两张给定静态启动图，首次升级默认图一一次；静态启动无固定停留，依赖并行准备。
- 小新进度角色七种天气可手动选择并保存。受控真机 Raster P95 下降约20%，仍有超预算帧。

[完整更新与验证边界](docs/fixes-2026-10-27-beta19.md) · [Beta.19 下载](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.37-beta.19) · [另一台电脑接续](docs/CONTINUE-BETA.md)。

一款面向 Android 的 Flutter 音乐应用，提供本地与在线音乐浏览、播放控制、歌词、主题换肤，以及好友音乐互动体验。

当前稳定源码版本：**1.0.37+46**<br>
Java + MySQL 独立测试通道：**1.0.38+40**（不替代正式稳定版）

稳定包使用 `com.mesting.music` 和 `releases/android/latest.json`；Java + MySQL 测试包与 UI Beta 分别使用独立包名和更新清单，三条通道不会互相覆盖。完整版本、标签和发布记录见 [docs/release-history.md](docs/release-history.md)。旧 `flutter-music-v1.0.37` 标签保留原发布历史，不伪装成稳定 APK 的逐文件源码快照。

## 下载与安装

发布后可在本仓库的 **Releases** 页面下载 Android APK。所有现存稳定、Java/MySQL 测试和 UI Beta 历史版本均已在 [APK 下载中心](docs/apk-downloads.md) 分开列出。下载完成后，在 Android 设备上允许“安装未知来源应用”，再打开 APK 安装即可。

> 安装包仅面向 Android。首次安装或更新前，请确认安装包来自本仓库的 Releases 页面。

## 主要功能

- 音乐首页、推荐内容、歌单与听歌排行
- 本地音乐与在线音乐搜索、播放和播放队列
- 中文、拼音、首拼与近似输入的音乐搜索联想
- 收藏歌曲、创建和管理个人歌单
- 歌词同步、后台播放、通知栏与锁屏媒体控制
- 完整播放页：唱片、进度条、音效化主题与胶囊播放器
- 多套主题及自定义图片、静音视频背景
- Android 系统悬浮歌词
- 好友关系、私信、未读提醒与一起听歌同步
- 账号注册、邮箱/手机号验证码登录、账号注销与隐私协议确认

## 技术栈

| 领域 | 技术 |
| --- | --- |
| 客户端 | Dart、Flutter、Material / Cupertino |
| Android | Gradle、Kotlin/Java Android 运行环境 |
| 状态与路由 | Riverpod、GoRouter |
| 音频与媒体 | just_audio、audio_service、audio_session |
| 本地数据 | Drift (SQLite)、SharedPreferences、Flutter Secure Storage |
| 网络与搜索 | HTTP、Audius 接口、拼音检索 |
| 云端能力 | Tencent CloudBase、Node.js / JavaScript 云函数 |

## 从源码构建

### 环境要求

- Flutter SDK（项目当前使用 Dart `^3.10.7`）
- Android Studio 与 Android SDK
- JDK（建议使用 Android Studio 自带 JBR）

### 运行

```powershell
flutter pub get
flutter run
```

### 构建 Android Release APK

```powershell
flutter build apk --release --target-platform android-arm,android-arm64
```

输出文件：

```text
build/app/outputs/flutter-apk/app-release.apk
```

## 项目结构

```text
lib/
  features/       # 音乐、搜索、播放器、社交、账号等功能模块
  core/           # 主题、网络、基础设施与通用能力
assets/           # 品牌、主题、歌单与播放器视觉资源
android/          # Android 原生工程配置
tool/             # 发布与维护脚本
```

## 隐私与网络说明

- 在线音乐、搜索与社交功能需要网络连接。
- 登录、好友和一起听功能依赖云端服务。
- 应用仅会在功能需要时请求相应权限；系统悬浮歌词首次开启时，Android 会请求“显示在其他应用上层”权限。

## 开源说明

请在使用、分发或二次开发前确认音乐内容、封面、歌词和第三方接口的授权范围。项目中的 `reference-vue/` 仅作为只读参考，不是应用运行依赖。
