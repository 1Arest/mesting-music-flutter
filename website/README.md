# Mesting Music 官网

这是 Mesting Music 的静态官网，包含 App 功能介绍、使用指南、主题展示和可操作的黑胶播放器。

[访问线上官网](https://download.csnas.asia/music/)

## 本地预览

在仓库根目录运行：

```sh
python -m http.server 8000 --directory website
```

打开 [http://localhost:8000/music/](http://localhost:8000/music/)。

## 部署路径

将 `website/music/` 挂载到现有下载站的 `/music/`。生产环境还提供以下服务：

| 路径 | 用途 |
| --- | --- |
| `/music/download` | Android 安装包下载 |
| `/api/app/music/health` | 当前版本和安装包大小 |
| `/music/media/warm-tea.mp3` | 由下载站单独托管的试听音频，支持分段读取 |

本地静态预览可检查页面和交互外观。测试试听时，可将有权使用的 MP3 放在 `website/music/media/warm-tea.mp3`。实际下载与版本数据可在线上官网验证。
