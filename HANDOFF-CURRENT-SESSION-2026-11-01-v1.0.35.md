# Mesting Music 1.0.35 / code56 本地交付与接续

2026-11-01，Asia/Shanghai。唯一工程D:/AnLi，beta/b6bcd5425e0df3e03febdd460b56d0ed42004c52。1.0.25～1.0.35未提交改动保留，暂存区空；HEAD不是当前完整源码。

原签名双ARM APK：release/Mesting-Music-v1.0.35.apk，107796174字节；SHA256：6e0f5e822c451fd1a690273001003b4eb9c47fd9c772c904cb3a4bf21d160c94。

完整源码：Mesting-Music-v1.0.35-source.zip；大小及摘要见release/Mesting-Music-v1.0.35-SHA256.txt和source-verification.json（避免自引用）。

[安装验收](docs/INSTALL-v1.0.35.md)、[维护说明](docs/list-loading-and-footprint-2026-11-01-v1.0.35.md)、[主机验证](docs/validation-2026-11-01-v1.0.35.json)、[APK核验](release/Mesting-Music-v1.0.35-verification.json)、[源码核验](release/Mesting-Music-v1.0.35-source-verification.json)。

1. 公共内容视口按懒加载缓存行的封面就绪状态约束向下滚动。未就绪前停在已准备内容末尾，只由视口显示一个Apple动画；向上回看、原位失败重试、分页和原有惯性继续可用。
2. 显式Bouncing/Clamping等物理外加公共边界适配，保留原物理为parent；未注册Beta内容视口及横向/Stable保持原行为。覆盖心动模式共用功能页、双平台发现/音乐库、搜索/详情/推荐等共用长列表。原本只是暂停的内部加载图形改为不绘制，避免与视口动画叠在一起。
3. 官版核心播放日志的realtime、time、startlogtime已核对。真实时长与倍速媒体时长分别计量，真实开始时记录时间。旧的未发送逐次记录保留原日期补发；已接受/已发出/结果不明/被拒记录不自动重发，不把每日或月度汇总合成播放。
4. 网易云播放与同步页增加官方云村听歌足迹汇总读取及刷新、未发送记录同步入口。官方小时/分钟字段按官版条件二选一显示，不相加；接口接收、最近播放确认与足迹累计继续分别表达。

96文件1376项Beta、Stable19项、搜索/返回/播放器11项（含Android返回登记1项）、分析0问题及4张主机渲染通过。专项和渲染重复项不叠加完整套件数量。

云村足迹真实新增时长及十月/十一月追溯仍待用户验收。683分钟来自用户本机统计，本轮未读取其手机数据库，不能声称683分钟已补回。APK在用户手机运行后才会核查该账号保留的逐次未发送记录。只有日期/歌曲汇总而无逐次事件的旧时长继续保留本机，未证明官方接受旧日期或重算已结束月份；禁止将已accepted/unknown记录改ID重复上报。保留当前已验证的clientlog eapi传输，静态字段对齐不等于完整官版传输或真实入库验收。

仅本地准备；未访问手机/ADB、真实账号或music后台，未提交推送、打标签、上传或发布。主机验证不证明真机覆盖安装、网络/账号结果、GPU/FPS、长期稳定。用户已确认1.0.34一起听历史累计正常；此前一起听结束私信记录仍为独立未确认事项。

维护入口：lib/shared/widgets/artwork_scroll_frontier.dart、artwork_reveal_boundary.dart；lib/core/audio/actual_listening_counter.dart；lib/features/music_platform/netease/netease_playback_log.dart、netease_footprint.dart、netease_listening_reporter.dart、netease_music_repository.dart、netease_playback_settings_page.dart。测试见test/release_135_*。私有完整日志、4张主机渲染、构建/保护校验在.codex-artifacts/2026-11-01-release135/，官版证据在其protocol/子目录，不进入源码ZIP。

52份旧冻结产物/原签名、PRODUCT.md/DESIGN.md、完整玻璃与双ARM定制引擎保留。Flutter3.41.9/Dart3.11.5、JDK/SDK/NDK和依赖锁未升级；build包装入口默认1.0.35/code56。源码ZIP保存当前manifest与旧SOURCE-SNAPSHOT-v1.0.24-BASELINE.json，工作区SOURCE-SNAPSHOT.json仍为历史基线，不据此回滚。

后续保持脏工作区，不reset/clean/stash、切分支或pull覆盖；未经新授权不访问手机/ADB、真实账号/music后台，不提交推送/打标签或发布。新需求继续一次一个问题、方案确认后实施；已确认选择不重复询问。
