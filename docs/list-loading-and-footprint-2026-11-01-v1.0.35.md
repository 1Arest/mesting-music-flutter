# 1.0.35 列表加载与云村足迹维护说明

2026-11-01，Asia/Shanghai。用户确认后实施；不包含手机/账号访问授权。

## 列表加载

既有ArtworkRevealBoundary会裁掉未就绪内容，但不约束滚动范围；快速手势可以越过已准备的列表，导致大面积空白。被统一加载层接管的内部加载动画此前仅停止Ticker，仍可能绘制静止动画外观。

- 新增artwork_scroll_frontier.dart：由公共视口按已布局的纵向列表缓存行及其真实封面就绪状态计算边界，未就绪内容前只留末尾加载空间。极大单次拖动也不能跳过整段已布局缓存；就绪范围增长后自然放开，向上滚和下拉刷新保持可用。
- 各列表仍使用原来的分页、错误、账号代次及缓存控制器。ArtworkPendingContent维持布局占位，但内部动画不再重复绘制/暴露语义；由视口绘制唯一Apple动画。失败行就绪为明确的原位重试状态，不阻塞其他已就绪内容。
- 显式Bouncing/Clamping等物理会跳过继承层的边界检查，因此在已有显式物理外加入公共边界适配，原有物理保留为parent。只有注册到Beta内容视口的纵向列表生效，未注册视口、横向轮播及Stable行为继续委托原物理。

排查覆盖：心动模式及NeteaseFeaturesPage共用的推荐/榜单/云盘/用户歌单/播客等列表；双平台发现与音乐库、搜索分类、歌单/专辑/歌手详情、推荐及探索列表；共用EditorialScroll/PlatformPageFrame/PlatformStyle的长内容。分页页的AutomaticSongPaging仍只预取，不承担封面已就绪判断。无待加载内容的法律/设置等页面虽共用惯性适配，但没有注册边界时不限制滚动。待播/系统Back/玻璃底距沿用原实现。

主机专项实际快速拖动/甩动分别覆盖Clamping/Bouncing、已加载末项可点击、等待时单一动画、就绪后继续、反向上滑及失败重试；既有图片解码/刷新专项继续运行。完整页面、真机高速手势、系统导航/辅助功能与网络业务仍需用户验收。程序化jumpTo不视为用户手势，继续供页面恢复位置和测试定位使用。

## 官版时长依据

原始网易云Android9.6.15/code9006015 APK SHA256：`e6427bcb35ccd9e8858ee55c46ec3db56b2f09871adcd8e897244d96cfcf7894`。应用宝原始分发：[下载页面](https://sj.qq.com/appdetail/com.netease.cloudmusic)。仅静态分析，未运行或安装。

官版核心qn0.z0.x3读取真实已播放毫秒getPlayedTime形成realtime秒、读取getPlayedTimeWithSpeed形成time秒，并携带本次原始startlogtime。完整原包SDK smali和派生原始classes18模块REA交叉核对；REA Evidence：`ev_bb528ee62bfc2a6d6451d3595355c9e95b308883faab6baeea702d16aa40d11f`、`ev_7ceeeec19602dff3033d4eaf19c8ca7fd0f61eba6b1f7ce9fb74b95aed2769b9`。REA为原成员字节组成的局部静态载体，不能表示完整APK或执行结果。原证据、派生文件及成员摘要仅在私有.codex-artifacts/2026-11-01-release135/protocol/，不进入源码ZIP。

原Mesting上报只有time，本版补充realtime和真实开始时间，ActualListeningCounter独立累计倍速媒体时长，暂停/缓冲/拖动均不计入；后台与本机播放仍以实际音频状态计量。新的逐次日志在真实开始时保存时间，重取/补发时沿用保存值；旧版确定未发送的记录用原事件时间戳或原createdAt，不改成补发日期。日志请求保留既有已验证clientlog eapi传输与请求局部身份，不擅自宣称完整复现官版原生日志传输。

官版s11.i.p()读取music/multi/terminal/widget/listen/data，无额外参数；响应data可为JSON字符串。FootPrintCalendarData含monthDate/hourDuration/minuteDuration等，REA DTO Evidence：`ev_c8837157a0ec464222b73164278f9ea37fa3bda68c7ec94eb4b33b8facefa031`。官版a21.f.i()有小时则显示小时，否则显示分钟；两个字段不能相加。本版只显示官方返回的月份及同样条件选取的数值，不据此证明某一条日志入库或追溯原月份成功。

## 历史恢复边界

本版恢复/手动同步只发送原账号真实逐次日志中queued或已中断的open未发送记录。已accepted、dispatched、unknown及rejected均不自动重发，不复制成新ID。当前仍在播放的open事件等待正常结束，不制造重复累计心跳或反复playend。

本机PlaybackDailyHistories按天/曲聚合，不能还原精确逐次开始、各次倍速、哪些已被平台处理。十月683分钟若只剩汇总，不能直接合成播放日志；本机统计完整保留。未找到证明官方接受旧日期、重算已结束月份或事件去重的服务端规则，不能保证十月/十一月全部追回。新播放与真实积压是否进入云村足迹，需用户安装后对照官方，200接收与最近播放出现均不等于足迹时长验收。

用户本轮已确认1.0.34一起听历史累计有效；这是累计功能的用户反馈，不是此前一起听结束私信记录/聊天卡片问题的解决证明。
