**2026-11-04 1.0.52：1.0.52本地新增酷狗真实听歌统计/乐龄/等级三榜/徽章管理和多账号。Lite音乐登录与同UID标准授权分开保存；正常新听歌回执、等级读回和官方日读回分别显示，真实账号及跨日入账待验收。**

# Product

<!-- impeccable:product-schema 1 -->

## 1.0.7 approved extension (2026-10-28)

The approved navigation is 发现 / 功能 / 音乐库 / 我的. The former home keeps its
content under 发现; 功能 is a fixed three-column launchpad of working existing
and newly integrated features. New local music, recognition, audiobooks and
Kugou together rooms inherit the current Apple/Cupertino visual language and
reuse the single playback engine. The device-local music index is independent
of cloud favorites. Official music-history synchronization is account-scoped;
old aggregate duration remains local, new duration uses actual listening time,
and official acceptance is separate from confirmed read-back. See the 1.0.7
fix and handoff documents for verification and publishing status. No device
access is implied by this contract.

## Platform

adaptive

## Users

中文音乐用户，在通勤、工作学习、放松和入睡等片段时间里寻找合适的音乐。

## Product Purpose

Mesting 是一款 Flutter 音乐应用，帮助用户快速发现、播放和管理适合当下状态的音乐。成功标准是用户首次打开后能迅速理解当前推荐，并在较少操作内开始播放。

## Positioning

以封面主导、中文内容和连续播放组织发现与音乐库。Android Beta.13 延续固定版本 md3Music 平台来源、顺序和反馈契约，沿用用户确认的 Mesting/Apple Music 视觉依据、原创音乐伙伴、统一账号入口、真实分类搜索、八页使用指南、独立启动页和真实队列时长；本轮修正账号恢复、进入与返回顺序、播放胶囊菜单及文本编辑交互。正式渠道保留既有“当下状态驱动”的定制推荐。

## Operating Context

主要使用场景是移动端单手操作、碎片化使用和持续播放；首页、发现、音乐库、我的组成四个主要目的地，搜索独立。手机与宽屏共享 Beta 底栏，正文自适应约束宽度。

## Capabilities and Constraints

- Beta.19 adds two original user-supplied static startup images, alongside both existing videos and the classic screen. One upgrade migration selects image one; subsequent user choices persist. The full image is fitted without cropping. Beta.20 holds each static startup image for about 500ms after its first decoded painted frame; optics/audio still initialize concurrently before business pages mount. Formal startup behavior remains.
- Beta.19 preserves all premium glass optics and capsule motion while reusing unchanged geometry and updating shader coordinates when an Android overscroll ImageFilter pass changes. Seven independent saved Shinchan weather choices are available beneath progress characters; offscreen and reduced-motion previews stop. Formal-only assets leave the Beta bundle and are checked in the actual APK.

- 现有项目使用 Flutter。Android Beta 由 DistributionChannel.isBeta（appFlavor == beta）接入，包名 com.mesting.music.beta；正式 flavor 的页面、主题、定制推荐、导航和默认黑胶保持其原有契约。共享工具的改进按调用点生效，不构成全局渠道切换。
- 装扮 → 启动页延续 Beta.12 的用户给定短片“音乐伙伴”“唱片派对”及珊瑚红/白色 M 经典页；Beta.19 首次升级默认静态图一，之后保留用户选择。选择写入成功才更新勾选，静态海报与独立预览操作分开，浏览/选择不自动播放。Beta.13 的选择行有局部圆角按压反馈，预览以 48dp 圆形独立 premium 玻璃按钮关闭。偏好与图标别名、主题、自定义背景视频、播放器样式及加密账号存储独立。短片主体按原比例完整显示，空余区域用同一个视频控制器的实时模糊纹理延展，状态栏与导航栏请求透明；这不证明设备上的系统栏或解码器表现。短片保留原声，每个冷进程只播放一次；依赖就绪且视频结束后才挂载业务应用与账号/播放恢复。后台暂停、回前台接续未完成片段，已完成不重播；有界初始化/停滞失败回退经典页，重试依赖不会重播短片。预览单独持有并释放控制器，不改变冷启动门控。
- Beta.13 的 retainedSecureStorage 为 Mesting 与酷狗两个账号存储关闭 Android flutter_secure_storage 的 resetOnError；安装的 10.3.1 插件原本会在存储异常时调用 deleteAll。保留现有 namespace/cipher，避免原生读取异常触发插件级清库。SecurePlatformSessionStore 对暂态平台异常和空读最多读取三次（间隔 100/200ms），格式错误直接暴露且不删除该凭证；写入经原值回读后才发布登录成功。platformAccountProvider 关闭 Riverpod 自动 build 重试，使永久恢复错误能够结束为可见错误，用户可“重试恢复”或“重新登录”；后者保留旧加密内容，直到真实平台认证结果经串行 accept 保存并回读成功后替换。Mesting SessionStore 原有 JSON 无效时清理自身键的规则不在这项修正中改写。此处确认的是源码与软件回归边界，尚未由设备日志证明此前冷启动丢失登录态的具体触发原因。
- 首次未完成进入且无恢复会话时显示欢迎页；Beta.13 为位于 Router 上方的欢迎 Navigator 注入 ChildBackButtonDispatcher 并取得优先级，登录/法规页面返回实际所属 Navigator，正文与不透明 surface 成对进退。Beta.18 确认每次新的交互式登录成功时，同帧显示并开放同一棵八页指南；登录成功 HUD 为 104×104dp 圆角方形，位于 SafeArea 内顶部 76dp、指南页头下方的上部中央，900ms 绘制标记、1800ms 后反向退出，仅自身绘制并忽略指针。反馈期间 Next/Skip/Back 继续操作同一个指南状态，延迟结束回调不能重置进度或完成后重开指南。原创 0.48 秒提示音仅随该交互成功事件调用一次，Android SoundPool 使用媒体音量、遵循静音/振动且不请求音乐焦点，不新建播放队列或音频服务 owner。恢复凭证、刷新 token 与重复扫码回调不触发成功流程。游客直接进入应用；指南“跳过”仅将当前页与第八页做局部淡变/微移，不经过中间页，仍需明确“开始使用”，设置可重看。退出仅真实成功后由上层协调器先覆盖欢迎页，再归位旧路由栈，返回不能重新进入退出前页面；等待时禁用重复操作，失败保留会话并允许重试。两类账号控制器和数据归属继续独立。
- 欢迎页优先手机号和微信扫码，其他方式提供酷狗/QQ 扫码；Beta.19 移除 Mesting 账号登录/注册入口，旧密码恢复路径转回平台账号入口；已有会话与数据保留，正式版功能保留。手机号页只承载手机号验证码，所选扫码通过 initialMethod 进入独立方式页；我的与设置使用同一个 BetaAccountCard，游客及受保护操作通过 openBetaLogin 进入欢迎页。协议小圆形状态与文字/链接整组居中、同基线，链接可独立访问，小屏和大字允许换行。
- 手机号表单沿用 Beta.11 经确认的 Raycast 简洁布局和窄屏大字六位验证码布局；_InlineCodeField 仅负责测量，框内右侧操作与字段为独立兄弟 premium 层，TextScaler 与业务状态仍由原框架/页面持有。Beta.13 常驻 +86 前缀，手机号方式显示手机图标；验证码按钮只在发码请求时显示 spinner，蓝色玻璃登录按钮只在登录请求时显示 spinner，共享 busy 仍禁止重复请求。发码平台成功后才显示“验证码已发送”成功 HUD 并进入 60 秒倒计时，失败如实保留原因。历史 Beta.11 的 responsive-code-tests.log 2/2、approved 原图与 R1 resolved 仅属于该版冻结实现。发送先注册设备，单次操作仅发送一次；原生 captcha_options 保留 KUGOU_API_MID/dfid 签名上下文、删除账号凭证，平台 status=1 才倒计时，20015 仍是业务拒绝；这些客户端/原生行为不证明真实短信送达。
- 用户确认所有登录类页面移除“开源许可与致谢”；共享 showLicensePage 入口位于 Beta 设置的应用分组（settings-open-source），协议/隐私同意入口继续按其真实用途呈现。原先源码没有独立设置许可入口，本轮将其移入设置；settings-capture-final.log 1 通过，fixture 改为真实 /music/settings，正确截图为 settings-final.png。
- 八页指南根据实际发现/搜索、歌词、灰条收起与底部操作、账号适用的推荐/收藏、手动队列优先与续播/历史、外观、五种播放器、开始使用组织；不承诺桌面歌词、Zen 或 AI 等未实现能力。五张动态预览共用真实 playerVisualStyleProvider，选择会保存到装扮/播放器相同偏好；外观模式也读取真实主题偏好。演示不发起播放、云写入或第二个音频 owner。
- Beta.11 游客可浏览公开内容、五类搜索、进入真实公开详情并播放平台提供的可播放资源；当前播放队列与临时待播继续开放。收藏/取消收藏、创建/修改个人歌单等账号写入在组件和仓库边界拦截并引导统一登录；不删除或迁移已有本机游客数据，也不把播放历史和当前队列误当成个人写入。
- Beta.10 在现有严格编码 hash 切换上，增加同 ID 的媒体修订通知，使当前曲音质/元数据跟随真实媒体发布而更新，且不订阅位置 tick。有损返回的正值实测码率优先于可能由适配器补入的请求档位标签；严格切换不符或无法确认时保留旧音源和偏好。当前软件证据不等于真实 CDN/会员权限验收。
- Beta.11 的 BetaPageMotion 将页面正文与主题不透明 surface 共同横向移动，进入和返回连续显露真实上级页面；不存在留到卸载终帧的静止整屏遮罩，源页保留挂载与滚动。播放器封面/歌词、曲目身份和样式继续成对入退；上一首/下一首读取真实播放命令方向。共享 transport 与音频 owner 持续存在，快速反复操作由局部过渡接续。
- Beta.5 新增音乐库路由、年/月 Replay 和歌单封面编辑。回顾只统计当前 owner 的真实每日记录，不反推未记录月份；云写入失败保留草稿，不显示虚假成功。
- Beta.6 封面规范化/只读回退与音质偏好契约继续。Beta.9 音质菜单依据当前歌曲真实资源只展示已有档位，不预填标准/高品质/无损/Hi-Res 四档。资源存在与会员权限分开判断，会员提示只在尝试选择后按平台结果出现，未知元数据手动重试。切换保留档位到编码 hash 的对应关系，严格请求所选实际音源，无损降到高品质/标准也使用目标档位的 hash；勾选、提示和播放器实际来源一致后才保存偏好。复用已有音频服务并保留进度、播放状态、队列与模式；失败保留旧流和旧偏好，偏好/实际返回/试听/降档分别如实表达。
- Beta.7 的发现呈现私人 FM、每日推荐、刷歌推荐与新歌速递，来源固定为 md3Music a69503b84e8829f888684f67c163be03c589c014 的 API/解析/刷新/续播契约；不再应用本地艺人评分和个人热榜。FM 提供红心/探索/小众/电台，保留 cur_mark、播放完成、喜欢/取消喜欢和不喜欢反馈及账号隔离。
- Beta.9 单点只播放所选一首，不隐式导入整页歌曲；只有明确“播放全部”才导入集合。已有手动待播时按实际情况提供保留/替换选择，手动队列优先于自动推荐。普通播放在手动队列耗尽后可由完成或“下一首”进入平台自动续播；当前队列区分自动项。上一首使用实际播放历史，没有历史则重播当前，不从未播放的页面曲目伪造历史。
- Beta.12 手动与自动队列行显示对应录音可信的正值总时长，未知/非正值显示 --:--，试听解码片段长度不冒充整曲时长。统一解析平台时长别名和秒/毫秒，零值不能覆盖已有正值；可见缺失行通过只读 /audio 元数据独立补齐，合并同身份请求、最多两并发、有界缓存/超时，账号和录音/hash 校验拒绝迟到或错配响应。失败保留可用列表与未知值，不为获取时长触发播放或换歌，不改队列顺序、归属、进度与播放状态。
- 只有明确从 FM/刷歌推荐开始才拥有该来源的反馈归属；普通自动续播不冒充 FM。剩余待播项 ≤3 时按服务器顺序预取并追加到真实可见队列，不混入本地音乐库或随机备选池。明确搜索/歌单/音乐库播放结束旧 FM 来源，即使碰巧同一录音；代次和账号校验拒绝过时响应，慢速“下一首”不能在后续暂停/停止/跳转进度后重新启动播放。
- Beta 搜索首页与独立搜索入口使用真实 /search/hot 分榜关键词、历史和主题歌单/场景/热门歌单/排行/新碟等探索分类；关键词只触发搜索，不能伪装成可播放歌曲。旧定制推荐路由在 Beta 转入发现，正式渠道仍使用原实现。场景与主题的当前展示/可点击能力以平台已接入数据为准，不能仅凭端点存在承诺完整功能。
- Beta.11 结果顶部以“歌曲/专辑/歌手/歌单/歌词”固定顺序取代“搜索结果”大标题。歌曲延续紧凑惰性列表，专辑/歌单为手机双列方封面，歌手为圆头像列表，歌词展示真实歌曲与接口实际返回的片段。歌词内容使用 /search?type=lyric，/search/lyric 属于下载候选而非内容搜索。裸数组歌手返回被实际解析，缺失头像按可见身份惰性补取，最多 3 并发、160 个成功缓存；歌单 gid 保留为 global_collection_id，详情沿真实专辑/歌手/公开歌单接口加载。
- 五类按需加载并分别保留页码、数据、错误/重试与滚动位置，不同时预取所有分类；查询或账号变化使旧代次失效。底部目的地导航结束搜索，清空输入、结果、类别及本次 PageStorageBucket，下次相同词也从顶部和歌曲类别开始，真实搜索历史保留；播放器/详情等临时页面仅暂存，返回恢复原词、类别与位置。结果组件本地 bucket 随搜索首页替换结果而销毁；类别切换和临时路由仍在同次会话中。
- cover、classic、aurora、cassette、lyricStage 五种样式保留各自上半区形象和动态，共用同一播放进度、裸白色 transport、Android 系统媒体音量及评论/音质/当前队列。封面与歌词模式都保留这些控件；播放器不建立另一套队列或音频服务。
- 系统音量通过 Android STREAM_MUSIC 原生桥读写/事件同步，无宿主禁用。Beta.8 提供 48dp 高响应区和即时拖动反馈，原生写入串行保留最新值，抑制重复状态、事件和相同步进。进度与音量各自提供中文名称、时长/百分比和可调节语义；硬件键和 TalkBack 仍待真机。
- Beta 装扮移除品牌选择器、重复皮肤说明/经典卡片、DRESS UP 和 followTheme 选项，图标继续固定 coral；启动页在 Beta.19 独立选择两张给定静态图、两段给定短片或经典页，首次升级默认静态图一一次。保留浅/深/系统、自定义图片/视频、显式 IP 进度配色/角色。Beta.8 再移除 IP 装饰开关，替代 Beta.6/Beta.7 的开关保留说明。Beta.7 残留 followTheme 转 classic，已转换显式 IP 保留；背景强度 .58、性能 automatic、完整 IP 主题退役继续适用，这些背景偏好不降低指定玻璃的 premium/full 光学质量。
- 轻量反馈使用一个可替换的顶部安全区半透明 HUD。普通提示仅保留短标题和图标，错误/警告保留可行动信息；通知不可覆盖真实业务结果。
- 不把 Material 3 默认色阶、默认按钮外观或默认卡片外观作为最终品牌表达。
- Beta.9 建立的单一惰性 Apple 歌曲结果列表继续用于当前歌曲类别，歌曲计数只显示“共 N 首”；歌曲列表按滚动指标自动分页，失败才显示重试，保留服务端顺序、收藏与更多。紧凑热搜保留分榜/排名/换页。Beta.12 的内嵌搜索以真实嵌套 LocalHistoryEntry 向所属 Navigator 暴露“搜索结果→搜索首页→来源页”，与左右 32dp BetaEdgeBack、PopScope、BackButtonListener 共同遵循先清查询再关闭搜索的顺序。临时详情返回仍恢复原词/类别/位置，目的地切换结束会话。MusicShell 持有来源 tab 与滚动位置，BetaMusicShell 在播放器/设置后方保持挂载；真实 Android 系统边缘/预测返回仍待设备验证。
- 五样式完整播放器仅顶部灰色 handle 下拉收起，封面/歌词状态共用提交与回弹。Beta.12 的 PlayerDismissMotion 直接驱动当前播放器路由的动画控制器；完成手势从当前进度退出剩余距离，取消连续回弹，只退出当前一层，避免局部退场后重新播放路由退出。迟到回调/快速重复与系统返回由路由归属及提交标记防护；封面、歌词与滑块不竞争灰条手势。持续挂载的胶囊随同一进度显露，音乐由原 owner 持续播放。胶囊仅订阅播放布尔值并使用共享实时播放/暂停操作，88/24dp 收拢滞回保留。
- Beta.11 建立局部 ValueNotifier 与同帧滚动通知合并，历史同 120 帧刺激的 shell 重建由 120 降至 0、底栏仍 120；Beta.12 同样刺激仍为 shell/胶囊/首页 0、底栏 120，未取得新的帧率改善证据。持续挂载、88/24dp 滞回和完整收展动画继续。指定玻璃固定 premium/full，应用级 adaptiveQuality=false；浅色共享材质与关闭底部滚动白罩保留内容通透度。本地 MIT 依赖覆写可复现地去除 fallback shader 深色恒定周圈和最小边缘项，保留方向性高光、折射、色散、弯月面及按压动态；各 GPU 渲染分支仍须真机验证。
- 收藏统一裸心形、48×48dp 透明目标、局部主题对比与按压缩放；成功状态以局部 420ms 动画表达喜欢/取消喜欢，可中断并尊重减少动画。Replay 年份使用 Cupertino 透明度反馈与圆角菜单，不产生矩形按压底；首页实心图标。经典唱机使用无黑描边的几何白色唱臂、唱头落在外圈沟槽，保留播放/暂停旋转区别；更多菜单带图标、分组、分隔线与当前样式对勾。
- 详情标题使用 21dp 单行文字，仅实际溢出时裁切跑马灯；测量与渲染共用继承字体和 TextScaler。Beta.13 的共享 EditorialHeader 与平台页头都在返回圆钮和标题之间保留 16dp。
- 评论排序/范围各为一个下拉菜单并排一行；浮动输入和蓝色 48dp 3D 发送按钮是独立的真实 Liquid Glass 兄弟表面，使用 liquid_glass_widgets premium 渲染，不能嵌套或以位图替代。KeyboardVisibilityBuilder 观察当前原生 View 的键盘指标：键盘显示最多 2 行，否则最多 4 行。评论优先录音专属 ID，有界旧 ID 修复/设备注册恢复只针对读取；发送/回复/删除均需明确操作且不自动重试。特色歌单解析 special_list/plist，排行解析 songlist；平台账号页使用实际 coral Mesting 应用图标。
- Beta.12 的评论发送与新建/编辑歌单确认共用 betaBlueActionGlass 的 clear body 蓝色材质，保留白色 glyph、独立 premium 层、折射/高光与按压反馈，避免浅色滚动背景的亮度归一化将正常蓝色漂白。歌单关闭为共享 BetaGlassAction 的中性玻璃 X，随浅深色调整图标对比；确认/保存为蓝色白对勾。业务页面保留名称校验、保存中禁用返回/重复操作、加载进度及失败草稿/封面，材质组件不持有保存与导航业务。
- Beta.13 的播放器进入阶段将 chrome reveal 保持为零，避免底栏在进入动画中闪现；灰条拖动、取消回弹和反向退出仍按同一路由进度显露已挂载胶囊。进度小新宽 56dp，Kitty/库洛米为透明背景的 28×28dp 头部，绘制中心严格跟随实际 Slider 轨道进度；控件上方预留真实布局空间，避免仅缩小图像后仍覆盖歌手/时间。
- Beta.13 首页首次可用时显示按时段及真实昵称生成的问候，五秒后收起；非 autoDispose 的进程标记避免后台切回、路由卸载/重挂再次播放。
- 评论真实发送成功显示“已发送”，共享圆环/对勾绘制 900ms；Beta 成功 HUD 在 2600ms 后反向退出，普通 HUD 仍为 1900ms。验证码发送成功复用同一反馈；通知及其图标不替代服务器的业务结果。
- Beta.13 将共享文本编辑菜单接入已存在的账号、搜索、评论、歌单、个人资料、社交/聊天等字段，以及 vendored 搜索配置。横条通过 > 展开，只提供可用的粘贴、选择、全选、带 hints 的系统自动填充；展开后非数字字段可插入 #，多行非数字字段可换行。密码/只读/数字字段按其条件隐藏相关动作；可用性继续读取 EditableText。菜单、扩展框与播放菜单复用 betaMusicPillGlass 的 premium 独立层。浅/深蓝色细光标、22% 蓝选区与 Cupertino 细杆圆点手柄共用编辑色，输入格式化、最大长度、IME/自动填充仍由框架和原字段持有，不能把主机测试当作真实 Android IME 验收。
- 长按已有播放胶囊打开锚定菜单，源胶囊保留原位置；局部菜单向上展开、反向向下收回，受安全区/键盘和可用空间约束。只列既有喜欢、添加歌单、队列、歌词、平台评论/音质及可用播放模式；“不喜欢这首”仅实际 FM 归属时提供。选择返回 intent，等待弹层 route.completed 后再调用现有业务，切歌后拒绝旧菜单动作，不增加另一套音频或账号状态。

## Brand Commitments

- 产品品牌：Mesting；Beta 可见应用名称统一为 Mesting Music；界面语言：简体中文。
- 需要降低常见 AI 生成界面的模板感，避免紫粉渐变、泛滥玻璃拟态、重复大圆角卡片和无意义装饰。
- Beta 以用户提供的 Apple Music 参考图为视觉依据：封面、大标题、横向内容组和悬浮控件；界面保留中文 Mesting 品牌与自身账号、播放能力。
- Beta 使用参考图采样红色统一导航选中态、个人页图标和相关选择；Beta.9 经典浅色面板改为中性白灰（#F2F2F7），保留红色强调、既有深色与封面播放器氛围。显式 IP 图案与角色继续拥有自身配色，选中标签保持主要文字对比。
- Beta 底部直接使用 liquid_glass_widgets 1.15.0 官方 Apple Music 示例的组件、布局与交互动态，本地 MIT 源码覆写及变更说明随项目保留，不依赖本机 Pub 缓存补丁。Beta.10 经确认扩展至指定账号操作/字段/圆形返回的 premium 材质继续使用；许可入口从 Beta.11 起位于设置。当前指定表面独立拥有层，评论输入/蓝色发送仍为兄弟表面，新建/编辑歌单复用中性关闭与蓝色确认，Beta.13 蓝色登录复用同一局部确认材质；编辑条、扩展框及播放菜单复用胶囊光学参数。内容列表、阅读正文和页面背景保持稳定。Beta 调用点不构成正式渠道全局改版，局部音质弹层/HUD 保持自身规范。
- Beta.10 的欢迎与指南采用用户选定的珊瑚红原创音符/唱片矢量双角色，具有四肢、表情、轻摆、眨眼和轻点问候；沿用既有 Mesting 世界、所给参考构图及随后确认的完整文字方案。没有另外生成或批准的 ImageGen comp、approval sidecar 或随机 FORM seed，不能事后补造来源记录。
- 默认封面播放器可切换左对齐同步歌词；歌词当前基准为 24dp 并支持 TextScaler。迷你 accessory 仅保留播放/暂停和下一首两个裸图标，点击/左右滑动与官方玻璃交互继续适用。
- 酷狗、Mesting、游客各自拥有收藏和历史；Mesting 社交入口不会显示给酷狗账号。云端写入失败不伪装成本地成功，不能把平台来源当成会员授权。

## Evidence on Hand

- Beta.13 是用户于 2026-10-26 明确确认的十五项方案在既有视觉世界内的修正；具体表面行为见 .impeccable/surfaces/beta13-interactions.md。没有新增 ImageGen 批准 comp、approval sidecar、QUALITY BAR card 或 FORM seed。
- work/beta13/review-final.md 的有界独立结论为 disposition: ship，R1–R4 resolved、remaining clear。review-fixes-functional-final.log 记录 23 项通过（9 session、14 entry），包括永久恢复错误后的新认证结果替换、零 delete、同一指南状态/语义屏蔽与一次声音调用；此前 12 项软件 UI 证据和未变的九张进度角色、两张成功反馈复核捕获继续适用。它们是合成软件环境中的断言与捕获；声音调用次数不证明可听响度或设备混音，存储修正不证明此前设备丢失登录态的根因。
- Beta.13 最终常规回归 657 通过/78 条件跳过/0 失败，Beta 196 通过/0 失败，当前软件 UI 53 通过；analyze 为 No issues found，各组重叠不相加。assembleBetaRelease 成功，work/beta13/release-verification/artifact-verification.json 核验 Mesting Music / com.mesting.music.beta / 1.0.37-beta.13 / 13，APK 为 90,180,180 bytes，SHA256 A5C6018FF7354552D8CECF37E01B4028DE93DAEBA1DEB61EE77840E2AAF6EBB6。同一 Beta 证书、16KiB ZIP 与五个 ARM64 原生库 LOAD 对齐、原生库对应链/FFI、兼容视频和修正 shader 已检查；原创提示音经资源优化位于 res/L_.wav，与源音频字节 hash 一致。发布包内容与软件检查不认证真机声音、GPU、输入法、系统返回或线上服务。源码 ZIP 身份由文档冻结后的外部交付清单记录，避免自引用。

以下 Beta.12 的测试、发布及媒体核验均为历史证据，只适用于该版冻结构建，不构成 Beta.13 的完整回归、包身份或真机验收。外部 work/beta12/implementation-status.md 保存该版明确确认，“待确认”只是历史方案文件名。

- Beta.12 的 work/beta12/ui-final.log 为 47 项重叠软件 UI 检查通过，captures-final/existing 使用实际生产控件、合成 fixture 与 Windows QA 中文字体，覆盖启动选择、小屏/大字、浅深玻璃纯色/内容背景、收拢/展开/形变、宽屏、新建/编辑及路由拖动。蓝色滚动前/变化中/稳定后采样：浅色三帧均 [13,107,218]，深色依次 [1,95,206] / [13,107,218] / [1,95,206]；该结果只证明主机软件渲染中的正常蓝色未漂白，不认证原生玻璃保真。
- Beta.12 targeted-navigation.log 两项生产路由回归通过；targeted-startup-cleanup.log 三项启动偏好/生命周期/超时检查通过。live-duration-probe.json 的主机嵌入服务真实只读 search 与三次 /audio 均 status=1，搜索 261/257/279 秒与同 hash 元数据 261276/257252/279196 毫秒对应；不据此宣称短信、账号或 CDN 播放可用。
- Beta.12 test-summary.json 记录最终常规 651 通过/63 条件跳过/0 失败、Beta 175 通过/0 跳过/0 失败、软件 UI 47 通过/0 跳过/0 失败；analyze-approved.log 为 No issues found。常规首轮一项脆弱静态源码位置断言失败属于早期阶段，修正后完整重跑已通过。media-verification.json 记录用户原文件未改，兼容副本为 H.264 Main / yuv420p / 608×1280 / 30fps，原 AAC ADTS 流 hash 一致；两段转码 PSNR 均值为 49.825196 / 51.435274 dB。各回归/截图组有重叠，不相加；转码与测试通过不证明实际设备解码/声音。adb 设备为空，原生 GPU/折射/FPS、真实系统边缘返回、媒体焦点/音量、解码器生命周期与 TalkBack 仍未认证。
- Beta.12 assembleBetaRelease 与最终检查成功，release-verification/artifact-verification.json 已核验 Mesting Music / com.mesting.music.beta / 1.0.37-beta.12 / 12；APK 为 90,136,848 bytes，SHA256 AC098F96C92839CD3B8830D1662826C8427EA09852BA34F5DE0B2AF8084CD74E。同一 Beta 证书、16KiB ZIP 与 ARM64 LOAD 对齐、两种 ARM 服务库的源码→merged→stripped→APK 对应链及与 Beta.11 一致性已验证；打包的修正 shader 与 Beta.11 不同，两段 APK 视频与仓库兼容副本逐字节一致。源码 ZIP 精确字节/哈希留文档冻结后的外部交付清单，不将尚未生成的归档身份写成完成。

以下 Beta.11 与更早版本的发布、测试与评审结果同样为历史证据，只适用于对应冻结构建，不构成 Beta.13 发布或真机验收。

- 历史 Beta.11 已验证发布 APK 为 Mesting Music / com.mesting.music.beta / 1.0.37-beta.11 / 11；assembleBetaRelease 成功。test-summary.json 记录该版最终常规 644 通过/58 条件跳过/0 失败、Beta 163 通过/0 跳过/0 失败，ui-captures-approved.log 43 通过；后补设置捕获 1 通过，analyze-approved.log 为 No issues found。组间重叠不可相加。APK 为 89,244,110 bytes，SHA256 64B761F855B4E44F26979375C04CAE266D608A18DB954D500494B4334D3DC4F3，同一 Beta 测试证书、16KiB ZIP 对齐、ARM64 ELF 16KiB 和打包 ARM 原生对应链已验证。精确记录在 docs/MD3MUSIC_BETA.md；源码 ZIP 字节/哈希留该版冻结后的外部 manifest。
- Beta.11 首轮 review-first 为 fix，后续 R1 曾 partial；经用户确认继续修复、responsive-code-tests.log 2/2 和 approved 原图复核，reviewer 已确认 R1、R2 均 resolved。R2 的 search-session-regression.log 1 通过，生产路由验证同词新会话 offset=0、同次类别/详情往返保留 offset=50。新 review-final.md 的独立有界结论为 disposition: ship，R1/R2 resolved、许可迁移 match，无剩余 material fix；结论仅覆盖所记录的软件/发布证据范围。
- Beta.11 review-fix-tests.log 3/3 的早期通过仍保留：内联验证码 pending→真实业务 status=1→60s 倒计时与重复点击防护、生产 appRouter 搜索生命周期、相同 120 次 playing-scroll shell=0/bar=120。初轮 642/56、Beta159、UI39、后续 UI42 和分析 1 info 均属早期源码/捕获阶段，已被最终 644/58、Beta163、approved43 与 clean analyze 取代；不以早期结果替代当前验证，也不将软件证据当作实际短信或真机帧率验收。
- Beta.11 genuine host live-read-probe 八类公开搜索/详情响应均 status=1，匹配裸数组歌手、歌词、专辑、gid 歌单及详情解析；这些是主机嵌入服务只读响应，UI 截图仍使用合成 fixture。Native 单元 46 通过；三个 ABI 服务库已用 Rust 1.99.1、NDK 28.2 和锁定 Cargo 依赖从修复源码重建。release 验证将源码原始库 manifest→merged 原始 hash→stripped→APK 两种 ARM 库完整对应，四个 C FFI 导出有效，且与 Beta.10 不同；x86_64 仅额外重建输出，原始未剥离 hash 不与 APK 剥离后 hash 直接混比。adb-devices 为空；真实 SMS、账号/QR/云写入、CDN/权限及设备验收仍未完成。
- Beta.11 新入口与边界：BetaConsentRow、BetaAccountCard、openBetaLogin、PlatformAccountPage.initialMethod、account_capabilities、LibraryRepository 写入防护；五类由 PlatformCategorySearchRepository、CategorySearchController、BetaCategorySearchResults、PlatformCatalogDetailPage 与 artistPortraitProvider 分工。原生修改在 third_party/md3music/rust/src/modules/misc.rs，复现入口为 tool/build_md3_beta_native.ps1；NOTICE 已说明来源与局部修改。
- Beta.11 motion-export.log 4/4 通过；外部 fixture 复用当前 Beta.11 实际组件，由 export-motion.py 导出欢迎/样式浅深四个 GIF，各 36 帧、每帧 80ms，未修改生产源码，也未使用旧 Beta.10 图冒充当前。它们是软件动态演示，与其他组重叠，不是设备 GPU/FPS 证明。
- 历史 Beta.10 已构建并验证 Mesting Music / com.mesting.music.beta / 1.0.37-beta.10 / 10，pubspec 保留正式基线；review-final.md 的有界独立判定为 ship，R1–R8 全部 resolved。普通回归 635 通过/54 条件跳过/0 失败，Beta 定向 150 通过/0 跳过/0 失败，最终软件 UI 34 通过/0 失败；组间重叠不可相加。analyze 无问题，同一 Beta 测试证书、16KiB ZIP 对齐、两种 ARM 服务库与 Beta.9 字节一致已验证。APK 为 89,227,526 bytes，SHA256 及精确证据见 docs/MD3MUSIC_BETA.md。首轮 27/7 与修复组 16 属于早期有界证据；首轮截图缺陷由最终捕获/复核闭合。源码归档精确字节/哈希由冻结后生成的外部 outputs/beta-1.0.37-beta.10/delivery-manifest.json 记录，避免自引用；这些结论仅属于 Beta.10。
- motion-export.log 另有 4 通过，复用相同软件 fixture 导出浅/深欢迎与样式预览，每个 GIF 36 帧、每帧 80ms；这是软件动态演示，不是 Android FPS 或原生 GPU 流畅度证据。设备清单为空，设备/线上边界继续保留。
- Beta.10 入口证据：beta_entry_flow.dart、BetaEntryCoordinator、BetaWelcomePage、BetaOnboardingPage、MestingMusicCompanions、BetaPlayerStylePreviews、BetaSignOutDialog；共享 BetaGlassButton/Field/BackButton、BetaAnchoredMenu、BetaSuccessMark/ActivityIndicator 和 PlayerCommentGlyph。评论菜单打开时实测各自触发器宽度；成功标记/等待状态由真实操作结果驱动。
- 延续结构边界：保持挂载的 MusicShell / BetaMusicShell、32dp BetaEdgeBack 与系统 BackButtonListener、beta_playback_actions、AutomaticSongPaging、OverflowMarquee、PlatformCommentComposer / KeyboardVisibilityBuilder。音质由 PlatformQualityCatalog/provider/resolver 管理；播放仍由 MestingAudioHandler 唯一持有。具体源码入口见 docs/MD3MUSIC_BETA.md。

- Beta 布局：`lib/features/experience/presentation/music_landing_page.dart`、`beta_music_shell.dart`、`beta_bottom_bar.dart`、`floating_playback_pill.dart`。
- 播放与歌词：`lib/features/experience/presentation/beta_now_playing_page.dart`、`apple_player_controls.dart`、`immersive_lyrics.dart`；复用 `lib/core/audio/mesting_audio_handler.dart`。
- 音量：`lib/core/audio/media_volume_controller.dart` 与 `android/app/src/main/kotlin/com/mesting/mesting_music/MediaVolumeBridge.kt`。
- 推荐：`lib/features/music_platform/data/platform_recommendations.dart`、`data/platform_explore.dart`、`platform_recommendation_providers.dart` 和对应 `platform_recommendations_page.dart` / `platform_search_landing.dart`。
- 视觉和迁移：`lib/features/themes/beta_appearance.dart`、`app_theme.dart`、`theme_controller.dart`、`app_brand_style.dart`、`theme_gallery_page.dart`；反馈入口为 `lib/shared/widgets/music_notice.dart`。
- 较早正式推荐入口：`lib/features/recommendation/presentation/recommendation_page.dart`；不应作为 Beta.7 平台推荐排序来源。
- 历史 Beta.9（2026-10-25）有界独立复核为 ship，R1–R5 全部闭合。普通回归 619 通过/52 条件跳过/0 失败，Beta 定向组 132 通过/0 跳过/0 失败，软件 UI 23 通过，命令与交互 21 通过；组间重叠不可相加。analyze 无问题。该版发布 APK 已构建并验证 com.mesting.music.beta / Mesting Music / 1.0.37-beta.9 / 9，同一 Beta 测试证书、16KiB ZIP 对齐和 ARM 服务库与 Beta.7 字节一致。该版源 ZIP 字节与哈希由其归档清单记录；这些结果仅适用于 Beta.9。
- work/beta9/pill-benchmark.json 对同一组 100 次播放位置事件的观测为 Beta.8 胶囊重建 99 次、Beta.9 为 0 次；这是 Flutter debug 构建工作量比较，不是帧率或真机流畅度证据。
- 本轮纳入的是源码与主机软件证据，捕获使用合成数据、Flutter 软件渲染和 Windows QA 中文字体；没有纳入 Android 设备验收记录。硬件音量/提示音响度与焦点、TalkBack、预测返回/硬件手势、真实 IME/自动填充、GPU 玻璃/动画/帧率、冷启动/升级迁移及账号恢复根因、线上 CDN/音质/权限与真实账号/评论写入仍待设备或线上验收。历史 Beta.7/Beta.8 计数、结论和包身份仅描述各自构建，保留在 docs/MD3MUSIC_BETA.md。

## Product Principles

- 先让用户播放，再让用户探索。
- 平台推荐来源、顺序和反馈应比装饰更明确。
- 音乐封面是主要视觉资产，界面 chrome 保持克制。
- 颜色、图标、间距和交互状态必须来自可复用语义规则。
- 首次使用者无需学习 Material 组件习惯即可理解页面。
- 软件截图、模拟协议和构建成功只能证明各自范围，不能替代真机或线上服务验收。

## Accessibility & Inclusion

- 触控目标遵循移动端至少 44dp 的可用范围；Beta 收藏统一 48×48dp，音量响应区高 48dp。顶部收起 handle 等紧凑操作按实际尺寸记录，软件测试不等于真机可达性验收。
- 浅色和深色模式都保持正文、次级文字、分隔线和焦点状态的可读对比度。
- 图标不能成为唯一信息来源，重要操作需要清晰文字或语义标签。
- 播放进度与系统媒体音量必须有各自的名称、可理解值和可调节动作；widget 测试通过不等于 TalkBack 设备验收。

### Beta.19 device validation and delivery

- 签到页三个玻璃操作保持白底黑字，滚动回弹仍保留；在离屏合成内补齐真实同色页面底层。蓝色手机登录/触感按钮继续保持蓝底白字。
- 真机性能采用隔离身份的受控首页/胶囊场景；普通 Beta 安装与启动另验。不得把主机软件图、后台被入口覆盖的页面或未完成开合的测量作为设备优化结论。
- 本次早期 Flutter drive 使用默认结束清理，发生了日常 Beta 卸载，原登录态/本机数据保留未通过认证；已向用户说明。后续改为隔离包并强制 keep-app-running，工具校验包名后才运行。当前交付、数字及限制见 docs/fixes-2026-10-27-beta19.md。


## Beta.20 confirmed refinement scope

Keyboard search hit geometry follows the visible IME-raised field. Comments and
reply threads cover the whole navigation shell. Functional actions and selection
use blue, favorites pink and saved sign-ins green, with neutral grouped surfaces
and brightness/contrast adaptation. Cover atmosphere and branded/IP artwork keep
their own palette. Static startup images receive a short full-image presentation
period after decoding and painting. No automatic listening-time synchronization
is enabled: two isolated real-playback tests did not show credited cumulative or
daily time in server readback or the user's official-app comparison.

## Beta.21 current contract (authoritative)

2026-10-27：这是已确认的同一 Mesting / Apple Music 视觉世界内的局部扩展，具体方向见 [.impeccable/surfaces/beta21-refinements.md](.impeccable/surfaces/beta21-refinements.md)。本节是当前 Beta 的权威补充：上文 Beta.10 的音符/唱片矢量双角色及 Beta.13 的小型操作成功绘制标记仅作为对应版本的历史说明保留，不能继续作为当前欢迎页或操作 HUD 的实施规则。没有新增或补造批准 UI comp、QUALITY BAR card 或随机方向 seed。

- **欢迎伙伴**：只使用 `assets/branding/welcome/companions-atlas.png` 这一张双角色四姿态图集。黑胶唱片坐在左侧，高挑奶油色耳机站在右侧，手搭在唱片上；缩放与换姿态维持同一构图。它是由原启动图身份派生的 3D 渲染姿态的二维图像动画，不是新建或绑定骨骼的 3D 模型。小写 `hi` 气泡和三道手指线由代码独立绘制，默认可见，随挥手/轻点问候轻弹；眨眼、点头和轻跳保持轻量节奏。离屏、后台及减少动画时停止动作。原始启动 PNG 字节不变，来源与完整生成提示保留在该目录的 `provenance.json`。
- **共享待播**：队列 sheet 与播放器内面板复用 `BetaPlaybackQueue`，直接呈现既有音频 handler 的权威待播顺序。手动待播优先和自动推荐来源仍由 handler 决定，界面不另建播放状态或重分组后冒充真实顺序。拖动开始保存歌曲身份快照，提交时按实时队列重定位，覆盖拖动中切歌/队列变化；支持右侧手柄排序和左滑移除。随机与循环各自设置，上一首仍使用真实历史。
- **小型操作反馈**：Beta 的成功通知保留结果文字、live-region 语义和原有停留/退出反馈，移除绿色成功图标及其绘制动画。错误/警告仍保留实际原因。独立登录成功 HUD 继续使用自己的既定展示与指南交互契约；移除操作通知图标不删除登录成功反馈，也不制造业务成功。
- **登录滚动玻璃**：手机号/验证码保留原 premium 材质、按压和回弹。`BetaGlassScrollBody` 在滚动 overscroll 合成内部绘制真实页面 surface，使玻璃有正确背板可采样；不以降级光学或关闭滚动回弹替代修复。
- **同意与法律文本**：Beta 不再自动展示重复的首次法规卡片；欢迎页显式协议/隐私链接与主动同意行保留，关闭自动 gate 不写入任何接受状态。协议/隐私按 flavor 选取，说明当前酷狗/资源/验证服务、历史 Mesting 会话与实际本机存储、退出及平台账号注销边界。依用户决定暂不填写联系方式；这次是当前产品事实校准，不构成法律合规审计。自动听歌时长上报仍关闭，已领取的会员奖励不证明本次获得新增权益。
- **八页指南**：使用当前歌曲、专辑、歌手、歌单、歌词五类搜索，真实播放器/歌词/评论与音质边界，系统音量/输出，账号归属的收藏、歌单、签到及会员限制，共享待播、启动/进度角色选择和五种实际播放器样式。指南预览使用现有偏好与局部绘制时钟，样式选择会保存，不创建第二个播放器或伪造云端写入。
- **输出卡片**：“切换设备”在现有玻璃卡片内部展开，不另开一种视觉面板。列表只显示系统确认的当前路由与公开可转移路由，选择要经原生确认和回读后才生效；已配对设备不等于可用输出。需配对/授权、旧系统或不开放的切换保留用户已接受的次级“系统设备管理”入口；“完成”关闭卡片。

本轮已存在的主机证据见 `.codex-artifacts/2026-10-27-beta21/`：`beta-regression.log` 为早期广泛 Beta 回归 266 项通过，`targeted-final.log` 为后续定向 24 项通过，`queue-final.log` 覆盖拖动中队列变化，`paired-final.log` 为后续双角色定向 22 项通过，`screenshots-final.log` 为截图相关 24 项通过，`analyze-final.log` 为 No issues found。各组存在重叠，不相加。`stable-final.log` 为 732 项通过、113 项跳过、2 项既有失败（文本编辑菜单间距、关注者移除 sheet），不能描述为全量全绿。Release 构建、签名与交付身份以另行冻结的最终交付记录为准，不由这些主机结果推导。

`.impeccable/review/beta21` 的 31 张图片来自实际生产 Flutter 控件、合成账号/媒体/设备夹具与 Windows QA 中文字体，只支持主机布局/交互审查；不能认证 Android GPU 光学、IME/自动填充、TalkBack、蓝牙实际转移、系统/预测返回或性能。用户自行真机测试，本轮不访问手机、模拟器或 ADB；原生 Flutter 范围没有运行 HTML/CSS 检测器。

Git 仍为 `beta`，基于 `edc6d1bf881cbe2173709cc84b86b91637fbaaed` / `v1.0.37-beta.19`，Beta.20 与 Beta.21 均为本机未提交修改；本轮不提交、建标签、推送或发布。Beta.20 APK/源码 ZIP、原始启动图与依赖锁继续冻结保留。

## Release 1.0.2 current contract (authoritative)

2026-10-27：本轮正式版本为 **1.0.2 / 23**。原包名、原签名和内部 beta flavor 保持覆盖升级兼容；公开界面与法律说明不再称 Beta。用户授权发布到 music 并验证旧 1.0.1 的更新发现/下载；没有授权操作手机或 Git 发布。实现与证据入口见 [1.0.2 修改](docs/fixes-2026-10-27-v1.0.2.md)。下方 1.0.1 节保留为交付历史，本节覆盖其中本轮涉及的操作。

- 版本信息标签与值相邻；装扮只在设置中提供，指南使用“设置 → 装扮”。
- 输出由既有音乐播放器的真实音轨与同一 ExoPlayer 配置持有；本机和已连接输出在同一玻璃卡片内选择，不自动打开系统选择器。暂停偏好与实际已生效路由区分，真实回读后才显示当前设备。新设备在系统配对，不把已配对等同于已连接。
- 音乐首页保留原视觉，扩充当前账号推荐、新歌、榜单、歌单、新碟、主题与场景；不引入听书、直播或混合广告流。场景先解析真实音乐模块/标签，目录点击进入真实音乐详情。账号/token 变化拒绝旧数据，不新增播放 owner 或伪造统计。
- Dart 锁改为本地 just_audio 0.10.6 路由适配，不再沿用 1.0.1 的旧锁摘要。共享历史 stable/Java 渠道保持各自既有规则。旧发布 APK/ZIP 冻结，不能由本轮测试推导为新的交付包。

## Release 1.0.1 delivered contract (historical)

2026-10-27：用户确认公开版本名为 `1.0.1`、Android build code 为 `22`；内部继续使用 Beta flavor、`com.mesting.music.beta` 包名及原签名身份，以支持已有安装覆盖升级。它延续当前视觉世界，方向见 [.impeccable/surfaces/release-1.0.1.md](.impeccable/surfaces/release-1.0.1.md)。本节覆盖旧版关于暖色欢迎底、小型成功通知仅文字及关闭应用更新的说明；Beta.20/21 和更早记录保留为各版历史，其余当前功能契约继续有效。最终 APK、签名、发布与源码归档身份以独立交付记录为准。

- **欢迎入口**：采用中性近白/近黑背景，手机号为带 Cupertino 手机图标的蓝色主按钮，微信为中性玻璃，游客/其他方式为次级操作。双角色图集、搭肩构图、小写 hi/手指线、舞台与动画代码保持原字节，不重新生成角色或改变动作。显式协议选择及原有账号/游客流程保留。
- **成功与等待**：小型成功 HUD 恢复主题成功绿色的静态圆环/对勾，调用 `BetaSuccessMark(animated: false)`；标记不绘制动画，HUD 容器仍按既有规则进入/退出。独立登录成功 HUD 保持自身契约。评论发送时禁止重复输入、按压与焦点，保留 48dp 蓝色 premium 表面；仅其等待子控件改用 `beta_activity_indicator.dart` 的自绘 Cupertino 风格八刻度，白色、radius 12、一个完全不透明的前导刻度，避免原指示器内部透明度降低可辨性。该绘制周期为 1 秒，TickerMode 关闭或减少动画时停止。共享 `BetaGlassButton` 的 loading 仍按既有实现阻断输入/焦点而保留原光学，不据此替换全应用的 spinner。
- **更新呈现**：设置中手动检查立即打开现有 premium `BetaGlassMenuSurface` 更新抽屉，网络检查随后更新同一个状态；显示检查中、已最新、发现更新、下载/暂停、校验、安装权限、准备安装、系统安装已打开及可恢复错误。主操作使用既有蓝色，缺少发布说明时不编造正文。重新打开抽屉附着原控制器，不建立并行下载/安装 owner。
- **真实下载进度**：采用 4dp 细胶囊轨道和主题蓝色填充，显示实际已收字节/总字节与百分比，数字使用等宽数字特性。首次打开从已保存进度开始，后续填充以 180ms `easeOutCubic` 插值；减少动画时取消插值。100% 只表示下载字节到齐，随后独立校验，不能写成“已安装”；系统安装仍需用户确认。
- **版本与发现**：当前客户端只读 Ring Download 的公开 music health 元数据，使用真实 `android_version_code` 判断新旧；公开标签 `1.0.0` 对应旧 Beta.20 的实际 code `20`，不因标签变化误判升级。完成入口后（含游客）允许 Release 自动检查，回到前台按 15 分钟节流，手动检查绕过自动检查/稍后提醒限制；对同一非强制版本选择稍后后暂缓 12 小时。正式 stable 与 Java 测试通道继续使用各自既有源。
- **下载与安装边界**：复用现有 HTTPS 下载仓库和 Android 安装链，支持主源、仅传输/服务失败时的一次有界备用源尝试、SHA-256 校验、Range/If-Range 与暂停续传；完整性或身份错误不通过切换源绕过。随机安装级下载 UUID 保存在本机，下载会话按 origin 保存，外部重定向不携带平台下载身份。包名、版本和签名检查保留；不加入 SDK、P2P/P8P 或向其他用户分享文件。客户端只使用公开文件元数据，不包含管理凭据。
- **隐私说明**：当前隐私文本披露 Ring Download 的 `download.csnas.asia` / `download1.csnas.asia`、联网所需 IP/请求信息、应用版本及用于下载会话/续传的随机本机安装标识；该标识不读取 IMEI，也不使用音乐账号身份。安装来源权限由系统和用户决定。联系方式仍依此前决定暂缺，自动听歌时长上报仍关闭；本轮没有新增依赖或改动依赖锁。

验证记录位于 `.codex-artifacts/2026-10-27-v1.0.1/`。生产 Flutter 控件捕获使用合成账号/版本/下载夹具和 Windows QA 中文字体，支持浅深色、大字与状态审查，不构成 Android GPU、IME、TalkBack 或安装验收。发布前主/备源各一次最多 1024 字节的 Range 探测均返回 206、签发下载会话并匹配 ZIP 开头，仅证明该有界协议响应，不证明完整 APK 下载或设备安装。本轮文档 pass 不访问手机/ADB，也不执行构建或发布；最终构建、校验与平台发布由各自交付证据确认。

## Release 1.0.3 current contract (authoritative)

2026-10-27：本轮公开构建目标为 **1.0.3 / 24**，Android 构建入口已采用这一默认值；内部 `beta` flavor 与 `com.mesting.music.beta` 包名保留，以延续已有安装的覆盖升级路径。此节记录当前源码已构建的产品行为，覆盖旧版本中本轮涉及的按钮、资料、更新说明与播放工具描述；最终 APK、签名、源码归档和发布状态仍以交付证据为准。视觉方向见 [.impeccable/surfaces/release-1.0.3.md](.impeccable/surfaces/release-1.0.3.md)，沿用用户确认的 Apple/iOS27 Cupertino、premium 玻璃及既有媒体/胶囊系统。

- **禁用与触感**：共享玻璃按钮和图标操作采用可读的浅深色中性禁用态，阻断指针、焦点及 enabled 语义；真实请求等待保留原操作材质。应用触感关闭时，“体验触感”仍可见且不会触发点击或振动预览。
- **此次更新**：设置中的现有更新抽屉增加“查看此次更新”，当前已是最新版也能查看精确的内置 1.0.3 说明。说明按版本匹配，没有正文的未来版本不补造内容；原有单一更新控制器、下载续传、校验及系统安装边界继续有效。
- **六项酷狗资料**：账号卡片/头像入口可进入当前酷狗账号的头像、昵称、性别、生日、个性签名和地区编辑。资料通过 JSON body 向现有平台路由提交，仅提交实际变更字段；账号写入不自动重试，失败保留草稿，账号或凭证变化拒绝旧请求结果。头像先预览、再明确提交，并提示平台审核，不把本机预览当作审核成功。`/profile/edit` 按 flavor 分流，既有 stable 资料路由与账号能力保留。
- **离线地区**：省/市选择使用附许可的离线中文数据，覆盖 31 个内地省级地区；直辖市城市值归一化，历史或目录外值保留并显示，不强制改写。只有明确保存才提交当前选择，不为显示名称发起账号写入。
- **均衡器**：原生均衡器绑定既有音乐 owner 的当前音频会话，不创建第二个播放器；构造移出 UI 线程，使用四秒截止与 generation 守卫处理迟到结果。设备提供实际频率、频段数及增益范围，九个预设沿用上游曲线，支持自定义频段和持久化期望选择。页面区分待播放、连接中、失败与已生效；增益曲线只描绘选择值，不是声学测量。用户确认所有可见滑块直径为 6dp、轨道为 2dp，保留 48dp 响应区和分贝语义，不加滑块阴影或按压 overlay。
- **音效目录**：社区、耳机与明星目录接入既有上游 endpoints，可用的免费条目映射到实际均衡预设；应用后保存对应选择。搜索只筛选已加载项目。应用操作具有对应条目的名称、tooltip、selected/enabled 语义和 tap action，等待/失败不冒充已经生效；没有实现或声称 IRS/VPF 卷积引擎。
- **歌曲 MV**：使用录音身份到 `/kmr/audio/mv`、`/video/detail`、`/video/url` 的真实元数据与视频 URL 契约，只列平台返回的清晰度；音频 hash、录音 ID、视频 ID 与视频 hash 分开处理。页面提供播放、暂停、seek、全屏和清晰度切换，释放被替换的控制器。进入时暂停唯一音乐 owner；仅进入前正在播放且此后没有更新的音乐/定时命令时，退出才恢复原音乐意图。
- **定时关闭**：支持预置/自定义倒计时或播完当前歌曲，届时暂停既有音乐 owner 并抑制自动下一首；保留应用、账号与本机状态。等待自然曲终时暂时关闭原生单曲循环，取消或之后播放时恢复原播放顺序。计时仅在当前进程中有效，进程重启后不续存，不描述为退出应用或注销账号。
- **入口与复用**：设置、账号卡片及播放器 More 提供各自适用的工具入口。新增页面复用既有主题、返回、表单、玻璃 sheet 与音频服务；启动/品牌 raster 字节未改，新增 shipping 数据是附来源与许可的离线地区 JSON，主机 QA 字体不进入 APK。
- **上游与许可**：资料、均衡、免费音效映射、MV 和计时语义参考 md3Music v6.1.0，提交 `4f783a998d7a108685dfa2e3dc9449df9c474c4e`；本机 bundled Rust API 仍为原固定 revision。具体移植范围见 [1.0.3 ports notice](third_party/md3music/MESTING-1.0.3-PORTS.md)，地区许可保存在 `third_party/region_data/`，不把上游 Material 页面当作本应用视觉规范。

已有主机证据位于 `.codex-artifacts/2026-10-27-release103/`：`broad-beta-tests.log` 为广泛 Beta 回归 **122 项通过**，`final-ui-tests.log` 为最终 UI **22 项通过**，`flutter-analyze.log` 为 **No issues found**。两组是各自有界结果，后续选定补充验证有重跑，不将各日志或重复运行相加成总通过数。独立 finish review 最终为 **SHIP**，persistence/fidelity/ceiling 均通过，R1 音效图标语义和 6dp 滑块要求已 resolved，无开放发现。

`final-ui/` 中的最终有效捕获来自生产 Flutter 控件、合成账号/目录/MV 画面和 Windows 专用 QA 字体；它们证明主机可观察的布局、状态与交互，不能证明真实云端写入、真实音频输出、Android GPU 光学、TalkBack、设备安装或发布。本轮没有访问手机或设备测试；Android Release 构建、原签名、music 发布及线上 HTTPS 下载/续传已核验，详见同版交接。P8P SDK 属于用户另行要求的后续任务，须在核验 1.0.3 已发布后才开始；本节记录的 1.0.3 实现不包含该 SDK。

## Release 1.0.4 current contract (authoritative)

2026-10-28：已先发布并冻结 1.0.3，再按用户确认完成 P8P SDK 接入，**1.0.4 / code 25 已发布 music**。当前产品继续保留 1.0.3 的资料、均衡/音效、MV、定时及 6dp 滑块，既有素材、原生音乐 owner 和页面风格保持同一实现。签名、包名及内部 beta 身份延续，详见 [1.0.4 交接](docs/SESSION-HANDOFF-2026-10-28-v1.0.4.md)。

更新下载使用本地 Ring Download SDK 1.1.0：music appId，P2P/P8P 开启，用户端 allowSharing=false；HTTPS 先行，可用节点提供辅助分片，SDK 管理会话、取消与续传。更新发现仍为原 health/真实 code，宿主保留二次大小/SHA 和安装前校验，完成文件原子移至原安装目录；旧 HTTP partial 兼容一次，不启动重复整包降级下载。隐私说明已披露实际网络协商和诊断，版本说明新增 1.0.4。

宿主回归 80、选定 stable 18、Beta 隐私界面 2 通过；SDK 首轮 213 通过及 1 个测试工作目录夹具失败，修正后该项复测通过，保留原结果。静态分析、完整 Android 构建、原签名及原生库对齐通过。真实 SDK 默认引擎的主机 HTTPS 下载/暂停/续传、旧 1.0.3 原代码发现及完整下载本版、主备有界入口和公开 metadata 均已核验。真实 Android P8P 节点贡献、安装和音频/视频仍由用户自行验收，没有访问手机。完整源码包含原权利的 SDK，以本地私有快照保存，GitHub 尚未同步本轮。


## Release 1.0.5 current contract (authoritative)

2026-10-28：沿用既有 Apple/Cupertino 和完整 premium 玻璃世界。资料、MV、均衡/音效、触感和欢迎页的滚动合成内提供真实同色背景；定时弹层统一应用主题。完整播放器更多菜单移除重复歌词项，默认折叠“封面样式”；工具栏设备 glyph 统一光学尺度，卡片/设备列表尺寸不改。均衡圆点继续 6dp/轨道约2dp/48dp响应区。

BetaLiquidMenu 从真实胶囊或输入区域分离，以同一几何进度反向融合；Impeller 使用共享 premium 层的 SDF 连接，Skia 使用既有光学回退。绘制 tick 不重建菜单内容，文本前景可以淡入，但不以祖先 opacity 隔离 live glass。减少动画跳过大幅形变；真实编辑动作仍由 EditableText 处理。底栏附件统一几何时钟，保留重定向和快速反转的连续位置。

MV 全屏请求横屏，退出/系统返回恢复竖屏和原详情，同一控制器保留位置。音效列表用一致的本地主题 symbol 代替旧远程缩略图，业务预设能力不扩张。Track 只清理末尾音频扩展名的显示，原持久化标题和文件身份保留。

本轮 179 项受影响 Beta 回归、56 项选定 stable 回归通过；42 张主机控件捕获已复核。来源与边界见 docs/fixes-2026-10-28-v1.0.5.md 和同版交接。主机结果不认证实际 Android GPU 液态效果、120fps、真实 P8P 字节贡献或安装。GitHub 归档和 music 后台分开记录；music 的 1.0.5 管理 UI 发布被浏览器 URL 安全检查中止。
## 2026-10-28 1.0.8 性能专项

保留1.0.7功能和Apple玻璃视觉，新增严格条件下的重复采样／背景读取复用及schema2用户自行导出的流畅度报告。报告以原始帧时间关联CPU绘制计数和光栅耗时，不将显示120Hz或主机验证冒充实际120fps。发布身份1.0.8/code29，详细边界见同版接续。


## 1.0.50 approved package and song-list extension (2026-11-04)

The user confirmed public Android package com.mesting.music from 1.0.50 onward, with no automatic migration from the separate .beta installation. The internal beta flavor still selects the current UI/native libraries and patched engine; the update feed is unchanged and this task authorizes local delivery only. Ordinary nested pages share reversible parent/child horizontal travel; special entries keep their original forms. Song lists use a compact real-cover bookmark capsule with integrated close, and platform-aware song menus with real non-trading operations and metadata. Favorites support account-isolated persistent local pins without changing official order. See docs/fixes-2026-11-04-v1.0.50.md for exact data/validation boundaries.
