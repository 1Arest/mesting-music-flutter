# Mesting Music 1.0.33 / code54 本地交付与接续

2026-11-01，Asia/Shanghai。唯一工程D:/AnLi，beta/b6bcd5425e0df3e03febdd460b56d0ed42004c52。1.0.25～1.0.33全部未提交改动保留，暂存区空；HEAD不是当前完整源码。

原签名双ARM APK：release/Mesting-Music-v1.0.33.apk，107697870字节；SHA256：1983f4a0e5253a6cf0e1d4d11fcd15774012670f45400de5b5692c77a9031ba6。

完整源码：Mesting-Music-v1.0.33-source.zip。大小/摘要见release/Mesting-Music-v1.0.33-SHA256.txt和source-verification.json，避免自引用。

[安装验收](docs/INSTALL-v1.0.33.md)、[修改维护](docs/fixes-2026-11-01-v1.0.33.md)、[遮挡排查](docs/layout-clearance-audit-2026-11-01-v1.0.33.md)、[主机验证](docs/validation-2026-11-01-v1.0.33.json)、[APK核验](release/Mesting-Music-v1.0.33-verification.json)、[源码核验](release/Mesting-Music-v1.0.33-source-verification.json)。

## 完成

主壳/独立页统一提供动态底距，修复历史1.0.1、公共表单及其他长页面末项遮挡。地区中文/短码/六位码共用匹配，保留既有选择，未选从北京市开始，不插入数字选项。一起听按任意当前好友读取既有官方累计字段，移除本次兜底；快照替换、隔离、明确未获取/上次同步及显式重试得到处理。

93文件1355项Beta、Stable19、Stable底距专项1、搜索/返回/播放器11项（含Android返回登记1项）、静态分析0问题和10张主机合成渲染通过。专项/渲染重复运行不叠加完整套件数量。

实际APK版本/code、原签名双ARM、固定Release引擎、全部玻璃着色器/SDK库和内置说明以核验文件为准。48份旧冻结物保持。源码ZIP保存当前清单及1.0.24历史BASELINE，工作区SOURCE-SNAPSHOT.json仍为旧基线，不能据此回滚。默认tool/build_android_release_apk.ps1为1.0.33/code54；Flutter3.41.9/Dart3.11.5及既有JDK/SDK/NDK不升级。

## 待验收与约束

仅本地准备；未访问手机/ADB、真实账号或music后台，未Git提交推送/打标签、上传或发布。主机证据不证明真机覆盖安装、系统Back/TalkBack、GPU/FPS、长期稳定及真实业务通过。

一起听累计显示使用既有totalConnectionTime字段，移除了currentConnectionTime兜底。真实响应是否返回每位好友的完整历史、是否与官版数值一致仍待用户验收；没有硬编码截图数值或猜测其他历史字段。历史一起听真实结束记录/聊天卡片仍未确认解决，属于独立待诊断事项。

若安装后累计仍未获取或数值不符，需用户提供脱敏响应结构再确认具体修复。本轮没有真实统计响应，也没有可复用官方客户端静态证据，不发明其他历史字段或累计公式。

保留全部脏工作区与冻结交付，不reset/clean/stash、切分支或pull覆盖。无新授权不访问手机/ADB、真实账号/music后台，不提交推送、打标签或发布。新需求继续一次只问一个问题，方案确认后实施，已确认选择不重复询问。

维护入口：lib/shared/widgets/beta_content_insets.dart、beta_secondary_music_layout.dart；lib/features/experience/presentation/beta_music_shell.dart；lib/features/music_platform/domain/platform_regions.dart及presentation/platform_region_picker.dart；lib/features/music_platform/netease/together/together_presence.dart、netease_together_controller.dart、netease_together_player_header.dart。三份test/release_133_*和test/support/release_133_qa.dart为新增主机回归。私有原始日志、10张渲染、复核及交付保护在.codex-artifacts/2026-11-01-release133/，不进入源码ZIP。
