# Beta 页面按钮与滚动交互约定

适用于 Mesting Music 当前工作区。新增页面与修复既有页面时一并遵守。

## 公共入口

- 常规操作、返回和带文字的按钮使用 `BetaGlassButton`；紧凑图标操作使用 `BetaGlassAction`。页面只提供业务回调、文案和可用／加载状态。
- 不在业务页面复制 `GlassButton.custom`、灰色禁用背景、整层 `Opacity` 或按压控制器。特殊播放器／导航光学表面需要直接使用底层控件时，单独说明原因并验证取消流程。
- `onPressed: null` 表示不可用；`loading` 表示请求进行中；`interactionEnabled` 可暂时阻止并行请求。控件负责同步处理命中、键盘焦点、辅助功能和按压状态，页面不能仅隐藏回调或仅改变颜色。
- 榜单横向胶囊由父级提供一整条玻璃光学层，分区使用 `BetaGlassButton(embeddedInPill: true)` 保留点击、焦点、反馈与拖动取消，不再给每个分区重复绘制独立底色；普通按钮保持默认独立光学层。

## 材质与状态

`betaNeutralActionGlass` 集中提供中性 clear-body 材质，`betaBlueActionGlass` 提供蓝色材质。clear-body 固定底色合成，继续保留模糊、折射、灯光与玻璃边缘，不让背景亮度归一化把操作按钮变成灰色实底。

不可用按钮保留同一套玻璃光学材质，通过前景和真实不可用状态区分；公共包装传入 `enabled: false`、`fadeWhenDisabled: false`，而不是让底层按钮保持可交互以绕过整层半透明。加载期间保持原强调色。

`GlassButton.persistPressOnDrag` 默认是 `false`。高亮与 `LiquidStretch` 形变会在超过点击容差后一起取消，之后直到手指抬起都不会重新进入按压。自由拖动的特殊玻璃表面可以显式选择 `true`，普通页面按钮不使用这个选项。

## 必须覆盖的交互

1. 从按钮上开始上下拖动列表，手指继续停在屏幕上：高亮和放大均应恢复，操作不能触发；不能只检查抬手后的状态。
2. 请求或同级按钮操作在按压期间将按钮设为不可用：当前按压应立即结束，再次启用后不能恢复旧高亮。
3. 浅色、深色、窄屏与大字号；键盘／辅助功能的可用状态必须与触摸一致。
4. 保留正常轻点的玻璃膨胀、回弹和反馈，不用关闭整套动画来修复滚动取消。

现有回归入口是 `test/followup_controls_regression_test.dart`，包含真实诊断页和两类公共按钮的滚动取消、不可用状态、直接控件与包装控件的中途禁用，以及显式自由拖动的兼容检查。

本地音乐的导入操作采用同排布局；常规手机宽度完整显示，窄屏／大字号横向滚动，保持文本缩放与可达性，不缩放整行文字来强行塞入。


## 1.0.17 公共滚动与菜单约定

Beta使用`BetaScrollBehavior`提供弹性越界滚动，避免Material拉伸指示器把玻璃放入无法取样Scaffold的独立ImageFilter层。不得通过降低玻璃质量或取消普通按钮弹簧修复灰底；页面在必要时提供同层背景。首选`PlatformPageFrame`保持页面标题、返回和背景一致。

选择表单使用`BetaChoiceField`，图标更多菜单使用`BetaPopupMenuButton`，排序／范围使用`BetaAnchoredMenu`的玻璃分支；加载、禁用必须与真正命中状态一致。新内容页使用`betaContentRoute`或已配置公共转场的Material路由，不能另写退出应用回调。`test/netease_v117_ui_test.dart`覆盖新个人页、已下载播放全部、逐曲来源置灰与三级返回；原有按住拖动、禁用和UID保存用例仍保留。
