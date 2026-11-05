# 1.0.50～1.0.60 完整归档

最新版本：**1.0.60 / code81**。包名 `com.mesting.music`。原始APK与完整源码，设备/账号验收边界保持原说明。

- [1.0.60 / code81](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.60) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.60)
- [1.0.59 / code80](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.59) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.59)
- [1.0.58 / code79](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.58) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.58)
- [1.0.57 / code78](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.57) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.57)
- [1.0.56 / code77](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.56) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.56)
- [1.0.55 / code76](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.55) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.55)
- [1.0.54 / code75](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.54) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.54)
- [1.0.53 / code74](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.53) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.53)
- [1.0.52 / code73](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.52) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.52)
- [1.0.51 / code72](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.51) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.51)
- [1.0.50 / code71](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.50) · [冻结源码](https://github.com/Mesting42/mesting-music-flutter/tree/v1.0.50)

Gitee已同步原始源码标签；本轮Release附件因API授权不足，待补，不将Git标签冒充完整附件归档。


---

# Mesting Music

**最新维护交付：1.0.49 / Android code70（Beta 安装通道）。** [Latest Release](https://github.com/Mesting42/mesting-music-flutter/releases/tag/v1.0.49) · [分通道下载目录](docs/apk-downloads.md) · [版本目录](docs/versions.md)。

| 安装通道 | 包名 | 导航 |
| --- | --- | --- |
| 正式稳定版 | `com.mesting.music` | [历史包按版本倒序](docs/apk-downloads.md#正式稳定版) |
| Beta | `com.mesting.music.beta` | [正式交付按版本倒序](docs/apk-downloads.md#beta-通道正式交付)、[早期实验系列](docs/apk-downloads.md#早期-beta-实验系列) |
| Java/MySQL 测试 | `com.mesting.music.javatest` 等 | [独立测试包](docs/apk-downloads.md#javamysql-独立测试包) |

本次补齐 1.0.25～1.0.37、1.0.39～1.0.49 共24版的独立源码提交、标签和正式 GitHub Release，263个附件均保持原始字节。1.0.38 的私有候选不公开。安装通道按真实包名分组，与 Release 的正式/预发布状态分别记录；1.0.49 设为 GitHub Latest，应用内更新后台未改动。

当前页面位于 `main` 分支。`beta` 维护当前产品；`main` 保留原产品源码，仅同步本下载导航。新电脑继续开发应从 [beta 分支接续](https://github.com/Mesting42/mesting-music-flutter/blob/beta/docs/CONTINUE-BETA.md)。设备、账号和历史时长的未完成验收如实保留，GitHub 归档不替代它们。

---

下面保留此前产品介绍的历史原文；其中旧版本状态和下载提示请以本页上方目录为准。

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
