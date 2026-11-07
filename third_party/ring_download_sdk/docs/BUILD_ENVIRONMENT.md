# 已验证构建环境

Flutter 3.47.7 / Dart 3.13.5；Android示例 AGP9.0.1、Gradle9.3.1、Kotlin2.4.20、JDK17、API24+、arm64-only。SDK声明的最低环境不等于所有低版本组合均已验收，先按已验证工具链接入。

示例 Gradle 配置限制两个工作线程，Kotlin编译使用 in-process，Gradle堆上限1536MiB，避免8GB Windows主机同时启动大型编译守护进程。大型宿主应按自身依赖规模调整，不视为SDK运行时内存上限。有关编译进程策略参考 Kotlin 官方文档：https://kotlinlang.org/docs/compiler-execution-strategy.html 。

以下首次构建/安装问题是1.0.0的历史记录。1.0.2已通过 package.cmd 重建最终验证包，并重新完成真实下载和前后台分享验收，详见 validation/summary.json。

1.0.0首次构建的外层脚本10分钟时限先触发，原生子进程仍在运行；已取消该轮并限制编译并发/堆，再通过 package.cmd 完成。最初APK检查发现依赖带入额外ABI，已在Android defaultConfig添加显式arm64过滤。最终arm64包再次通过签名、ZIP与16KiB对齐检查后才在设备验收。

本机原有JNI缓存权限问题沿用工作区临时同版源码副本：181个原始文件逐一哈希一致，未修改插件源码；构建后恢复覆盖和依赖元数据。此环境补救不写入分发包，也不修改客户Flutter SDK。正常客户环境只需可写的标准Pub/Gradle缓存。

OPPO平板首次安装独立示例时出现系统安装确认；读取实际界面后继续安装，未禁用安全检查。示例保持自己的包名，不替换LifeRing或实验室。SDK本身不自动安装下载的APK。
