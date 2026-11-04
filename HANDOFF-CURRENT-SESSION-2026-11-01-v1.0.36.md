# Mesting Music 1.0.36 / code57 本地交付与接续

2026-11-01开始准备，2026-11-02完成本地核验，Asia/Shanghai。唯一工程D:/AnLi，beta/b6bcd5425e0df3e03febdd460b56d0ed42004c52。1.0.25～1.0.36未提交改动保留，暂存区空；HEAD不是当前完整源码。

原签名双ARM APK：release/Mesting-Music-v1.0.36.apk，107910862字节；SHA256：370744ba5cfdf8ad718aa94d2830eec420c1d24772a4fcf0da32575f55ecf7cd。

完整源码：Mesting-Music-v1.0.36-source.zip；大小与摘要见release/Mesting-Music-v1.0.36-SHA256.txt和source-verification.json，避免自引用。

[安装诊断步骤](docs/INSTALL-v1.0.36.md)、[维护说明](docs/fixes-2026-11-01-v1.0.36.md)、[主机验证](docs/validation-2026-11-01-v1.0.36.json)、[APK核验](release/Mesting-Music-v1.0.36-verification.json)、[源码核验](release/Mesting-Music-v1.0.36-source-verification.json)。

新增“网易云播放与同步→按月听歌上报诊断”。默认上个月，可切换有本机记录的月份并刷新，读取当前网易云账号的一致本机快照。分别展示全部来源/网易云歌曲的按日真实时长、逐次时长记录及各发送状态、开始播放与最近播放匹配数量、旧版缺少realtime/startlogtime等字段。

模型、数据库读取、页面/复制分别解耦。数据库只读事务不改变日志状态、不发网络请求；本版不改播放上报/补发协议。JSON仅白名单日期、匿名报告内编号、时长、状态和字段完整度，不含账号/歌曲/事件真实ID、名称、URL、凭据或精确播放时刻。导出前预览，确认复制后由用户手动分享；账号变化后不能复制旧报告。逐次明细上限5000条并显式标识截断，汇总仍完整。

按本机收听日与逐次开始日期归月可能存在跨午夜差异，二者不能直接相减当作云端缺失分钟。旧记录缺字段只能说明本机保存的内容，不能倒推补发时的真实线上载荷；accepted及recent匹配不等于足迹入库，只有time而无真实计时证据的记录不会被当作确切真实分钟。

98文件1388项Beta、Stable19项、搜索/返回/播放器11项（含Android返回登记1项）、分析0问题及4张主机渲染通过。专项12项及渲染重跑不叠加完整套件数量。

本版目标是拿到真实按月诊断，尚未读到用户手机上的十月明细，也没有追回683分钟。用户已确认1.0.35点击补发后仍未恢复，待发约0分钟；截图为已接收540条、最近播放确认236条、结果未确认18条，官方汇总显示2026/11约1小时。上述为全期条数与当前月显示，不证明十月入库。旧月份追溯、真实新增足迹仍待验收，不重发accepted/dispatched/unknown或伪造日/月汇总。用户已确认1.0.34一起听历史累计正常；结束私信记录仍为独立未确认事项。

仅本地准备；未访问手机/ADB、真实账号/music后台，未Git提交推送/打标签、上传或发布。原签名、完整玻璃与固定双ARM引擎保持；主机验证不等于真实账号、手机覆盖安装、GPU/FPS与长期稳定验收。

接下来的真正阻点是等待用户手动提供十月脱敏按月JSON，之后才能判断缺少逐次记录、旧载荷字段或平台不接受历史追溯。不要拿当前540/236/18的全期条数推算十月分钟数，不重复询问已经确认的0分钟和补发已点击事实。没有数据时不承诺追回，也不继续打无依据的“补回版”。

维护入口：lib/features/music_platform/netease/diagnostics/netease_listening_audit.dart、netease_listening_audit_provider.dart、netease_listening_audit_page.dart；设置入口netease_playback_settings_page.dart。新回归test/release_136_listening_audit_test.dart和test/release_136_listening_audit_ui_test.dart。

私有完整日志、4张渲染、构建和保护校验在.codex-artifacts/2026-11-01-release136/，不进入源码ZIP。54份旧冻结物及签名密钥、PRODUCT.md/DESIGN.md、完整玻璃和定制引擎保持。Flutter3.41.9/Dart3.11.5/JDK/SDK/NDK和依赖锁不升级；两个build包装入口默认1.0.36/code57。源码ZIP自带当前manifest和旧SOURCE-SNAPSHOT-v1.0.24-BASELINE.json，工作区SOURCE-SNAPSHOT.json仍为历史基线，不据此回滚。

不reset/clean/stash、切分支或pull覆盖。无新明确授权不访问手机/ADB、真实账号/music后台，不提交推送/打标签或发布。新需求继续一次一个问题、方案确认后实施，已确认选择不重复询问。
