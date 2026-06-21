# CodexUsageBar v0.1.0

首个可运行版本。

## 功能

- macOS 顶部状态栏常驻显示 Codex 剩余用量：`h45 w25`
- 点击状态栏后显示完整 Usage 信息
- 支持手动刷新，自动刷新间隔为 5 秒
- 点击状态栏菜单时会立即刷新一次
- 支持打开官方 Usage 页面
- 支持退出 App
- 默认不显示 Dock 图标

## 数据源

当前版本从 Codex 本地日志 `~/.codex/logs_2.sqlite` 读取官方响应头：

- `x-codex-primary-used-percent`
- `x-codex-secondary-used-percent`
- `x-codex-primary-reset-at`
- `x-codex-secondary-reset-at`

状态栏显示的是剩余百分比，即 `100 - used-percent`。本项目不读取 Cookie、不读取浏览器数据库、不读取 `auth.json`、不模拟登录、不上传用户数据。

## 安装

下载 `CodexUsageBar-v0.1.0.zip`，解压后打开 `CodexUsageBar.app`。

如果 macOS 拦截未签名 App，可在“系统设置 -> 隐私与安全性”里允许打开，或自行从源码构建。
