# Gitee 私有源码备份完成交接

日期：2026-11-04，Asia/Shanghai。用户逐项确认范围、私有可见性、附件保留原位置及最终执行方案。GitHub 原仓库与本机产品工作区保持原样，Gitee 是独立的源码副本。

- [Gitee 私有仓库](https://gitee.com/Mesting42/mesting-music-flutter)，默认 `main`，当前提交 `0549f0c93373cb8b02abdd25d6be2f54efc61cd7`。
- [71 个版本目录](https://gitee.com/Mesting42/mesting-music-flutter/blob/main/docs/gitee-versions.md)，每版另有原发行说明和原附件链接。
- 范围：早期 Beta.1～Beta.21，以及新版 1.0.1～1.0.51，共71版。1.0.38只有本系列私有候选，没有正式冻结版，未创建该标签。旧稳定版、Java/MySQL独立测试与私有候选未建立备份标签；既有提交所需祖先历史随 Git 保留。
- 69个旧标签保留 GitHub 原始标签、提交和树对象；50/51分别由各自原冻结ZIP建立独立注释标签与提交，未用今天的工作树倒填历史。
- Gitee 的 `main` 在51冻结源码之上增加导航和说明；50/51标签本身包含原ZIP全部文件，分别2362/2423项，内容逐字节核验。
- 平台发行版页面未另建；71版说明保存为 `docs/gitee-release-notes/<tag>.md`，由版本目录访问。685个原附件链接保留，附件仍位于GitHub；50/51原APK及冻结ZIP仍只保留本地，本轮未上传或重新发布。

## 验证

从Gitee进行独立网络裸克隆，完整严格 `git fsck --full --strict` 通过。唯一主分支及71个标签与允许清单完全相符；跨71版111089个源码条目的树身份核对通过，50/51另与原冻结ZIP逐项SHA-256核对。75份新增导航/目录/每版说明文件内容核对。

GitHub全量回读：两分支、94标签、73发行版和724附件的引用/正文/文件信息与备份前一致。未对GitHub发起任何写操作。未访问手机/ADB、真实音乐账号或音乐业务后台，不改变原测试/设备验收边界。

本机保留原beta/HEAD `b6bcd5425e0df3e03febdd460b56d0ed42004c52`、原索引和空暂存、2425份原工作文件与94份冻结APK/ZIP、签名与依赖锁。仅新增本文、`gitee`远端及 `refs/remotes/gitee/main` 跟踪引用；`origin`仍为GitHub。50/51新标签创建在隔离备份Git库与Gitee中，未强行挪动主工作区分支或向GitHub补推。

## Git 和两个远端

Git 是本地版本管理工具；GitHub 和 Gitee 是托管 Git 仓库的平台。`origin` 与 `gitee` 是两个独立目的地，向其中一个推送不会自动同步另一个。发行版附件不是普通Git对象，也不会随 `git push` 自动复制。

当前主工作区仍故意停在旧beta提交并保留1.0.51等脏改动，不能直接reset/pull/checkout覆盖。以后需同步新的冻结版本时，按对应版本源码及明确目的地建立提交/标签，不运行 `push --mirror`、强推或通配标签来混入旧稳定系列。

私有证据：`.codex-artifacts/2026-11-04-gitee-archive/` 的 `prepared-backup.json`、`push-final.json`、`fresh-source-verification.json`、`github-unchanged-verification.json`、`delivery-final.json`。凭据仅使用既有安全存储，不写入日志、源码或附件。
