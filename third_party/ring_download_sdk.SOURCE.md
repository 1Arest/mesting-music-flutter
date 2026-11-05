# 2026-11-04 Music 1.0.51：升级 Ring Download SDK 1.1.2

- 用户确认将 SDK 更新与本轮页面修复一起交付；使用官方最新正式包，非开发候选。
- 来源：[SDK 下载页](https://download.csnas.asia/sdk)；[1.1.2 ZIP](https://download.csnas.asia/static/ring-download-sdk-1.1.2.zip)；[官方 SHA-256](https://download.csnas.asia/static/ring-download-sdk-1.1.2.sha256)。
- 官方 ZIP SHA-256：`387a6b8f5f3ec1bf2e0551d57427f6053a841fb90dd1b2bd670dad376d143665`。
- 242 个原始文件逐一按解压字节校验；宿主 Dart 3.11.5 分析兼容仅在 `lib/src/core/services/app_upgrade_v40_download_client.dart` 删除已由前序长度检查证明非空的重复 `!` 并补注释，不改变传输流程；其余 241 项保持原始字节。原本地 1.1.0 目录和宿主依赖锁另存私有保护副本。原 LICENSE 和第三方声明原文保留。
- 新版增加 Android 接收缓冲本地库、取消与收尾、缓存恢复及受限分享能力；Music 继续 `allowSharing: false`，不启用用户上传。
- Music 继续通过公开 `ring_download_sdk.dart` 调用，保留 appId=`music`、更新源、P2P/P8P 开关和原安装器。宿主离线解析只将 SDK 锁定版本 1.1.0 改为 1.1.2，其余依赖版本保持。
- 本轮主机与实际 APK 验证结果见 `docs/fixes-2026-11-04-v1.0.51.md` 和 `docs/validation-2026-11-04-v1.0.51.json`。供应方自带的实测/回归材料仅为来源证据，不能冒充本 App 设备验收。

以下为旧版集成的历史记录。

# Ring Download SDK 来源

**2026-10-28 分发边界更新**：用户在本次会话明确确认已取得 SDK 源码公开分发授权，并要求将 1.0.4 / 1.0.5 完整源码推送 GitHub，供另一台电脑接续。下方本机集成时期的“仅私有”操作说明属于当时状态；本次授权记录见 `docs/version-archive/RELEASE-BACKFILL-2026-10-28.md`。原 LICENSE、所有权和第三方声明保持原文，不重新宣称 SDK 采用 Music 的开源许可。

- 固定版本：1.1.0（P8P 正式 SDK）。
- 原始包：https://download.csnas.asia/static/ring-download-sdk-1.1.0.zip
- ZIP 字节：499322。
- ZIP SHA-256：0edc03178bf446d19947643d59021d46362e24a4b3c8e5a1807c9e85dd4bc7ef。
- 本次 Music 基线：95d5719829a754978ba615a873aa6ddff08f67f6。
- SDK 归档内文件逐一与解压源码核对，详细结果见交接包 evidence/sdk-source-integrity.json。
- 保留原 LICENSE 和 third_party 声明；未将其重新声明为 Music 仓库的开源许可。
- SDK 示例、内部测试和兼容代码随原包保留；Music 生产只引用其公开 ring_download_sdk.dart。
- 本目录无需在 App 启动时从任何网站下载，开发者使用本地 path 依赖编译。

## Music 1.0.4 本机兼容说明

宿主保留独立 Flutter 3.41.9 / Dart 3.11.5，按 SDK 声明的最低约束重新解析并冻结宿主依赖锁，不套用交接主机 Flutter 3.47.7 的固定测试依赖。SDK 196 个原始文件中，仅 `lib/src/core/services/app_upgrade_v40_download_client.dart` 删除了一处已由前序空值断言和流程提升证明不为 null 的重复 `!`，消除宿主分析器的 `unnecessary_non_null_assertion`；没有改变分片、恢复或传输策略。原始 ZIP 及其摘要保持冻结，验证清单分别记录原始与本地摘要，不能称修改后目录 196 项均与原包字节一致。

SDK LICENSE 保留原权利说明，本地集成不代表授权将其源码公开推送至 GitHub。

另修正 SDK 的 `test/sdk_contract_test.dart` 元数据夹具：先核对包名，再定位 SDK 自身的 `pubspec.yaml`，兼容 SDK 目录和 Music 根目录两个测试入口，不误读宿主版本。断言及生产传输代码不受此测试路径修正影响；196 项中其余 194 项与原包一致。
