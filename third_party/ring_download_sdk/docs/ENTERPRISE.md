# 当前交付范围

本版交付目标是让其他 Flutter Android App 按 LifeRing 相同下载契约接入公开 APK 平台。安装级设备标识、版本请求头、下载会话、续传、HTTPS/P2P/P8P、校验、取消、分享撤回和诊断由 SDK 封装；接入方不再按旧文档重写这些底层功能。完整步骤、字段及自备资料见 [开发者手册](https://download.csnas.asia/sdk)。

App 自己继续处理登录、更新资格、UI 与安装器。已有业务后台的接入用 download(request) 或 resolveRelease，不绕过其灰度和账号策略。普通公开发布可用 downloadLatest()，服务端无需为每个新 App 修改客户端核心。

使用客户私有域名、私有文件和跨租户权限，属于独立部署能力，需要服务端发布权限、短期票据、session/peers/signal/piece/traffic 全链路租户与文件隔离，以及配额、审计和撤销。当前公开平台并未实现这些；本版不把公开 app slug 当成私有授权，也不在客户端嵌入管理密钥。

原生 Kotlin/Java AAR、iOS、Windows 客户端是另外的平台交付。当前提供 Flutter Android；不会要求本项目现有 Flutter App 改用其他技术栈。

当前正式源码版为 1.1.0，服务端 P8P 能力已部署；原 1.0.3 及历史候选保持原记录。历史稳定结果在 validation/summary.json；本版范围在项目 p8p/validation/。按发布方决定不追加长期耐久或大样本测试，未测范围不标为通过。HTTPS 立即开始，有可用 P8P 才介入；内网实测不代表全部蜂窝/公网 NAT 成功率。正式宿主仍验证更新入口、资格、包名/签名、系统安装及前后台行为，App 与业务后台由 App 开发者发布。

外部 COS/CDN 不依赖本站 health/P2P，允许没有预期摘要；收据 verification 明确校验级别。业务后台负责把有效 COS 放进主下载字段，不能统一强制 health。LifeRing 当前授权后台主地址仍为本站时，health 失败返回 503，不自动采用另存 COS；开发者修改主下载字段后才下发 COS。SDK 不新增第三个 COS 候选。安装统计需要宿主调用对应 API，不能把打开安装器当安装成功。
