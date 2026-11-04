# Mesting Music 1.0.37 / code58 本地交付与接续

2026-11-02，Asia/Shanghai；D:/AnLi，beta/b6bcd5425e0df3e03febdd460b56d0ed42004c52。1.0.25～1.0.37全部未提交改动保留，暂存区空，HEAD不是当前完整源码。

原签名双ARM APK：release/Mesting-Music-v1.0.37.apk，107927246字节，SHA256：b79f75758312b90cf763acaf8298b7b45b00abf144a416df6b299488162180ac。

完整源码：Mesting-Music-v1.0.37-source.zip；大小、摘要和文件数见release/Mesting-Music-v1.0.37-SHA256.txt及source-verification.json，避免源码包自引用。

[安装验收](docs/INSTALL-v1.0.37.md)、[实现与证据](docs/official-footprint-2026-11-02-v1.0.37.md)、[验证](docs/validation-2026-11-02-v1.0.37.json)、[APK核验](release/Mesting-Music-v1.0.37-verification.json)、[源码核验](release/Mesting-Music-v1.0.37-source-verification.json)。

网易云播放与同步页的“云村听歌足迹”改为独立入口，分别读取官方今日、当前月和历史总时长，记录每项成功读取时间。失败保留旧值、保留原读取时间并提示；字段缺失不变成0。今日按官方日期匹配日记录，歌曲/播客/有声书分项求和；当前月与历史报表校验返回月份，防止官方返回最新报告却误标为所选历史月。

历史月份默认上个月，可选择最近36个月，手动读取官方月报后核对当前账号本机网易云歌曲时长、逐次记录及已知真实时长。官方多端口径和本机/逐次归月不同，不直接相减为缺失分钟；查看范围也可能受平台会员规则影响。窄屏大字号渲染发现月报按钮文字换行裁切，已缩短为“读取月报并核对”，保留原玻璃并验证单行及页尾内容避让。

数据模型、只读仓库、读取协调器、账号Provider和页面分层。时长字段以秒解析，报告时间戳按毫秒解析；北京时间日/月与请求代次隔离，账号/凭据变化销毁旧快照。同一账号应用会话内离页再进入保留成功值，不承诺重启后的持久化。入页、手动刷新、前台恢复触发读取；仅可见前台页每分钟检查是否跨日，只有日期变化才刷新，不增加听歌写入心跳或后台轮询。

100文件1404项Beta、Stable19项、搜索/返回/播放器11项（含Android返回登记1项）、分析0问题及6张主机渲染通过。专项16项与渲染复跑不重复叠加。

十月683分钟尚未追回。用户已提供完整十月脱敏报告：本机683分10秒，逐次292条约649分30秒，其中280条accepted约617分31秒、12条unknown约31分59秒、0待发，均保存旧格式字段。用户反馈十一月官版今日/本周会增长；规则截图确认今日可能延迟1～2分钟、历史总时长按天更新，周日15点是周报，月报次月1日19点前后。

本轮不修改播放上报/补发协议，不重复发送accepted/dispatched/unknown、不根据按天汇总伪造播放。官版离线队列静态证据不等于服务器支持已接收旧日志纠错或已结束月份回填；真实API返回、跨端新增和十月恢复由用户验收。本地MockClient只证明传输路径、参数与状态逻辑，不证明官版账号成功。用户已确认一起听历史累计有效；结束私信记录仍为独立未确认事项。

仅本地准备；未访问手机/ADB、真实账号/music后台，未Git提交推送/打标签、上传或发布。原签名、固定双ARM定制引擎、完整玻璃、PRODUCT.md/DESIGN.md及56份旧冻结APK/源码ZIP保持。主机验证不等于真机覆盖安装、GPU/FPS或长期稳定验收。

维护入口：lib/features/music_platform/netease/footprint/official_footprint.dart、official_footprint_repository.dart、official_footprint_reader.dart、official_footprint_providers.dart、official_footprint_page.dart；入口netease_playback_settings_page.dart；新回归test/release_137_footprint_test.dart和test/release_137_footprint_ui_test.dart。

原官版逆向与完整REA ledger在.codex-artifacts/2026-11-02-offline-investigation/（不进入源码ZIP），用户十月报告分析在2026-11-02-october-report/。本版日志/6张渲染/构建/签名与保护校验在2026-11-02-release137/。完整源码ZIP保留定制引擎和许可，排除密钥/本机配置/私有诊断；旧SOURCE-SNAPSHOT.json工作区元数据不覆盖，打包为明确的v1.0.24-BASELINE另附当前manifest。

不reset/clean/stash、切分支或pull覆盖；不重问十月诊断报告已提供、待发0、已点击补发和新播放增长等已确认事实。后续重点是用户验收真实今日/当前月/总与十月报表读取；服务器纠错/回填尚未知，不据静态队列直接重发已接收或未知旧记录。没有新授权不访问手机/ADB、真实账号/music后台，不提交推送/打标签或发布。新需求仍一次一个问题，方案确认后实施。
