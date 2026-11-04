# 1.0.37 官方足迹读取维护

网易云播放与同步页的“云村听歌足迹”改为独立入口，分别读取官方今日、当前月和历史总时长，记录每项成功读取时间。失败保留旧值、保留原读取时间并提示；字段缺失不变成0。今日按官方日期匹配日记录，歌曲/播客/有声书分项求和；当前月与历史报表校验返回月份，防止官方返回最新报告却误标为所选历史月。

历史月份默认上个月，可选择最近36个月，手动读取官方月报后核对当前账号本机网易云歌曲时长、逐次记录及已知真实时长。官方多端口径和本机/逐次归月不同，不直接相减为缺失分钟；查看范围也可能受平台会员规则影响。窄屏大字号渲染发现月报按钮文字换行裁切，已缩短为“读取月报并核对”，保留原玻璃并验证单行及页尾内容避让。

数据模型、只读仓库、读取协调器、账号Provider和页面分层。时长字段以秒解析，报告时间戳按毫秒解析；北京时间日/月与请求代次隔离，账号/凭据变化销毁旧快照。同一账号应用会话内离页再进入保留成功值，不承诺重启后的持久化。入页、手动刷新、前台恢复触发读取；仅可见前台页每分钟检查是否跨日，只有日期变化才刷新，不增加听歌写入心跳或后台轮询。

官方当前网页源日期2026-11-02；REA调查原APK为9.6.15/code9006015，SHA256 e6427bcb35ccd9e8858ee55c46ec3db56b2f09871adcd8e897244d96cfcf7894。当前网页动态代码与该APK静态代码分别归属，不宣称同版本运行验证。API模块main-290eea8e.ae83ab53.js的6882及页面main-49eac513.a1a5bbec.js的87869/82796/84513提供读取参数、日期与秒数消费证据；格式化函数r8除以3600和60，日记录合计duration/podcastDuration/audiobookDuration。REA parent Evidence：ev_7039699c9b5d758de0ca18820547a117e76a57e33c0f2aebbdb16cec42ae5edc；静态语义图partial，不当成真实后台观测。

接口：当前周/月 /api/content/activity/listen/data/realtime/report，type=week/month；历史月报 /api/content/activity/listen/data/report，type=month、endTime=中国日历月底减一小时（与官版导航一致）；历史总时长 /api/content/activity/listen/data/total，读取data.totalDuration。这些业务是读取统计，沿用App已有EAPI传输与请求级凭据代次保护；网页层GET/POST与App的EAPI HTTP封装不冒充完全相同。未向接口发送本机时长或逐次日志。

没有回退到旧widget的hourDuration/minuteDuration相加；旧widget DTO/测试保留兼容，本入口改用官方主页面字段。无新的SDK/依赖升级。

维护入口：lib/features/music_platform/netease/footprint/official_footprint.dart、official_footprint_repository.dart、official_footprint_reader.dart、official_footprint_providers.dart、official_footprint_page.dart；入口netease_playback_settings_page.dart；新回归test/release_137_footprint_test.dart和test/release_137_footprint_ui_test.dart。

100文件1404项Beta、Stable19项、搜索/返回/播放器11项（含Android返回登记1项）、分析0问题及6张主机渲染通过。专项16项与渲染复跑不重复叠加。

专项包含三类秒数、零值/缺失、无效/重复日、日期/闰年、原历史endTime、独立失败与旧时间、同日合并点击、午夜/跨月晚响应、账号/凭据生命周期、快速切月及失败保留。UI包含真实push路由、深浅色、320px/1.5字号、读取失败、历史本机对照、另一账号晚返回、注销、按钮按住拖动和前台跨日。新增版本后，旧更新说明测试的1.0.32条目下移到浮动播放器范围，已修正测试滚动定位，单独复测通过后重新运行完整回归。早期测试括号/日期上限、懒列表滚动方向及模拟生命周期失败保留私有日志；最终完整运行才计入通过。

十月683分钟尚未追回。用户已提供完整十月脱敏报告：本机683分10秒，逐次292条约649分30秒，其中280条accepted约617分31秒、12条unknown约31分59秒、0待发，均保存旧格式字段。用户反馈十一月官版今日/本周会增长；规则截图确认今日可能延迟1～2分钟、历史总时长按天更新，周日15点是周报，月报次月1日19点前后。

本轮不修改播放上报/补发协议，不重复发送accepted/dispatched/unknown、不根据按天汇总伪造播放。官版离线队列静态证据不等于服务器支持已接收旧日志纠错或已结束月份回填；真实API返回、跨端新增和十月恢复由用户验收。本地MockClient只证明传输路径、参数与状态逻辑，不证明官版账号成功。用户已确认一起听历史累计有效；结束私信记录仍为独立未确认事项。

仅本地准备；未访问手机/ADB、真实账号/music后台，未Git提交推送/打标签、上传或发布。原签名、固定双ARM定制引擎、完整玻璃、PRODUCT.md/DESIGN.md及56份旧冻结APK/源码ZIP保持。主机验证不等于真机覆盖安装、GPU/FPS或长期稳定验收。
