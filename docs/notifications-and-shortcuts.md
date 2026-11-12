# 1.1.0 消息提醒、桌面快捷入口与装扮主题

## 使用行为

- 同时读取保留登录的网易云和当前选中的酷狗账号，与正在浏览的平台无关；不读取汽水消息。
- 私信、评论/赞/关注、关注歌手新作品、音乐推荐默认开启，设置 → 消息与通知可分别关闭。
- 采用本机检查方案，没有新增外部服务端或厂商推送账号。前台每 30 秒检查，后台使用 Android JobScheduler 的 15 分钟周期任务；实际运行时间由系统决定，省电策略、网络与强行停止均会影响提醒。
- 初次成功读取建立基线，不集中提醒历史记录。提醒记录只保存在应用私有目录，最多保留 100 条，退出或更换对应登录时清理。通知使用私密锁屏可见性，播放通知不受消息开关影响。
- 点击通知进入该平台的消息提醒内容。酷狗本次增加读取和提醒，没有新增发私信流程。桌面长按的三个固定入口为我的收藏、听歌识曲、搜索；平台沿用最近使用的网易云或酷狗。登录或首次引导尚未完成时保留入口请求，完成后继续跳转。
- 装扮弹层订阅应用的实时主题；切换浅色、深色或跟随系统时，外层与内容一起更新，保留弹层和滚动状态。复用已有 `MusicApplicationTheme` / `themeBuilder`，没有增加第二套主题状态。

## 接手代码

| 模块 | 职责 |
| --- | --- |
| `notification_sources.dart` | 独立账号读取、官方协议适配与消息解析；不改变可见账号，不迁移或写入凭据 |
| `notification_runner.dart` | 共用的前台/后台轮询、有限并发、最后凭据复核、失败隔离 |
| `notification_models.dart` | 消息类型、首次基线、去重与有界游标历史 |
| `notification_coordinator.dart` | 前台生命周期、权限时机、启动入口恢复和固定路由白名单 |
| `MusicNoticeStore.kt` | 单写入者、跨引擎租约、账号代次检查、持久化与系统通知 |
| `MusicNoticeJobService.kt` | 90 秒内结束的后台引擎；只注册存储、目录、偏好与网络插件，不注册音频或界面插件 |
| `MusicEntryActivity.kt` | 校验后转发给当前启用的品牌启动入口；不直接接收任意路由或网页地址 |

凭据仍在原加密仓库，通知侧只持有不可逆的登录摘要。开始账号写入/退出前，通用 `CredentialMutationSignal` 使通知租约失效；提交消息前再读取已落盘凭据。旧账号的迟到结果不能更新新账号通知。安全仓库不依赖通知或页面模块。

## 来源与验证边界

网易云复用现有私信会话、互动、关注歌手新歌和每日推荐接口。酷狗复用嵌入式协议的 `/artist/follow/newsongs` 与 `/recommend/songs`；消息读取对应官版 20.8.8 的 `MsgPullProtocol`，与 `MsgReadProtocol` 分开。旧域名的 HTTPS 证书不匹配，因此走官方网关 `https://gateway.kugou.com/msg.mobile/v3/sync/poll`，保留严格 TLS 校验。概念版和标准版沿用各自实际授权身份，不将 Lite token 改称标准版登录。

研究使用官网下载 APK 的静态方法与本项目已有协议。匿名 UID 0 检查确认两种身份参数的 HTTPS 网关返回 HTTP 200、status 1、errcode 0 和消息轮询结构；这不证明真实账号私信、通知横幅或后台唤醒已经通过。真实账号内容及系统桌面点击仍需安装验收。音乐推荐/歌手更新是根据平台可读内容生成的本地提醒，无法保证与官版运营推送逐条相同。

参考：[Android 快捷入口](https://developer.android.com/develop/ui/compose/system/shortcuts/creating-shortcuts)、[JobInfo.Builder](https://developer.android.com/reference/android/app/job/JobInfo.Builder)、[酷狗官方下载](https://download.kugou.com/android.html)。
