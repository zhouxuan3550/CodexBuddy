# CodexUsageBar v0.1.0

首个可运行版本。

## 功能

- macOS 顶部状态栏常驻显示 Usage 简化信息：`h89 w32`
- 点击状态栏后显示完整 Usage 信息
- 支持手动刷新
- 支持打开官方 Usage 页面
- 支持退出 App
- 默认不显示 Dock 图标

## 数据源

当前版本使用 Mock 数据：

```text
5 小时 89% · 23:31
1 周 32% · 6月26日
```

真实官方数据源入口已预留在 `CodexUsageProvider`。在没有稳定官方 API、CLI 输出或官方本地状态文件前，不做 Cookie 抓取、浏览器数据库读取或模拟登录。

## 安装

下载 `CodexUsageBar-v0.1.0.zip`，解压后打开 `CodexUsageBar.app`。

如果 macOS 拦截未签名 App，可在“系统设置 -> 隐私与安全性”里允许打开，或自行从源码构建。
