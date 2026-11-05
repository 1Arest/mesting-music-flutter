# 酷狗标准版 20.8.6 授权和等级协议核对

本记录针对 1.0.52 的标准授权补充及正常听歌计量实现。协议静态证据与主机 fixture 不等于手机、真实账号或酷狗最终入账验收。本轮没有访问手机、ADB 或真实音乐账号。

## 参考物与核对方式

- 原始参考物：`com.kugou.android`，20.8.6 / code20869，APK SHA256 `d434f15fef375cb88ca18a9bc1412dd8df8e11cb47ec4604ce67114a35f3168a`。本记录的静态观察不单独保证第三方下载包的官方签名真实性。
- 按原 DEX 提取单个 DEX 并保留原 manifest/resources，使用 REA/JADX 检查明确类和方法。跨 DEX 的零调用数量不视为完整无调用证据。
- `og3.e.f = 0x7f11001a` 对应原始资源 `res/c/a6config_compress`。资源 364440 bytes，SHA256 `0c6a1a272390a6844eeb55d7e082ad6b59896535469bebc455c88a3531344211`；Base64 解码后 273329 bytes，SHA256 `c79f064b37fdbcbfc97cca2711b06346b9522c7d1966b02bef585d4ac72c6e7d`；gzip 解压后 JSON 1348582 bytes，SHA256 `dd811589436fdbea1079bae5c00cf7d375ed0d26000dcd64edb73b39e594ddc4`。
- 原 APK、解压配置、反编译输出及完整证据保留在私有调查目录，不进入正式源码 ZIP。产品仅保留独立实现、公开协议常量及合成 fixture。

## 标准扫码合同

原生 `KGQRCodeApi.b/c`、Retrofit 方法注解、`QRCode.getFinalQrcodeString` 和 `LoginResponse` 字段注解共同核对以下合同：

| 阶段 | HTTPS 地址 | 特有参数 |
| --- | --- | --- |
| 生成 | `https://login-user.kugou.com/v2/qrcode` | GET，`plat=1,type=1` |
| 轮询 | `https://login-user.kugou.com/v2/get_userinfo_qrcode` | GET，`plat=1,qrcode=<本次返回值>` |
| 扫码文本 | `https://h5.kugou.com/apps/loginQRCode/html/index.html` | `qrcode=<本次返回值>,appid=1005` |

`LoginHistoryUserEntity.TYPE_PHONE` 的原 DEX 静态值是字符串 `1`。本合同不沿用 Lite 登录现有的 `plat=4`。共同参数为本机注册的 `mid/uuid/dfid`、`appid=1005,clientver=20869,clienttime=<秒>`；签名为标准 appkey 包裹排序后未经 URL 转义的 `key=value` 连接串的 MD5，小写 hex。生成和轮询响应字段为 `error_code`，不是 Java 字段展示名 `code`。

轮询 `data.status` 为 1、2 时继续等待，为 0 时过期，为 4 时取得 `userid/token/nickname/pic`。未知状态不当作成功。官方 fragment 的轮询上限为 300 秒；产品可以提前终止。

官版取得状态 4 后会继续走 `v5/login_by_token`。该交换涉及原生 `NativeParams.encryptWithT0` 和设备信息，本轮没有把 Lite 固定值套用到标准交换，也没有宣称复刻此过程。

Mesting 对本次 `appid=1005` 签发的 QR 凭据，先请求一次标准 `v4/get_grade_info`：`d_sec=0,diff_sec=0,medal=0`。仅当响应明确成功、返回 UID 相同、`d_sec` 非负、等级及积分字段完整合法时，才把它作为该 UID 的补充标准授权交给账号仓库。验证失败销毁该临时 challenge，保留原登录。此读回验证不增加听歌时长。

标准授权保存于同 UID 的加密账号条目，保留 Lite 主 token、主播放协议、音乐库和队列。没有将旧 Lite token 改贴 `appid=1005` 标签的回退路径。网络请求不跟随重定向；取消、换账号、刷新 challenge 或页面退出后，不发布晚到的授权结果。

## v4 等级请求字节合同

`com.kugou.common.userCenter.protocol.u.a`、`dr3.a`、`dr3.h0`、`ParamGenerator.W/B0` 和 `Utils.r/z` 确认：

- 地址固定为 `https://userinfoservice.kugou.com/v4/get_grade_info`，JSON POST。外层含 `plat,userid,clienttime_ms,type,d_sec,diff_sec,y_type,m_type,pk,params,medal`。
- 临时 secret 是随机 AES 密钥字节转小写 hex 的前 16 字符。MD5(secret) 的 32 个小写字符作为 UTF-8 AES-256 key，后 16 字符作为 IV；AES/CBC/PKCS5Padding（AES 块下与 PKCS7 相同），密文小写 hex。
- `params` 明文包含当前 `userid/token` 和计量校验 MD5，真实可用会员字段才可另行附带。校验串为十进制 `d_sec,diff_sec,y_type,m_type` 依次直接连接。
- `pk` 明文为 `clienttime_ms/key` JSON 的 UTF-8 字节，从 128-byte 零数组的 offset0 开始复制，使用标准配置公钥做 RSA/ECB/NOPADDING，输出定长大写 hex。不是 PKCS#1 填充，也不是把明文整数左补零代替右零填充。
- URL 共同参数含注册设备、标准身份及秒级 clienttime；签名为 `MD5(appkey + 排序原始key=value连接串 + 实际JSON正文 + appkey)`。签名前不 URL 转义，传输时再转义。凭据只在加密正文内，不进入 URL 或日志。

独立 `KugouV4GradeProtocol` 不执行网络请求、不决定有效听歌时长、不清理待发队列。合成 golden 使用 PyCryptodome AES 和 Python 整数模幂独立生成，检验 RSA 填充方向、hex 大小写、AES、毫秒转秒和实际正文签名，不包含真实账号数据。

## 正常计量与累计语义

原生 `protocol.k.d` 解析成功响应后，读取服务器累计 `data.d_sec`，新对象 `localMillis += d_sec * 1000`，先置 `diff_sec=0`。`UserGradeInfoHelper.r` 随后计算 `max(旧localMillis/1000 - 新服务器d_sec, 0)` 作为仍有差额；内部 `$j.a` 在成功后把 `localMillis` 保持为本机与服务器返回两者较大值，并持久化。

因此 `d_sec` 是本机已知累计秒（可信服务器基线加本机正常新增），不能把单次新增量冒充累计；`diff_sec` 是尚未被服务器累计覆盖的秒数。失败、超时、结果不明或账户周期变化时，不可据此盲目重发历史已接收/未知日志。有效听歌只能来自实际连续播放的计量，seek、暂停和账号切换不产生额外听歌时长。

成功响应只能说明这次接口的明确回执；官方日/周/月统计、等级变化及官版中的最终显示，必须分开读取核对。主机测试不能证明真实账号已入账，也不能证明历史欠账已经恢复。

## 仍需真实设备和账号验收

本轮主机仅验证合成网络与加密 fixture；真实二维码扫码、QR token 能否通过当前服务的零计量验证、长时间播放后的服务端累计变化，以及官版统计与等级的最终变化，仍待用户实际验收。若 QR token 被服务端要求进一步原生交换，现实现会明确失败并保留原登录，不伪装为授权成功。
