# 网易云一起听累计请求与计时依据

2026-11-01，1.0.34/code55。记录接口事实与实现选择，不包含官版反编译源码、APK 或真实账号数据。

## 静态依据

样本为应用宝分发的网易云音乐 Android 9.6.15/code9006015，224823452 字节；MD5 与分发信息一致，Android SDK 已验证 APK 签名。原包 SHA256 为 `e6427bcb35ccd9e8858ee55c46ec3db56b2f09871adcd8e897244d96cfcf7894`。来源：[应用宝](https://sj.qq.com/appdetail/com.netease.cloudmusic)。只读分析，未安装或运行。

- 原包 `va0.u0$p.f()`：查询 `listen/together/relation/statistics/get/v2`，传当前 `roomId` 和数值数组 `roomUserIds = [好友ID, 当前登录账号ID]`。响应分别读取 `totalConnectionTime`、`currentConnectionTime`、`duration`、`listenCount`。Android SDK 完整原包 smali 已逐条核对；不是只按端点字符串猜测。
- `playpage.l4.c()` 的累计显示读取 `totalConnectionTime`；`playpage.y6.k()` 的本次显示读取 `currentConnectionTime`。REA Evidence：`ev_edbafc24a82ca614b5f40255baf29df838cd73e0409c2a967e92973fa9a9e033`、`ev_979b5c816d8c263c89b344f95f7e3508c6db4b944bb8243853381cacff82ed36`。
- `playpage.r` 按已有秒数对齐分钟，在内存中把 total 和 current 各增加60秒，此段时钟不检查歌曲播放状态。REA Evidence：`ev_38b8c3e19806dccec79d00ee852fc02acec0c9a425bf558c0813f3ac070d71e4`、`ev_15aaef289e022f22304a7133b1a9af892bf5a678fceca4ca2a9e1c2bc1cafc3f`。
- `StatisticsChangeMsg.ensurePreConnectionTime()` 在同房间收到零值时保留之前的 total/current。REA Evidence：`ev_403ba07be803ebffd85cb732b12a69e218fcdfdc2e893f54fbb86139365c447d`。

REA 全包分析超时后，仅对原始 manifest 和 classes17.dex 成员字节组成的派生静态载体分析，覆盖不到其他 DEX 实现。派生包 SHA256 为 `1c4ed46a4e2ef16f052afb37e9aa074934f4beb0d1b324eb18381dc10b316498`，不是原始签名 APK。完整原包 SDK smali 用作交叉核对。混淆类名清单冲突时没有把 SDK 输出冒充 REA Evidence。原始证据与工具配置仅保存在私有 `.codex-artifacts/2026-11-01-together-history-review/`，不进入完整源码ZIP。

## 1.0.34实现

1. 请求由单个好友 ID 改成官版的双方数值 ID；缺少合法双方身份时不退化成单人查询。
2. `TogetherCumulativeClock` 只保存官方累计快照及其之后的单调时钟间隔。每次有效统计替换基准并重置间隔，不另加本次累计，也不叠加旧快照。
3. 进入房间和应用回到前台主动恢复；进程重建从未知开始查询官方值，不拿本机进程存活时间补造历史。暂停播放不暂停累计显示时钟，退出与账号/好友/房间切换清空旧状态。
4. 同一房间已有非零累计又收到零值时，保留已确认显示并标注“上次同步”，暂停续算；新的非零官方值可恢复。新房间的有效零值可以显示零。缺失/错误不回退到本次时长。

## 验证边界

双方 ID 差异为确认的静态请求错误；修正后真实账号是否返回完整历史仍待用户验收。主机测试中的15788小时53分钟是明确标记的合成数据，不是读取用户账号的结果。

用户观察的“一方未退出，即使清后台仍累计”涉及服务端结算。客户端静态证据不能证明所有服务端退出策略；恢复时以官方返回值为准。没有修改结束房间协议，也没有把进程关闭当作显式退出。此前真实一起听结束私信记录问题仍为独立未确认事项。
