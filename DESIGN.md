**2026-11-04 1.0.52：1.0.52沿用完整玻璃与反向路由，末播胶囊最大210dp、同一滚动活动连续校准；目录/署名独立错误与重试保留成功内容。酷狗原生统计/等级/徽章页面覆盖明暗/320窄屏及2x文字，写入未知先重读，不添加交易入口。**

---
name: Mesting Music Android Beta.20
description: 封面主导、语义配色与共享播放控件的中文私人听歌空间
colors:
  beta-accent: "#0066D9"
  beta-accent-dark: "#0091FF"
  beta-navigation: "#D60035"
  beta-navigation-dark: "#FF375F"
  beta-navigation-label: "#BC0032"
  beta-navigation-label-dark: "#FF829B"
  beta-together: "#7639C7"
  beta-together-dark: "#BF8CFF"
  beta-insights: "#A85B00"
  beta-insights-dark: "#FFAA3D"
  beta-panel-light: "#F2F2F7"
  beta-panel-dark: "#1C1C1E"
  entry-coral: "#DE5757"
  action-blue: "rgba(0,99,216,0.94902)"
  editing-blue: "#007AFF"
  editing-blue-dark: "#0A84FF"
  primary-seed: "#465CC7"
  primary-seed-dark: "#91A5FF"
  favorite: "#CC3F56"
  beta-favorite: "#FF2D55"
  beta-favorite-dark: "#FF375F"
  beta-success: "#007A2B"
  beta-success-dark: "#30D158"
  beta-success-surface: "#E9F6ED"
  beta-success-surface-dark: "#153523"
  canvas-light: "#FFFFFF"
  canvas-dark: "#000000"
  surface-light: "#FCFCFD"
  surface-dark: "#11141B"
  text-primary-light: "#20232B"
  text-primary-dark: "#F5F7FC"
  text-secondary-light: "#5D6572"
  text-secondary-dark: "rgba(200,208,222,0.741176)"
  text-muted-light: "#7E8795"
  text-muted-dark: "rgba(152,162,179,0.568627)"
  player-base: "#17191F"
  player-ink: "#FFFFFF"
  lyric-inactive: "rgba(255,255,255,0.65098)"
typography:
  display:
    fontFamily: "sans-serif, Noto Sans SC, Microsoft YaHei"
    fontSize: "34px"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "-0.9px"
  headline:
    fontSize: "23px"
    fontWeight: 800
    letterSpacing: "-0.4px"
  detail-title:
    fontSize: "21px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "-0.5px"
  title:
    fontSize: "16px"
    fontWeight: 600
  body:
    fontSize: "13px"
    fontWeight: 400
  action:
    fontSize: "14px"
    fontWeight: 800
  glass-action:
    fontSize: "15px"
    fontWeight: 700
  label:
    fontSize: "10px"
    fontWeight: 600
  lyrics:
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.4
    letterSpacing: "-0.5px"
rounded:
  artwork-small: "9px"
  cover: "12px"
  content: "18px"
  panel: "22px"
  dialog: "28px"
  player-quality: "30px"
  composer: "24px"
  floating: "32px"
  sheet: "36px"
  capsule: "999px"
spacing:
  tight: "4px"
  small: "8px"
  compact: "12px"
  shelf-gap: "14px"
  header-gap: "16px"
  control: "18px"
  page: "22px"
  section: "24px"
  section-top: "28px"
components:
  button-primary:
    typography: "{typography.action}"
    rounded: "{rounded.capsule}"
    height: "48px"
  button-secondary:
    rounded: "{rounded.capsule}"
    height: "48px"
  button-text:
    rounded: "{rounded.capsule}"
    height: "44px"
  input:
    rounded: "{rounded.content}"
    padding: "17px 18px"
  chip:
    rounded: "{rounded.capsule}"
  panel:
    rounded: "{rounded.panel}"
    padding: "20px"
  cover:
    rounded: "{rounded.cover}"
  navigation:
    rounded: "{rounded.capsule}"
    height: "64px"
  playback-pill:
    rounded: "{rounded.floating}"
    height: "64px"
  player-transport:
    backgroundColor: "transparent"
    textColor: "{colors.player-ink}"
    height: "48px"
  favorite-button:
    backgroundColor: "transparent"
    height: "48px"
    width: "48px"
  media-volume:
    height: "48px"
  comment-input:
    rounded: "{rounded.composer}"
  comment-send:
    backgroundColor: "{colors.action-blue}"
    textColor: "{colors.player-ink}"
    rounded: "{rounded.composer}"
    height: "48px"
    width: "48px"
  glass-action-confirm:
    backgroundColor: "{colors.action-blue}"
    textColor: "{colors.player-ink}"
    rounded: "{rounded.composer}"
    height: "48px"
    width: "48px"
  glass-action-close:
    rounded: "{rounded.composer}"
    height: "48px"
    width: "48px"
  glass-button:
    typography: "{typography.glass-action}"
    rounded: "{rounded.capsule}"
    height: "52px"
    padding: "0 18px"
  glass-field:
    rounded: "{rounded.composer}"
    padding: "17px 20px"
  glass-back:
    rounded: "{rounded.capsule}"
    height: "48px"
    width: "48px"
  glass-button-blue:
    backgroundColor: "{colors.action-blue}"
    textColor: "{colors.player-ink}"
    typography: "{typography.glass-action}"
    rounded: "{rounded.capsule}"
    height: "52px"
    padding: "0 18px"
  glass-menu:
    rounded: "{rounded.composer}"
  login-success:
    backgroundColor: "rgba(13,16,18,0.94902)"
    textColor: "{colors.player-ink}"
    rounded: "{rounded.panel}"
    width: "104px"
    height: "104px"
    padding: "12px"
---

# Design System: Mesting Music Android Beta.19

## Overview

**Creative North Star: "封面主导的私人听歌空间"**

封面承担视觉重心，中文大标题与留白组织阅读顺序。横向内容组露出下一项，歌曲列表保持紧凑；播放与导航悬浮于内容之上。Beta 使用功能蓝、收藏粉、完成绿的语义配色，经典浅色、深色和跟随系统共用布局，进度条样式与角色独立选择。

本文合并用户于 2026-10-27 确认的 Beta.20 修正，沿用 Mesting/Apple Music 视觉依据与同一 North Star。可见名称为 Mesting Music。经典浅深色使用中性黑白灰面板，功能操作与选中用蓝色、收藏用粉色、签到完成用绿色；封面播放器的氛围配色保留；入口与指南继续使用珊瑚红原创音乐双角色和局部暖色背景。居中同意组、Raycast 参考适配的按方式登录、统一账号模块、真实五类搜索、独立启动选择和真实队列时长继续使用。Beta.13 已确立的欢迎返回、指南跳过、播放器进退、进度角色锚点、文本编辑和播放胶囊菜单继续按各自契约运行；登录成功的尺寸与指南可用性由本轮确认覆盖。Beta.20 经用户确认统一功能强调色，原珊瑚入口插画与显式 IP 配色继续独立。Beta 门限为 DistributionChannel.isBeta（Android appFlavor == beta）；正式 flavor 的页面、导航、迷你播放器、完整主题、定制推荐与默认黑胶契约保留，共享工具按调用点生效。

Beta.18 的范围以 docs/fixes-2026-10-26-beta18.md 为准：轻量首页问候、原创输出 glyph 与对话框音量、更多/关闭的局部按压、成功音质目录的进程内有界保留、评论等待与内容到达、滚动取消后的蓝色玻璃可读性，以及可立即操作指南上方的小型登录成功 HUD。最新确认的登录 HUD 为圆角方形（104×104dp），位于 SafeArea 内顶部留白（76dp）、指南页头下方的上部中央；不再采用历史大卡片与阻断指南的遮挡。前景到达动效不包裹整块玻璃，premium/full 材质继续拥有独立层。具体音乐表面和入口构图分别见已有 surface brief；没有建立新视觉世界。

以下 Beta.13 证据仅属于该版冻结构建：work/beta13/review-final.md 给出有界 disposition: ship，R1–R4 resolved、remaining clear；review-fixes-functional-final.log 为 23 项通过（9 session、14 entry），此前 12 项软件 UI 证据及未变的九张进度角色、两张成功反馈复核捕获用于该版。最终常规回归为 657 通过/78 条件跳过/0 失败，Beta196 通过/0 失败，软件 UI53 通过，analyze 为 No issues found；各组重叠不相加。assembleBetaRelease 成功，1.0.37-beta.13 / 13、同一 Beta 证书、16KiB ZIP/五个 ARM64 LOAD 对齐、原生链/FFI、视频/shader 与优化后的原创提示音字节一致性已检查；精确包身份见 PRODUCT.md 和该版 artifact-verification.json，源码 ZIP 留文档冻结后的外部清单。这些结果不替代 Beta.18 的验证。源码、软件测试与捕获不证明实际 Android GPU/FPS、IME/自动填充、TalkBack、预测返回、提示音响度/焦点、短信或云写入；设备冷启动丢失登录态的原触发原因也未由日志证明。没有新增 ImageGen 批准 comp、approval sidecar、QUALITY BAR card 或 FORM seed。

以下 Beta.12 证据为历史冻结快照：ui-final.log 47 项通过及 captures-final/existing 的生产控件捕获，包含纯色/内容、浅/深、收拢/展开/形变、手机/宽屏和小屏大字配对；蓝色滚动前/变化中/稳定后浅色三帧均为 [13,107,218]，深色为 [1,95,206] / [13,107,218] / [1,95,206]。test-summary.json 记录最终常规 651 通过/63 条件跳过/0 失败、Beta175 通过/0 跳过/0 失败；analyze-approved.log 为 No issues found，组间有重叠不可相加。媒体核验确认用户原文件未改，兼容副本保留原 AAC 流；assembleBetaRelease 成功，1.0.37-beta.12 / 12 的身份、同一 Beta 证书、16KiB ZIP/ARM64 LOAD 对齐、打包原生库对应链、修正 shader 与两段兼容视频均已核验。精确包字节/哈希见 PRODUCT.md 与该版外部 release-verification/artifact-verification.json；源码 ZIP 身份留该版文档冻结后的外部清单。软件捕获使用合成 fixture、软件渲染与 Windows QA 中文字体，不能认证 Android GPU 光学、FPS、系统边缘/预测返回、原声解码/媒体焦点/硬件音量或 TalkBack；也不构成 Beta.13 发布身份或测试结果。历史待确认文件名不改变用户随后对 Beta.12 文字方案的明确确认。

历史 Beta.11 发布 APK 已验证为 Mesting Music / com.mesting.music.beta / 1.0.37-beta.11 / 11，assembleBetaRelease 成功；该版最终常规 644 通过/58 条件跳过/0 失败、Beta163 通过/0 跳过/0 失败、approved 软件 UI43 通过，后补设置捕获1通过，analyze-approved 无问题，组间重叠不可相加。_InlineCodeField 的外部标签/两行右侧操作在 320dp/1.6 浅深色通过两项六位数字/标签/键盘操作验证，reviewer 已看该版 approved 原图并确认 R1、R2 resolved；该版 review-final.md 的独立有界结论为 disposition: ship，R1/R2 resolved、许可迁移 match，无剩余 material fix；它不扩大到 Beta.12 或设备/线上证据。登录页许可按钮已移入设置应用分组，settings-final.png 是该版正确设置截图。历史 APK 身份、同一证书、16KiB ZIP、ARM64 ELF16KiB 与原始→merged→stripped→APK 的两种 ARM 库对应链已核验，精确字节/哈希见 docs/MD3MUSIC_BETA.md；源码归档身份留该版冻结后的外部 manifest，不嵌入自引用 ZIP 哈希。Beta.10 的 ship、计数及哈希同样仅属于历史构建。Beta.11 motion-export 4/4 通过，外部 fixture 复用该版实际欢迎/样式组件导出浅深四个 GIF，各36帧/80ms，无生产源码变更；不是沿用旧版图。软件捕获和 GIF 使用合成数据、Flutter 软件渲染及 Windows QA 中文字体；adb-devices 为空，不能证明原生 GPU 折射、帧率、硬件音量、TalkBack、真实 IME 或线上服务，八类 genuine host 只读响应也不等于真实收码或 CDN 验收。历史入口方向来自既有 Mesting 世界、用户参考构图、珊瑚红矢量双角色选择及确认后的 Beta.10/Beta.11 文字方案，没有独立 ImageGen 批准图、approval sidecar、QUALITY BAR card 或随机 FORM seed。

**Key Characteristics:**

- 封面主导，正文使用清楚稳定的主题表面。
- 大标题、粗体分区、紧凑曲目元数据形成层级。
- 中性白灰支撑经典浅色，Beta 蓝色统一导航和选中 chrome，显式 IP 图案与角色保留自身配色。
- 五种播放器共用白色播放操作、进度、系统媒体音量与底部功能。
- 真实玻璃服务持续挂载的悬浮 chrome、独立评论输入/发送、指定 Beta 账号控件和共享编辑/播放菜单；正文背景清楚稳定。
- 原创音符/唱片双角色以可控矢量、关节动作和浅深色可辨轮廓承载入口识别；等待与成功采用共享分段 spinner 和绘制标记。
- 两段给定启动短片与经典标识页保留各自原貌，选择与显式预览分离；中性关闭和局部蓝色确认共享清楚的操作语义。

## Beta.19 performance, retained glass and startup

2026-10-27: preserve the existing premium/full optical world, blur, refraction,
press deformation and capsule transitions. Identical layouts reuse their geometry
matte; genuine size/style changes still invalidate it. Retained glass now also
tracks active ImageFilterLayer pass bounds, including Android overscroll stretch
whose offscreen pass can change without a render-transform change. The stretch
and the glass remain active; foreground coloring is not replaced by a flat fill.

Beta removes the unavailable Mesting account login/register item and redirects
legacy password recovery to the platform account entry. Formal account features
and existing local sessions/data remain. Formal-only gallery, theme and brand
artwork is excluded from Beta assets, with generated-staging cleanup and an APK
content check. Active progress sprites and currently used preview/cover resources
remain available.

Shinchan has seven manually saved weather choices: sun, breeze, sunset, night,
drizzle, storm and parade. The shared painter and walking sprites remain; only
the selected settings preview animates, and cached offscreen/reduced-motion
previews stop tickers. Formal themes retain their legacy mapping when no explicit
weather choice is stored.

Two user-supplied static startup PNGs retain their original bytes, lettering and
composition. Render the entire image with contain and a matching coral surround;
never crop the characters or stretch the artwork. Beta.19 migrates the default
once to the first image, including upgrades, then respects later explicit choices.
Both films and the classic screen remain selectable. Static startup has no timer
or video decoder; dependencies and full-quality optics gate the real app, while
optics and native audio initialize concurrently. Beta's former 720ms minimum is
removed; the formal channel retains its prior minimum.

See docs/fixes-2026-10-27-beta19.md for physical-device evidence and limitations.

## Colors

### Primary
2026-11-02用户确认的局部扩展：底部四个目的地的选中图标改用beta-navigation / beta-navigation-dark，选中小字使用独立亮度的beta-navigation-label / beta-navigation-label-dark。选中玻璃仍为中性透明材质；浅色弱白指示层与深色低透明白指示层避免反向重灰覆盖红色文字。功能蓝继续负责通用操作、链接、输入及普通选择；一起听/音效入口使用紫色，下载入口/成功使用绿色，回顾/排行榜入口使用橙色，收藏入口及已选心形使用红粉色。颜色由BetaFeatureTone的用途显式分配，不依据列表顺序或翻译标题随机映射。

Beta 的 beta-accent / beta-accent-dark 保持蓝色语义色；浅色蓝针对中性分组面板上的小字加深。BetaAppearance 与 app_theme.dart 将它们接入 primary，中性浅灰/深灰面板接入 primaryContainer 和 surfaceContainerLow。正式 flavor 仍由既有主题种子与预设决定，primary-seed / primary-seed-dark 属于该保留系统。

entry-coral 负责欢迎伙伴、指南插画及品牌标题；指南进度和可选控件使用功能蓝。导航红拥有独立语义，不复用品牌插画色。入口暖色浅背景与暗色暖黑背景是该组表面的构图材料，不作为全应用页面底色。

action-blue 是评论发送、新建/编辑歌单确认及 Beta.13 手机号登录的局部共享材质色，白色箭头/对勾/文字形成可辨操作；clear body 保留 alpha 蓝色及高光/折射。歌单关闭使用中性主题玻璃与局部 onSurface 图标。editing-blue / editing-blue-dark 仅负责 Beta 浅/深色光标、Cupertino 选择手柄及其 22% 透明度选区；导航红与编辑蓝分别持有独立角色。

### Secondary
favorite 保留为正式渠道收藏色；Beta 已选心形读取亮度适配的 beta-favorite / beta-favorite-dark，未选读取实际局部 onSurfaceVariant。显式 IP 进度图案/角色保留自身配色，选择外框用蓝色，标签保持 text-primary-*。

### Neutral
canvas-* 是经典纯色背景，surface-* 对应基础表面。正文、说明、弱提示成组随亮度切换；深色半透明文字须结合实际背景判断。Beta 个人页与低阶内容面板使用 beta-panel-*；经典浅色的表面与分层容器为中性白灰，不从功能色 seed 自动生成彩色底层。播放器使用 player-base、白色文字、封面模糊和深色罩层；非当前歌词降亮度。

**The Theme Ownership Rule.** Beta 红色拥有底部导航选择，蓝色拥有通用操作与编辑，紫色拥有一起听/音效入口，橙色拥有回顾/排行入口，红粉色拥有收藏，绿色拥有下载入口与完成状态；歌曲封面拥有氛围，显式 IP 图案与角色拥有自身配色；正式 flavor 继续读取原主题。上方历史Beta.20“统一功能蓝”的说明保留原时点，不覆盖本段的新确认。

2026-11-02一起听胶囊：网易云房间有效时，封面位置显示本人在左后、好友在右前的圆形叠放头像；等待好友时仅本人头像；退出/切换账号回到当前歌曲封面。房间监听只重建头像小区块，重复心跳不重建完整玻璃或播放控件，头像沿用ArtworkImage缓存。胶囊展开/紧凑布局共享此契约。

2026-11-02音频输出：耳机图标采用用户明确指定的原始airpodspro矢量比例和路径，见third_party/audio_glyphs中的来源与声明。Beta点击图标直接进入既有“播放设备”列表，显示真实路由、当前勾选及系统音量，点设备仍等待原生确认；失败不得冒充切换成功。播放器与列表共用图形，设备名称继续读取真实元数据。Formal保留原概览与系统选择入口。

**The Local Contrast Rule.** 经典灰色唱机的顶部收起/更多操作使用局部深色半透明底，底部加强深色罩层，歌手为不透明白字；共享上一首/播放/下一首仍是裸白色图标。

## Typography

平台默认无衬线，中文回退 Noto Sans SC、Microsoft YaHei、sans-serif；没有新增品牌字体包。截图测试的 BetaQACJK 与显式 chip/subtitle 字体是 QA 设施，不是产品字体。QA 字体的覆盖范围不能代替 Android 字体与字形验收。

display 用于主要页面标题，headline 用于分区；详情页使用 detail-title 单行标题，OverflowMarquee 合并 DefaultTextStyle 后使用同一字体、间距和 TextScaler 测量，只在实际溢出时裁切平移，减少动画时静止。曲目使用 title 并单行省略，普通封面标题为相近的小一档（15dp/600）且最多两行。body 承载歌手与说明，空状态行高（1.6）；action 承载按钮，label 配合导航图标。同步歌词从 Beta.6 的 30dp 收敛到当前 24dp，按真实文本与 TextScaler 测量，左对齐、当前行白色、其余降亮度，上下边缘渐隐。

首页短时问候是标题旁的轻量两级文字：时段问候（11dp/500，局部 onSurface 的 65%），实际昵称（13dp/600，局部 onSurface）。不使用胶囊或音符 badge；昵称占用标题余宽并单行省略，保留“首页”单行和系统 TextScaler。

**The Readable Hierarchy Rule.** 长内容换行、省略或滚动，不缩小整页文字来塞满首屏。

## Layout

Flutter 数值为逻辑像素；frontmatter 的 px 是可移植记法，文字遵循系统 TextScaler。页面左右（22dp）、书架间隔（14dp）、分区上/下（28/14dp）。页头计入安全区，共享 EditorialHeader 与平台页头的返回圆钮到标题间隔（16dp）；正文回弹、可刷新。常规封面宽（158dp）、歌单（174dp）；歌曲行方封面（52dp），垂直内距（9dp）。

窗口分级：compact <600dp、medium 600–839dp、expanded ≥840dp；正文内容上限依次为可用宽、760dp、1080dp。Beta 手机和宽屏统一使用同一个官方底栏，不显示左轨或预留 88dp 左轨占位。音乐库可用宽 ≥650dp 时两列变四列；特色封面按可用宽计算并夹紧，保留邻项露出。正式 flavor 的既有自适应导航保持原有行为。

**The Reachable Content Rule.** 编辑式正文保留底部滚动余量；短屏播放器增加可滚动高度，文字缩放时增加空间，保留全部播放操作。搜索内容延伸到悬浮玻璃后方，清空原先整条不透明白底；搜索正文内部保留底部余量。官方底栏处理手势安全区和搜索键盘抬升，shell 仅为搜索正文避让键盘，不能重复移动底栏。设置/聊天/完整播放器/媒体预览分别控制悬浮层显示。

**The Transition Surface Rule.** 搜索与普通路由的正文及当前主题不透明 colorScheme.surface 一起移动，进退连续显露真实上级页面；不把静止整屏遮罩留到卸载终帧。源页保留挂载、焦点/语义/触摸按可见状态切换，不能用透明 scaffoldBackgroundColor 作为遮挡。播放器退场仍连续显露真实下层与已挂载胶囊。

搜索结果顶部是固定顺序的歌曲/专辑/歌手/歌单/歌词分类，取消“搜索结果”大标题。歌曲类别用单一 CustomScrollView / SliverList 惰性构建，保留 52dp 封面、紧凑元数据、裸心、更多和“共 N 首”；专辑/歌单为手机双列方封面，歌手为圆头像列表，歌词以歌曲身份和真实返回片段构成列表。每类按需加载、分别保留分页/重试/滚动，并有成对分类切换；结束搜索销毁本次位置，临时详情/播放器往返仍恢复。同次结果的本地 PageStorageBucket 不越过搜索首页。热搜每页最多 10 词，常规两列、≥650dp 三列，分榜/排名/换页仍在。更多菜单窄屏/大字可换行滚动。AutomaticSongPaging 按新布局的滚动指标提前加载，距离末端不超过 480dp 时可请求下一页；短列表按新指标填充视口，隐藏页面暂停请求。正常状态不显示手动加载按钮，失败保留列表并提供重试。

Beta.12 内嵌搜索为所属 ModalRoute 建立搜索层和结果层两个真实 LocalHistoryEntry；返回先清查询显示搜索首页，再关闭搜索显露实际来源。系统分派、PopScope 与左右边缘共享此优先级，五类与临时详情的会话/位置规则继续。软件生产 Router 检查与 Android 实际系统边缘手势的验收分开记录。

## Elevation & Depth


正文依靠留白、稳定表面与封面层次。特色封面以底部深色渐层承载白字，播放器使用封面模糊与深色罩层。封面局部柔影不是全局阴影；收藏为透明裸心形，不再以圆底/光晕作默认容器。

运行依赖以 liquid_glass_widgets 1.15.0 为基底，官方示例快照、MIT 许可、NOTICE 与 Beta.12 MESTING_PATCHES.md 保留在 third_party/liquid_glass_widgets/；pubspec 的本地 package 覆写使修正随源码可复现。Beta 底部 chrome 直接组合官方 Apple Music 示例的 GlassScaffold、GlassTabBar.searchable 与 GlassButton.custom，由库负责按压、拖动、弹簧和 accessory 形变。应用级 adaptiveQuality=false，指定表面固定 premium/full；不以滚动时降级或平面遮罩替代光学。底栏使用 blur 2、thickness 30、chromaticAberration .01、saturation 1.2、ambientStrength 0、refractiveIndex 1.2；浅/深 lightIntensity 为 .28/.2、fresnelStrength 为 .2/0。浅/深底栏颜色为 #80F2F2F7 / #AA1C1C1E；共享播放胶囊为 #80F2F2F7 / #CC1C1C1E，lightIntensity .28/.18、fresnelStrength .2/0。whitenAtBottom=false，避免滚动底部白罩压平收拢材质。

vendored fallback shader 只抑制深色背景的恒定结构周圈与最小边缘 floor；方向性高光、折射位移、色散、弯月面吸收和按压反馈继续参与渲染。premium 原生分支保留，不能由 fallback 软件截图推断所有 GPU 分支表现一致。浅色纯白背景不伪造纹理；内容背景、收拢/展开/形变及宽屏捕获用于检查背景通透和轮廓，Android 真实折射/自然 glint/FPS 仍待设备证据。

原 MestingGlass 仍用于其他表面，其 standard、blur 12、thickness 22、lightIntensity .22、chromaticAberration .005 及高对比时不透明 surface + outline 是独立实现，不能套用到官方底栏。官方 chrome 使用库自身行为，不能宣称继承原 MestingGlass 的降级或全部透明度均关闭。

**The Floating Glass Rule.** 内容封面、列表与正文背景保持稳定表面；折射用于悬浮 chrome、评论输入/发送、用户指定的 Beta 返回/欢迎/账号/验证码/退出操作与账号字段、新建/编辑歌单关闭/确认，以及共享文本编辑条/扩展框和播放胶囊菜单。每个玻璃控件独立拥有层，不能嵌套玻璃而失去子层折射。封面模糊、播放器音质弹层和短时状态 HUD 各按自身局部背景处理；该扩展不构成正式渠道全局改版。

BetaGlassButton、BetaGlassField 和 BetaGlassBackButton 复用 betaMusicPillGlass，均为 premium/useOwnLayer 和独立 RepaintBoundary。按钮以胶囊轮廓、文字强调及库内按压形变表达层级，字段使用 composer 圆角和无实心填充的 TextField。静态 sidecar 只示意结构、色彩与状态，不能复现库的原生光学。

蓝色 BetaGlassButton 在滚动手势取消时结束按压状态；其 ambient lift 有界（.06），高光使用局部蓝色染色与低透明度（.12），使白字在拖动和取消后仍可读。该变体继续使用原共享蓝色材质、premium 独立层与折射/形变；不能用白色按压罩层或降级玻璃代替这项修正。

BetaGlassMenuSurface 将同一 betaMusicPillGlass 用于编辑横条、展开菜单和播放菜单，使用 premium、useOwnLayer 与独立 RepaintBoundary。BetaMenuLayout 读取实际触发器/EditableText 锚点并避让安全区和键盘，在可用空间内约束宽高与滚动；正常底部胶囊菜单向上展开，退出反向下收，源胶囊不移动。菜单退完后才执行下一项业务或打开后续页面。

评论发送直接使用库内 GlassButton.custom 的 premium 渲染，不使用位图仿制。输入使用 GlassContainer，输入和按钮各自 useOwnLayer 并置于独立 RepaintBoundary；不能嵌套玻璃按钮而使折射失效。发送与新建/编辑歌单确认共用 betaBlueActionGlass：clear body、thickness 32、blur 2、lightIntensity .3、ambientStrength .15、refractiveIndex 1.25、chromaticAberration .01、fresnelStrength .12、saturation 1.2，保留透明材质的高光/折射与正常蓝色。BetaGlassAction 的关闭变体复用中性 betaMusicPillGlass，前景读取局部 onSurface。静态 HTML 仅示意结构，软件 RGB 检查仅覆盖其渲染路径；两者均不能承诺 Android GPU 的立体光学。

## Shapes

小图片轻圆角，封面保留方形比例；普通封面、面板、弹窗用 cover / panel / dialog。按钮、chip、导航为胶囊；播放胶囊 32dp，编辑 sheet 只圆顶部。transport/收藏为透明目标；音质弹层 30dp、普通状态 HUD 25dp，登录成功使用 login-success 的紧凑圆角方形。Replay 年份使用 Cupertino 透明度按压反馈，菜单圆角裁切且不绘制矩形反馈底；更多为锚定 22dp 圆角局部模糊弹层。经典唱臂白色几何轮廓、无黑描边，唱头接触标签外的黑色沟槽。

## Components

- **收起与更多**：PlayerPullToDismiss 仅顶部灰色 handle 接收下拉；生产 PlayerDismissRoute 的 PlayerDismissMotion 直接驱动路由控制器。Beta.13 在正常 forward 进入阶段将 chrome reveal 固定为零，路由切入同步归零；反向退出及手指拖动/取消仍按同一进度连续显露真实下层与已挂载胶囊。达到阈值只完成剩余退出距离，取消以 280ms easeOutCubic 连续回弹，提交/销毁守卫避免重复导航和迟到回调；减少动画即时完成。五样式封面/歌词共用该协议，handle 可点击，封面/歌词/滑块不竞争收起。点击收起与系统返回保留正常路由退场。PlayerMoreMenu 锚定顶部更多，图标行按组分隔、当前样式带对勾，最大宽 280dp、窄屏两侧至少 16dp。
- **收藏**：裸心统一 48×48dp 透明目标，compact 仅改 glyph；按压缩放 .88/120ms。真实成功状态驱动 420ms 局部填充/轮廓与缩放动画，喜欢峰值 1.24、取消喜欢 .8 后归位，方向可中断，减少动画直接终态；失败不播放虚假成功庆祝。保留键盘激活和账号归属。经典唱片/唱臂保留播放和暂停的旋转区别。
- **更多与关闭**：接入 BetaIconButton 的操作保留 48×48dp 目标、tooltip、框架键盘激活与可见键盘焦点；按压仅将 glyph 缩放至 .9、透明度降至 .66（140ms），抬起或取消恢复，减少动画直接终态。保留关闭 glyph 自带的小圆 X；不额外生成大圆按压底。经典灰色唱机原有的局部深色对比底继续由调用者提供。
- **播放选择与历史**：单点只播放一首，明确“播放全部”才导入集合；已有手动待播提供保留/替换选择，手动项优先自动项。普通队列耗尽在完成或下一首时由平台继续，自动项在当前队列中有独立标识。上一首根据实际播放历史返回，无历史则重播当前；普通自动续播不取得 FM 反馈归属。MestingAudioHandler 是唯一播放 owner；后来暂停/停止/seek 会使慢速下一首结果失效。
- **队列时长**：手动与自动项共用 QueueTrackDuration，显示对应录音正值总时长或 --:--；试听解码片段不作为总时长，非正值媒体信息不能覆盖正值目录数据。平台秒/毫秒别名统一解析，缺失的可见行通过只读元数据独立更新；两并发、同身份合并、有界缓存/超时和账号/录音/hash 检查防止错配。不以自动播放或换歌探测时长，失败不阻塞列表，不改顺序、播放归属或进度。

- **按钮与表单**：既有 PlatformStyle 填充/描边最小 48×48dp，文字按钮 44×44dp；primary/onPrimary、低阶表面或安静文字区分层级。普通输入 18dp 圆角，焦点 primary 1.5dp 描边，错误使用主题 error。Beta 指定账号操作使用 BetaGlassButton：默认高 52dp、横向内距 18dp、15dp/700，强调版本使用当前亮度 Beta 蓝文字；调用点可设高度，不能把所有调用都记成 52dp。BetaGlassBackButton 为 48dp 圆形和中文返回语义。BetaGlassField 为 24dp 圆角，字段内距 20/17dp、外加横向 3dp，字段自身保留焦点、校验、键盘与错误语义。Beta.11 手机号页采用简洁标题、圆形返回、宽输入与单一主操作；_InlineCodeField 仅管理布局，验证码操作默认高 44dp、13dp/700，按 TextScaler 和六位数字测量宽度。窄屏大字将 14dp 标签移至框外，suffix 分为两行并增高，输入基准由 18dp 调整为 16dp 且继续使用系统 TextScaler，字段保留完整六位数字所需空间；320dp/1.6 浅深软件验证中六位 863432 的 maxScrollExtent<1，外标签/键盘主登录 hitTestable。按钮始终位于框内右侧，结构上为 Stack 内独立兄弟 premium 玻璃；旧整行操作已被最新要求取代。Mesting 新登录/注册在 Beta 标“暂不可用”并禁用，保留实现与既有会话；正式渠道继续原控件。
- **许可入口**：所有登录类页面移除“开源许可与致谢”；Beta 设置应用分组中的 settings-open-source 项调用共享 showLicensePage，登录表单聚焦认证与真实协议/隐私同意。Beta.10 登录页许可按钮仅作为历史实现保留在交付记录。
- **手机号当前状态**：Beta.13 的 +86 常驻，手机号方式使用手机图标；验证码与登录共用重复提交防护，但各自仅在自身请求时显示 spinner。登录主操作为共享 action-blue 玻璃白字，验证码平台成功后才出现“验证码已发送”成功 HUD 与倒计时。上述 Beta.11 窄屏响应测试为该版历史证据，不能作为本轮设备输入法或真实收码证明。
- **文本编辑**：Beta 的既有账号、搜索、评论、歌单、资料与社交/聊天字段及 vendored 搜索通过同一 builder/selection controls 接入。横条的 > 展开为纵向玻璃菜单；只提供可用的粘贴、选择、全选及具有 hints 的系统自动填充，展开后非数字字段可插入 #，多行非数字字段可换行。密码/只读/数字条件限制动作，不加入未接功能；由 EditableText 提供可用性、锚点、选择与格式化，插入使用 userUpdateTextEditingValue。细蓝光标、22% 蓝选区和 Cupertino 细杆圆点手柄共用编辑色。菜单入/退（230/190ms）与展开（260ms）局部配对，原字段继续拥有 IME、最大长度和校验；软件 fixture 不认证真实 Android 输入法或自动填充。
- **账号恢复呈现**：酷狗本地凭证读取失败显示“账号暂未恢复，登录信息已保留”，分别提供“重试恢复”和“重新登录”，不把错误绘制为游客。旧加密内容的保留与新认证接受规则见 PRODUCT.md；该错误界面不是此前设备故障根因已验证的声明。
- **统一账号与同意组**：BetaAccountCard 在我的/设置复用头像、真实昵称/来源与一个登录或管理操作，取代双账号宣传模块；游客登录进入共享欢迎页。BetaConsentRow 将 14dp 小圆标放在 44dp 语义目标中，与正文及独立协议链接整组居中，使用紧凑 Wrap 适应大字/小屏；标注红框不属于产品边框。具体入口构图留在 auth surface brief。
- **Chip / 面板**：普通 chip 选中为 primary 轻填充。PlatformPanel 为 22dp 圆角、20dp 内距的不透明 surfaceContainerLow。Beta 进度样式/角色选择用蓝色轻填充、边线与轻影，标签保持主题主要文字；加载、失败、空数据及适用重试如实显示。
- **导航**：四目的地和独立搜索延续，首页实心图标，选中图标/文字用 Beta 蓝色。底栏基础 64dp、搜索/accessory 50dp，随 TextScaler 最多加 28dp；内距 20/16dp、间距 8dp。滚动超过 88dp 收拢 accessory，回到 24dp 才展开，再点当前 tab 回顶部。局部 ValueNotifier 合并同帧滚动通知到帧后更新，只让底栏读取几何状态，premium/full 与完整动画保留；光学参数以当前 Elevation & Depth 为准。MusicShell 持久持有来源 tab 与滚动位置，BetaMusicShell 在播放器/设置后方保持挂载，chrome 仅改变透明度与显露。底部目的地结束本次搜索，临时路由仅暂存。内嵌搜索通过 BetaSearchBackHistory 的嵌套 LocalHistoryEntry 暴露真实返回目标，PopScope/BackButtonListener 与左右 32dp BetaEdgeBack 按“结果→搜索首页→来源页”处理；不抢占内部书架/滑块手势，实际 Android 系统边缘返回仍待真机。
- **播放条**：有当前媒体才显示，作为官方底栏 accessory；32dp 方封面、歌曲/歌手，仅保留播放/暂停与下一首两个裸图标。点击打开播放器、左右滑动切歌。较窄且文字放大时可省略歌手；不按宽度添加队列按钮。GlassButton.custom 基础高度 64dp，只订阅 playing 布尔值避免随进度事件重建，播放/暂停使用共享实时 toggle 操作以便快速再次点击取消淡出；复用既有音频服务。
- **播放条长按**：测量现有胶囊锚点后打开共享玻璃菜单，源胶囊位置不变。上组为喜欢/添加歌单/当前队列，下组为歌词、平台歌曲的评论/音质及可用播放模式；仅真实 FM 归属提供“不喜欢这首”。菜单以 320ms 局部淡入/上移/缩放展开，反向下收，等待 route.completed 再调用原仓库、登录或音频操作；切歌后拒绝旧 intent。静态 sidecar 只表示菜单形态，不实现真实业务。
- **播放器**：Beta 默认沉浸封面；cover、classic、aurora、cassette、lyricStage 五种样式保留上半区各自视觉/动态身份，下半区统一使用 ApplePlayerControls。顺序为进度与时间、裸白色 Cupertino 上一首/播放暂停/下一首、真实系统媒体音量、评论/音质/当前队列；封面和歌词两种状态都保留同一组控件。顶部小封面、歌名/歌手与模糊封面背景组织歌词页，点击同步歌词跳转进度。PlayerContentTransition 使用局部淡变、微移和缩放的成对入退，默认进入 360ms/退出 280ms；封面/歌词方向相反，上一首/下一首读取 userCommandStream，样式按枚举方向切换；共享 transport 与音频 owner 不重建，减少动画时该过渡归零。
- **播放目的地与对话框音量**：工具栏的本机输出采用音频广播轮廓，耳机路由采用成对耳机；输出对话框的扬声器、耳机与选中对勾共用应用原创矢量，不是导出的 SF Symbols，也不依据通用耳机路由推断 AirPods 品牌。实际名称/类型仍来自原生路由。新音量外观仅用于输出对话框：安静的粗轨道（7dp）、白色小滑块（20×16dp，激活到 23×18dp）、48dp 高响应区和百分比语义；继续使用框架 Slider 的键盘/焦点/取消与既有 MediaVolumeController。主播放器音量外观按原规范保留。
- **滑块语义与系统音量**：进度合并语义“播放进度”读已播/总时长，音量“系统媒体音量”读百分比，保留原生可调动作。音量轨纤细视觉与 48dp 高响应区并存，拖动本地即时更新。Dart 串行保留最新待写值，Kotlin 抑制重复事件和相同步进，前台刷新 STREAM_MUSIC，无宿主禁用。原生写入工作量与 Android 硬件/TalkBack/帧率属于不同验证边界，后者仍待真机。
- **进度角色**：小新宽（56dp），Kitty/库洛米为透明背景的头部（28×28dp）；无底座、额外丝带/冠饰或前导点。Slider 取消额外轨道内距，角色中心按实际可用轨宽与当前进度定位，端点不额外夹紧角色中心；父级留白容纳外伸。控制区为角色预留真实上方空间，避免遮挡歌手和时间，角色忽略指针，不改变进度语义与实际 seek。
- **音质**：五样式共用持久化偏好与 30dp 圆角浅/深半透明弹层。PlatformQualityCatalog 依据当前歌曲正值资源 hash/显式资源档位生成选项，会员标志不制造资源；只显示已有档位，未知/失败手动重载，无自动循环。弹层随歌曲更新，选择绑定录音 ID。会员提示只在尝试选择后按平台结果出现。档位保留各自编码 hash，严格请求选择的来源，避免以 FLAC hash 请求标准档仍返回 FLAC；勾选、提示和 footer 与实际引擎来源一致后才保存偏好。既有 handler 保留进度、播放状态、队列/模式，失败保留旧流/旧偏好；偏好、实际、试听、降档与待平台确认分开表达。
- **音质等待与保留**：成功解析的目录只在当前进程内保留，最多 64 个录音；provider 继续观察账号 future，登出、账号或 token 替换使旧目录失效，淘汰会释放 keepAlive。失败不保留，重新打开或明确重试可重新请求，不写磁盘也不推断权限。等待到结果的内容高度以 280ms 平滑变化，结果前景以 320ms 淡入并上移 7dp；玻璃本体不包进到达动效，减少动画直接稳定终态。
- **同曲媒体修订**：currentMediaRevisionProvider 只随媒体项发布递增，使同 ID 音质/元数据变化能够更新 currentTrackProvider，不扩大为位置 tick 订阅。resolver 有损实测码率优先于请求标签；不符/未知维持失败恢复契约，不能以顶部成功文案作为实际档位的唯一证据。
- **评论**：排序（最热/最新/最早）与范围（全部/歌手/我的）两个下拉并排单行，保留排序范围说明、回复/删除与真实线程归属；日期、赞数与排序说明读取局部 textSecondary 以保持浅深色可读性。浮动 composer 使用 24dp 圆角输入，蓝色 48×48dp 发送作为兄弟玻璃按钮；输入 16dp/1.4，键盘显示最多 2 行，否则最多 4 行，最多 1000 字。KeyboardVisibilityBuilder 观察当前原生 View.viewInsets，不读取已被 Scaffold 消耗的 body inset；发送中禁用并显示真实进度。
- **评论等待与到达**：初次资源/评论读取只显示裸 BetaActivityIndicator，不添加等待卡片。评论行以真实 comment ID 保持稳定 key，320ms 淡入/上移只作用于新到达的前景；分页追加时已完成的行保留其到达状态。排序、范围、账号/请求守卫与真实写入结果继续由原业务持有，失败仍提供可操作原因与重试。
- **评论菜单与 glyph**：BetaAnchoredMenu 打开时测量各自触发器的真实 RenderBox 宽度并约束菜单，最小触发器 90×44dp 不能当作固定弹层宽度；勾选/间隔/Expanded 标签在相同宽内布局。22dp 圆角菜单使用主题表面。PlayerCommentGlyph 以同一绘制函数提供圆形引号气泡并在教程复用；音质为 Cupertino 中间音箱，原操作语义和目标保留。
- **音乐伙伴与预览**：欢迎/指南复用原创音符和唱片双角色，身体、四肢、面部与耳机由矢量分层绘制，深色外部轮廓提高对比而非全体发光。五种样式小预览共用一个局部绘制时钟与真实样式偏好，每张卡有独立可辨舞台、文字/勾选与 selected 语义，邻页通过 TickerMode 暂停；演示不新建音频服务。入口/指南的具体顺序与构图见对应 surface brief，不作为其他页面模板。
- **装扮与启动**：保留浅/深/系统、自定义图片/视频、五种播放器与显式进度配色/角色；品牌选择器、重复皮肤说明/经典卡片、DRESS UP、followTheme 及 IP 装饰开关继续移除。图标固定 coral，启动页独立提供两张给定静态图（图一默认）、“音乐伙伴”“唱片派对”两段视频及经典 M 标识页；Beta.19 首次升级迁移到图一一次，之后保存用户选择。静态图完整 contain、同色留白、无音频；首个完整解码帧绘制后保留约 500ms，同时等待真实依赖就绪。选择行以 BetaPressSurface 局部圆角染色/缩放（.977）反馈，持久化成功才勾选；静态海报与显式预览分开，列表不自动播放。预览关闭是 48dp 圆形独立 premium 玻璃按钮。短片主体完整保持原比例，空余区域使用同一控制器的实时视频纹理模糊延展（sigma 24），请求透明状态/导航栏，保留原声。每个冷进程一次，依赖就绪和视频完成共同放行业务/恢复；未完成后台暂停后接续，完成后不重播，解码/停滞有界回退经典。预览单独持有控制器，退出释放，不重置进程门控。旧品牌迁移、显式 IP 保留、完整 IP 主题退役、背景强度 .58 与背景性能 automatic 延续；后者不降低指定 premium/full 玻璃。平台账号继续实际 coral 应用图标，正式主题契约保留。
- **首页问候**：冷进程首次可用的首页标题旁显示按时段与实际昵称生成的轻量文字，可见五秒后局部收起；无胶囊或音符 badge，长昵称单行省略且不挤成两行首页标题。淡入/微移与尺寸变化统一 320ms，减少动画归零；进程级非 autoDispose 标记防止后台切回和路由重挂重播，不作为其他页头的固定模板。
- **状态反馈**：showMusicNotice 以顶部安全区下的单个半透明 HUD 替换前一个通知；短标题加图标，支持浅深色、淡入/顶部滑入/缩放与减少动画。普通提示省略旧说明，错误/警告保留可行动原因；Semantics liveRegion 读出可见信息。Beta 真实成功的 check 图标改用共享 900ms 绘制标记，2600ms 后反向退出，普通提示仍为 1900ms；评论“已发送”和验证码成功共用这一规则。不建立第二套业务成功状态，也不将软件回调等同于真实收码/云写入。
- **等待与登录成功**：BetaActivityIndicator 统一分段 Cupertino spinner 的尺寸/语义，在所属请求区域呈现并禁用重复提交。BetaSuccessMark 圆环/对勾绘制为 900ms。登录成功使用 login-success 的 104×104dp 圆角方形，位于 SafeArea 内顶部 76dp、指南页头下方的上部中央，仅绘制自身方形；进入/退出为 300/220ms，1800ms 后反向退出。指南与成功事件同帧挂载、可见且可操作，只有 HUD 忽略指针；Next/Skip/Back 始终继续同一个指南状态，延迟完成回调不能重置页码或在完成后重开指南。减少动画时 HUD/标记直接终态且退出时长归零，反馈停留计时保留。原创 0.48 秒 SoundPool 提示音只随新交互成功事件调用一次，恢复/刷新及重复认证不触发，不请求音乐焦点或新建播放 owner；未认证真机响度。指南跳过以 340ms 当前页/第八页淡变微移，仍需“开始使用”；普通翻页仍为 380ms。欢迎 Navigator 的 child dispatcher 取得返回优先级，法规页先返回所属 Navigator。其余减少动画按实际组件分支记录；退出失败保留原会话和可恢复错误。
- **封面恢复**：推荐、搜索、歌单与播放器共用平台封面规范化，接受有效 HTTP/HTTPS 与协议相对 URL、替换尺寸占位并跳过裸文件名。列表元数据回退仅只读，合并同歌曲请求、最多 3 并发、缓存最近 256 个成功封面；临时失败不永久缓存，也不影响播放或触发云写入。
- **歌单编辑**：PageView viewportFraction .72，中心方封面、邻项露出、相机/圆点指示；第一项现有/相册，另六项本地模板，空封面有加图占位。Beta 新建与编辑固定页头都使用 48dp 独立 premium BetaGlassAction：左侧中性玻璃 X、居中标题、右侧共享 clear-body 蓝色白对勾；确认材质与评论发送一致，关闭不染蓝。键盘上移、表单滚动；名称校验、保存中禁用返回/重复提交与 spinner、失败保留草稿/封面、成功才关闭继续由业务页面持有，材质组件只负责光学/反馈。结果为 640×640 不透明 PNG；正式渠道保留原操作控件。
- **Replay 与 owner**：按当前账号本机每日记录聚合年/月，年份 Cupertino 透明度反馈/圆角菜单，选中月进入视野；封面氛围、大排名、时长和“歌曲封面”披露共存，不补算缺失月份。账号归属、收藏/播放唯一状态与既有推荐来源继续适用。

封面/歌词切换与歌词跟随读取 disableAnimations，主题背景也尊重减少动画；局部文字淡变与 sheet 键盘动画仍固定时长，不宣称全应用完全适配。

### Beta.21 current component rules (authoritative)

2026-10-27：当前 Beta 在原有视觉世界内扩展，沿用本文件的语义配色、字阶、premium/full 玻璃、按压形变和胶囊动效，不引入新 token 系统。此节明确覆盖 Overview 及上文“音乐伙伴与预览”“状态反馈”中已退役的矢量音符/唱片身份与小型成功 HUD 绘制标记；旧说明保留为历史，不是当前规则。独立登录成功 HUD 的既有规范仍有效。表面方向见 [.impeccable/surfaces/beta21-refinements.md](.impeccable/surfaces/beta21-refinements.md)。

- **启动身份规则**：欢迎/指南伙伴采用原启动图派生的一张 `companions-atlas.png` 双角色四姿态图集：左侧坐姿黑胶，右侧高挑奶油色耳机，手搭唱片，响应尺寸变化仍保持搭肩关系。3D 渲染姿态通过二维图像换帧、轻跳与点头呈现，不称作新 3D 模型或实时 3D 渲染。独立代码绘制的小写 `hi` 气泡和三道手指线默认可见，随挥手/轻点轻弹；可眨眼、点头和问候，离屏、后台、减少动画时停止。原始启动图字节及 `assets/branding/welcome/provenance.json` 的来源/提示记录保留；旧分离图集不作为当前素材。
- **真实结果反馈规则**：小型 Beta 成功 HUD 仅显示结果文字，保留替换前一通知、浅深材质、live-region、停留和退出；不再显示或绘制绿色成功 glyph。错误/警告原因与独立登录成功 HUD 保持各自用途，不以演示或点击替代成功状态。
- **共享待播规则**：sheet 与播放器面板共用 `BetaPlaybackQueue`，按 handler 权威顺序显示，自动推荐用来源文字标识，不将手动/自动重新分组后的视觉顺序冒充实际顺序。排序手柄为 48dp 目标，支持左滑移除，随机和循环独立。拖动按身份快照在实时队列中重定位；既有音频 handler 保持唯一播放 owner。
- **同一玻璃卡片规则**：输出路由列表在当前输出玻璃卡片内展开，保留当前设备、音量与底部动作层级；只呈现原生确认的选中项及公开可转移项。切换中显示等待，原生确认/回读后才标选中，失败保留原因与重试。次级“系统设备管理”承担系统配对、授权及不支持的切换，“完成”关闭卡片。
- **滚动背板规则**：登录页手机号/验证码维持原独立 premium 光学、按压和 overscroll；实际 surface 在 `BetaGlassScrollBody` 的滚动合成内部绘制供玻璃采样，不新增平面盖层或降低折射质量。
- **入口与指南边界**：Beta 移除重复的自动首次法律卡片，但欢迎页主动同意行与独立法律链接仍在，且不自动写同意。八页指南的文字/预览对应五类搜索、播放/歌词/评论、实际输出、账号及任务限制、真实待播、启动/进度选择与五个可保存的播放器样式；预览只使用局部绘制时钟和现有偏好，不另建音频服务。法律正文按 flavor 和实际服务/存储/账号退出边界展示，联系方式依用户决定暂缺；听歌时长不自动上报、旧奖励不等于新增权益。

本节只记录当前生产代码中可复用的组件规则，没有重新生成视觉系统、批准 comp、随机 seed 或 QUALITY BAR card。31 张生产控件主机捕获使用合成 fixture 与 Windows QA 字体；它们不认证 Android GPU、IME、TalkBack、实际蓝牙转移、系统手势或性能。`.impeccable/design.json` 存有本轮之前的叙述/示例漂移，未在这次普通扩展中修复，也不作为上述退役身份或 HUD 的新权威。

### Release 1.0.1 current component rules (authoritative)

2026-10-27：本节是同一视觉世界内已确认的扩展，覆盖上文 Beta.21 的纯文字成功 HUD、暖色欢迎背景及旧版更新关闭说明；其他既有规则继续有效。方向见 [.impeccable/surfaces/release-1.0.1.md](.impeccable/surfaces/release-1.0.1.md)。沿用字阶、语义色、Cupertino 操作与 premium 光学，不新建 token 系统或 UI comp。

- **中性入口规则**：欢迎页使用近白/近黑底，角色与品牌继续在操作上方；手机号为蓝色完整胶囊与 `CupertinoIcons.device_phone_portrait`，微信使用完整中性玻璃，游客/其他方式为一组次级操作。角色 atlas、舞台、默认 hi/三道手指线、搭肩位置与全部动作保持原字节，暖色角色本身不改色。
- **静态成功规则**：小型成功 HUD 恢复使用现有主题成功绿的静态圆环/对勾（`BetaSuccessMark(animated: false)`），保留可读结果文字、live-region 与容器进退。不要恢复标记绘制动画，也不要将此规则套到独立登录成功 HUD。
- **等待不降材质规则**：评论发送保持原 48dp 独立蓝色 premium 表面，通过 input/focus 守卫阻断重复操作。仅发送子控件使用 `beta_activity_indicator.dart` 的自绘 Cupertino 风格八刻度：白色、radius 12、刻度 alpha 80–255，前导刻度完全不透明；1 秒局部绘制周期，TickerMode 关闭或减少动画时暂停。它替代原 CupertinoActivityIndicator 的较低刻度透明度，同时保留 IgnorePointer、ExcludeFocus、发送语义及原光学，不改变蓝色玻璃来掩盖等待标记。共享 BetaGlassButton loading 继续保持同一光学层并阻断指针/焦点，此局部替换不成为全应用 spinner 规范。
- **立即可见的更新规则**：手动检查先展示同一套 `BetaGlassMenuSurface`（圆角 34dp）抽屉，随后由单一控制器更新检查、当前、可用、下载/暂停、校验、权限、安装或错误内容。保留抓手、强标题、关闭、安全区和主题蓝主操作；已打开系统安装不能描述为安装成功，缺失发布说明就省略。短屏正文可以滚动，关闭和重新打开不重置已有下载。
- **真实细进度规则**：下载使用 4dp 胶囊轨道、主题蓝填充和百分比/真实字节对，标签使用 tabular figures。首帧从已持久化进度开始，后续仅填充以 180ms `easeOutCubic` 平滑，标签始终直接报告真实数据；减少动画归零。到 100% 后使用独立校验/安装状态，进度动画不承诺校验或安装已成功。此前 6dp 捕获不作为当前尺寸规范。

更新的公开源、真实 build-code 顺序、续传/校验、安装权限及隐私边界由 PRODUCT.md 与实际业务 owner 持有；展示层不引入第二个更新任务。生产控件的主机捕获仍使用合成夹具与 Windows QA 字体，不证明 Android 玻璃 GPU、系统安装或真实设备交互。既有 design.json 漂移未重写，也不将其旧叙述固化为本版规则。

### Release 1.0.2 current component rules (authoritative)

2026-10-27：同一视觉世界内的局部扩充，不重建色板、字阶、光学或 sidecar。本节覆盖前述设备选择路径和装扮入口的旧说明；历史冻结版本的记录保留。

- 更新详情的标签和值以 12dp 相邻间距组合，大字不足时换行，不拉到两端。装扮集中在设置，“我的”只保留设置入口。
- 耳塞使用同一 Tabler MIT 改编轮廓：24 单位坐标、1.65 单位描边；同一绘制函数按工具栏/当前设备 40dp、列表 29dp 缩放。“本机”使用细线手机轮廓；不把耳机图标当作品牌识别。
- 设备选择在原 premium 卡片内展开，保留曲目、音量、关闭与完成；选择后的真实路由与“已选择，播放时生效”分开。不能将暂停偏好标成活动切换成功，不能以系统面板代替用户确认的卡片内操作。
- 新音乐栏目复用封面书架、23dp 分节标题、22dp 正文边距、14dp 横向间隔和现有语义色；场景为可操作的中性标签。空、错、等待与目录详情均接入真实业务 owner，不制造新视觉系统。

验证范围仍是生产 Flutter 控件的 Windows 主机捕获和软件交互，未认证设备 GPU/音频硬件。旧 design.json 漂移只记录，不作为本轮系统改造。

### Release 1.0.3 current component rules (authoritative)

2026-10-27：1.0.3 延续用户确认的 Apple/iOS27 Cupertino 与 premium 玻璃世界；此节补充新增设置、资料与播放工具的实际组件规则，覆盖共享按钮禁用态及更新说明入口的旧描述。既有语义配色、字阶、封面氛围、胶囊动效、启动图与角色素材继续作为视觉依据。方向和验证边界见 [.impeccable/surfaces/release-1.0.3.md](.impeccable/surfaces/release-1.0.3.md)，没有建立新身份、token 系统或 UI comp。

- **完整禁用状态规则**：共享 `BetaGlassButton` 与 `BetaGlassAction` 的不可用态使用中性玻璃及局部 `onSurfaceVariant` 文字/图标，分别适配浅深色；材质本体继续保持独立 premium 光学，不以整层透明度代替前景与底色配对。指针、键盘焦点和 enabled 语义同时关闭。请求等待保留原操作的蓝色或中性材质，阻断重复操作；滚动取消仍清除按压残留。触感关闭后，“体验触感”保持可读、不可点击。
- **次级工具页规则**：`MusicFeaturePage` 复用中性主题 surface、独立圆形玻璃返回和清楚标题（22dp/700）；内容最大宽度（760dp），资料、均衡器与音效列表沿用正文边距（22dp）及滚动布局。系统 TextScaler 继续参与测量，小屏大字以换行和滚动容纳内容，不缩小整页文字。
- **资料与地区规则**：头像先于昵称，性别、生日、地区使用同一中性分组与 Cupertino 选择；个性签名和保存操作继续使用现有字段与玻璃语法。只呈现当前平台支持的六项资料。地区使用离线省/市名称的双列选择，已有目录外值继续可见，不以默认选中项冒充已保存资料。头像预览、提交中与“等待审核”按真实阶段显示，保存与上传均为明确操作。
- **可读均衡规则**：顶部开关卡区分关闭、连接中、等待音乐和已生效；蓝色增益折线只表示当前选择值。预设使用现有 ChoiceChip，频段行并列真实频率、可拖动轨道与 dB 数值。所有频段的可见圆点直径（6dp）、轨道（2dp），拖动响应区高（48dp）；不加滑块阴影、按压放大或 overlay。频率名称、分贝值和框架可调动作保留，设备返回的频段数与范围决定实际列表，主机夹具的五条频段不定义设备能力。
- **音效操作规则**：社区、耳机、明星使用 Cupertino 分段切换；搜索明确写为“筛选已加载的音效”，热门/最新沿用选择 chip。当前音效卡和列表同时显示实际均衡预设与等待/生效状态。应用图标提供对应音效名称的 action label、tooltip、selected/enabled 语义和可用时的 tap action；蓝色加号与对勾继续属于功能操作和选中状态。
- **媒体与定时规则**：MV 以实际视频区域为视觉重心，播放、进度、全屏和清晰度属于同一视频控件；等待、缺少 MV 和失败原因如实呈现。定时关闭复用既有玻璃 sheet、Cupertino 时长选择和一个明确开始操作，显示倒计时或“播完当前歌曲”，不另建一套播放面板。
- **版本说明规则**：现有更新玻璃抽屉保留版本与下载状态；“查看此次更新”打开对应版本的说明 sheet，即使当前已经是最新版也可查看。标题、版本和逐条说明来自该版本实际说明，未来版本没有正文时如实留空，不借用当前版说明。

独立 finish review 的最终 disposition 为 **SHIP**：persistence、fidelity 与 ceiling 均通过，音效应用图标的 R1 语义问题及用户要求的 6dp 均衡滑块已 resolved，无开放发现。最终生产控件捕获位于 `.codex-artifacts/2026-10-27-release103/final-ui/`，使用合成账号、音效目录和 MV 画面及 Windows 专用 QA 字体；这些字体不是 shipping 资源。本节记录源码与主机布局/交互证据，不认证真实账号写入、Android GPU 光学、TalkBack、实际音频或安装；Android Release 构建、原签名身份、music 发布及生产 HTTPS 完整下载/续传已完成，详见同版交接。既有 sidecar 漂移没有在本次局部补充中重写。

## Do's and Don'ts

### Do:
- **Do** 使用语义色并检查浅深色、蓝色选中 chrome、粉色收藏和绿色完成状态与装扮背景的最终对比。
- **Do** 让封面、歌曲、歌手与真实平台内容承担信息层级。
- **Do** 提供中文 tooltip/语义标签、selected 状态、文字缩放及可达操作。
- **Do** 让加载、空状态、失败、草稿与账号归属如实可见。
- **Do** 在纯色/内容、浅/深、收拢/展开/形变配对中检查玻璃，保持指定 premium/full 质量、独立层与连续路由进度。

### Don't:
- **Don't** 把 Beta 条件组合推广为正式分支的全局布局或默认播放器。
- **Don't** 将 Beta 指定账号控件的玻璃扩展成全部正文/列表或正式渠道的默认材质，或把评论发送嵌套进输入玻璃而丢失独立折射。
- **Don't** 以无意义眉题、重复圆角外框或装饰渐变替代真实内容。
- **Don't** 把 fixture、歌曲封面、未记录月份或失败写入描述为生产素材、艺人肖像、历史统计或成功。
- **Don't** 给共享播放 transport 恢复大圆面，或把两个滑块合成无名且不可调的语义节点。
- **Don't** 为本轮接入 BetaIconButton 的更多/关闭叠加大圆按压底，或让登录成功 HUD 阻断指南的 Next/Skip/Back。
- **Don't** 以软件截图宣称真机 TalkBack、硬件音量、GPU Apple 效果或线上服务已验收。
- **Don't** 用连续装饰描边、滚动时降级或不透明平面盖层替代光学修正，或把未知队列时长编成真实数据。

未固化为规则：软件渲染中的平面玻璃外观不是原生 GPU 光学保证；浅色纯白/内容背景的光学、fallback/premium GPU 一致性、真实系统/预测返回、IME/自动填充、TalkBack、媒体焦点/提示音响度与启动原声解码仍待设备验收。局部减少动画仍不完整，部分时钟与固定计时继续；收起 handle 的 112×36dp 手势区和指南跳过等紧凑目标按实际尺寸披露，不能推广为触控尺寸规范；测试人像和教程字体 glyph 不是生产素材/图标规范。Beta.13 reviewer 的 R1–R4 resolved 只覆盖其所读源码、软件检查与提供捕获；没有证明此前设备账号丢失的触发原因。历史 Beta.10/11/12 测试、捕获、发布身份及评审结论各属于对应冻结构建。范围为通用 Android 兼容，没有机型专属优化；软件捕获、历史36帧/80ms GIF、120帧重建工作量、历史主机只读查询及 Beta.12 时长元数据响应均不替代真机 GPU/FPS、真实短信/账号或线上播放验收。

### Beta.19 native material verification

签到页三个操作保留白底黑字及原 premium 玻璃。页面回弹的 ImageFiltered 会隔离 Scaffold 底层，因此签到正文在滚动内容内绘制同色 surface，供玻璃实际采样；禁止用禁用回弹、平面白底按钮或降低折射质量掩盖问题。所有 BetaGlassButton 在滚动赢得手势时取消按压高光，普通点击与键盘反馈保留。账号恢复覆盖层拥有独立 Material/安全区，不继承 WidgetsApp 诊断文字样式。新入口、启动和天气契约见 [Beta.19 验证记录](docs/fixes-2026-10-27-beta19.md)。

原生验证采用独立 `.beta.benchmark` 身份、内存偏好和静止封面夹具。只将通过可见入口门控与胶囊展开/收起断言的场景计入性能对比；它不认证所有业务场景稳定 120fps，也不构成进程 CPU 占用下降百分比。日常 Beta 的安装与冷启动单独检查。


## Beta.20 interaction contracts

- Keyboard search: the accessory wrapper includes the inner pill's IME extent in its layout/hit bounds; it does not add another visual translation or replace premium optics. Taps on the visible field must not reach songs behind it during IME changes.
- Song comments, playlist comments and reply threads use the root navigator. Their opaque page owns its composer and covers persistent shell controls; audio ownership and background playback remain unchanged.
- Signed days use a pale green rounded 44×48dp cell with the date and an inset check, independent of today's blue outline. One-line dates scale down only when their calendar column cannot fit the requested glyph width. The month count and progress use completion green; the auto-sign-in switch retains the functional tint.
- StartupImageSurface reports its first decoded painted frame. StartupVisibilityGate measures the short static-image hold from that callback, not process startup; audio/optics initialize concurrently. Videos and formal-channel timing keep their prior contracts.
- Live listening synchronization was not credited in the isolated test: cumulative server time stayed 850 seconds and the user confirmed the official app still showed 14 minutes and no daily record. Automatic duration reporting is not integrated. Today's already-claimed member reward cannot prove new task credit.


## Release 1.0.5 current contract (authoritative)

2026-10-28：沿用既有 Apple/Cupertino 和完整 premium 玻璃世界。资料、MV、均衡/音效、触感和欢迎页的滚动合成内提供真实同色背景；定时弹层统一应用主题。完整播放器更多菜单移除重复歌词项，默认折叠“封面样式”；工具栏设备 glyph 统一光学尺度，卡片/设备列表尺寸不改。均衡圆点继续 6dp/轨道约2dp/48dp响应区。

BetaLiquidMenu 从真实胶囊或输入区域分离，以同一几何进度反向融合；Impeller 使用共享 premium 层的 SDF 连接，Skia 使用既有光学回退。绘制 tick 不重建菜单内容，文本前景可以淡入，但不以祖先 opacity 隔离 live glass。减少动画跳过大幅形变；真实编辑动作仍由 EditableText 处理。底栏附件统一几何时钟，保留重定向和快速反转的连续位置。

MV 全屏请求横屏，退出/系统返回恢复竖屏和原详情，同一控制器保留位置。音效列表用一致的本地主题 symbol 代替旧远程缩略图，业务预设能力不扩张。Track 只清理末尾音频扩展名的显示，原持久化标题和文件身份保留。

本轮 179 项受影响 Beta 回归、56 项选定 stable 回归通过；42 张主机控件捕获已复核。来源与边界见 docs/fixes-2026-10-28-v1.0.5.md 和同版交接。主机结果不认证实际 Android GPU 液态效果、120fps、真实 P8P 字节贡献或安装。GitHub 归档和 music 后台分开记录；music 的 1.0.5 管理 UI 发布被浏览器 URL 安全检查中止。


## Release 1.0.7 extension (2026-10-28)

The established Apple/Cupertino world remains authoritative. The approved fixed
three-column feature launchpad uses quiet grouped neutral surfaces, blue native
glyphs and strong Chinese labels; no per-tile live glass is added. Root tabs are
发现 / 功能 / 音乐库 / 我的. Player dismiss and overflow share one 48dp premium
circular lens, and the overflow liquid source stays inside the button edge
facing the menu. Existing 400ms/240ms liquid trajectories and optical settings
are retained. Each shuffle/repeat state has a distinct glyph.

New local-library, recognition, audiobook and together-room pages inherit shared
PlatformStyle/PageFrame, theme-aware content and native back controls. Content
loads, empty/error/permission states stay explicit. Device-wide music scanning
starts only on a user action. Large text remains scrollable; the feature grid
keeps three columns with taller cells. Performance work reuses full-DPR textures
and static label subtrees, without reducing blur/refraction or replacing motion.
Host screenshots verify composition, not Android GPU optics or 120fps; user-run
frame diagnostics preserve that distinction.
## 2026-10-28 1.0.8 无损性能约束

保留当前材质参数、全分辨率背景采样、色散、模糊、阴影与所有动画时长／曲线／弹簧。只复用相同纹理范围的读取；底栏与胶囊仅在终点、完全不透明、真实绘制及读取范围安全时共享背景。按压缩放、重叠和过渡立即隔离，浅色阴影阻止共享时保留原画面。实际设备性能待用户复测，不能凭主机截图验收120fps。


## 1.0.17 个人音乐库与交互补充（2026-10-29）

用户方向保持：Apple玻璃、完整折射和动画。网易云参考只用于“我的”的资料区、紧凑快捷操作与喜欢／创建／收藏歌单信息顺序，不复制其颜色、统计或账号内容。个人页与设置账号卡分开，列表懒构建，收藏封面有加载、失败与缓存状态。

下载区独立为“已下载／下载任务”，播放全部为主要蓝色玻璃操作；导出与文件夹交给用户主动调用系统文件界面。歌曲切换先呈现新身份及加载反馈，阻止旧音频与旧进度跨到新歌。搜索组合输入与已存在结果保持连续。

全Beta公共滚动采用弹性越界，避免Material拉伸合成层切断玻璃背景取样。选择表单、排序和更多菜单复用公共液态玻璃菜单；二、三级页面共享返回及转场，保留系统返回与左右边缘返回。不可用的逐曲来源保持前景置灰且禁用命中。

本轮渲染核对：浅／深色、390与320宽度、窄屏1.3文字缩放的个人页，以及已下载列表；公共玻璃选择、按住拖动取消、禁用、加载、逐曲来源可用性、三级返回均有主机回归。原生GPU帧率、真机系统文件夹行为和真实账号内容需设备验收，不能以主机截图替代。


## 1.0.47 长列表与足迹收尾记录（2026-11-03）

在现有 Apple Music 参考、明暗语义色、胶囊和完整玻璃下做性能与结构修正。集合 30 条一批，公共足迹头部只参与竖向收起；横向移动仅作用于报告。保持原图文缓存、失败旧内容、完整收藏及显式播放/下载全部语义。

两轮有界主机检查已完成：首轮新夹具缺少图标字体，第二轮加载测试字体后 26 帧全部核对，包含明暗搜索、3000 收藏首批/末尾搜索、新歌首批、下载任务及横滑中头部固定。最终判定为本地主机检查通过；不表示 Android IME/GPU/帧率或真实账号验收。未更改产品字体、原材质或动画来换取性能。


## 1.0.50 approved refinement (2026-11-04)

Preserve the existing premium glass, colors, type, motion forms and native audio owner. Ordinary page pairs enter toward the left and reverse toward the right, including the retained parent; the tab viewport remains the only root-tab primary animation. Bookmark controls use one compact cover/text/close capsule (238dp maximum width, 52dp base height, 34dp real cover, at least 44dp close target) instead of a full-width hint plus detached close. Song-row actions use vertical three dots, opening the shared rounded glass bottom-sheet with real track identity, source/context-aware operations and verified people/album information. Screenshot references guide the NetEase hierarchy; local older Kugou static evidence does not establish the newer capsule exact dimensions. Host software captures do not certify physical Android composition.
