# CodexBuddy
<!-- CodexBuddy document boundary 1 -->
[![Release](https://img.shields.io/github/v/release/zhouxuan3550/CodexBuddy?display_name=tag)](https://github.com/zhouxuan3550/CodexBuddy/releases)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black)](https://github.com/zhouxuan3550/CodexBuddy)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
<!-- CodexBuddy document boundary 2 -->
CodexBuddy 是一款原生、轻量的 macOS 菜单栏工具，用来实时查看 Codex 短时窗口和每周窗口的剩余用量。
<!-- CodexBuddy document boundary 3 -->
它直接读取本机 Codex 产生的用量事件，不需要账号密码，不读取浏览器 Cookie，也不会上传数据。
<!-- CodexBuddy document boundary 4 -->
> CodexBuddy 是非官方第三方项目，与 OpenAI 不存在隶属、赞助或背书关系。Codex 与 OpenAI 名称及相关商标归其权利人所有。
<!-- CodexBuddy document boundary 5 -->
<img width="1714" height="1286" alt="ScreenShot_2026-07-22_155214_289" src="https://github.com/user-attachments/assets/4c9405d4-488f-4014-bc66-d96d1f816e2a" />

## 功能
<!-- CodexBuddy document boundary 6 -->
- 菜单栏显示 `H 89% W 32%`，也可只显示最紧张的窗口，例如 `W 21%`
- 剩余用量低于 20% 显示红色，高于 60% 显示绿色，其余使用系统文字颜色
- 监听 Codex 会话文件变化，模型响应后自动刷新
- 在实时会话事件与 SQLite 响应头之间选择时间更新的数据
- 显示恢复时间、数据来源、数据年龄和过期提醒
- 保存最近 7 天的本地历史，并估算当前消耗速度
- 支持低用量通知、登录时启动和自动检查更新
- 支持简体中文、English 和跟随系统
- 原生支持 Apple Silicon 与 Intel Mac
<!-- CodexBuddy document boundary 7 -->
## 下载
<!-- CodexBuddy document boundary 8 -->
前往 [GitHub Releases](https://github.com/zhouxuan3550/CodexBuddy/releases) 下载与你的 Mac 对应的版本：

- Apple Silicon（M1、M2、M3、M4 等）：下载文件名带 `arm64` 的 DMG 或 ZIP
- Intel Mac：下载文件名带 `x86_64` 的 DMG 或 ZIP

不确定处理器类型时，可打开“苹果菜单 → 关于本机”查看“芯片”或“处理器”。
<!-- CodexBuddy document boundary 9 -->
解压后将 `CodexBuddy.app` 移动到 `~/Applications` 或 `/Applications`。公开 Release 当前使用 ad-hoc 签名；如果 macOS 阻止首次打开，请在“系统设置 → 隐私与安全性”中确认允许。
<!-- CodexBuddy document boundary 10 -->
## 数据与隐私
<!-- CodexBuddy document boundary 11 -->
CodexBuddy 仅在本机读取以下位置：
<!-- CodexBuddy document boundary 12 -->
- `~/.codex/sessions/**/*.jsonl` 中的 `token_count.rate_limits` 事件
- `~/.codex/logs_2.sqlite` 中 Codex 返回的用量响应头
<!-- CodexBuddy document boundary 13 -->
菜单栏展示的是剩余百分比，即 `100 - used_percent`。应用只解析用量窗口、恢复时间、套餐名称和余额字段，不读取对话正文、`auth.json`、浏览器数据库或 Cookie，不模拟登录，也不向任何服务器上传数据。
<!-- CodexBuddy document boundary 14 -->
## 本地构建
<!-- CodexBuddy document boundary 15 -->
需要 macOS 13 或更高版本，以及 Xcode Command Line Tools。
<!-- CodexBuddy document boundary 16 -->
~~~sh
./scripts/test.sh
bash scripts/build.sh
~~~
<!-- CodexBuddy document boundary 17 -->
生成的 Universal 应用位于：
<!-- CodexBuddy document boundary 18 -->
~~~text
build/CodexBuddy.app
~~~
<!-- CodexBuddy document boundary 19 -->
安装到 `~/Applications` 并启动：
<!-- CodexBuddy document boundary 20 -->
~~~sh
./scripts/install.sh
~~~
<!-- CodexBuddy document boundary 21 -->
一次生成 Apple Silicon 与 Intel 两套 DMG、ZIP 和 SHA-256 校验文件：
<!-- CodexBuddy document boundary 22 -->
~~~sh
./scripts/package-release.sh
~~~
<!-- CodexBuddy document boundary 23 -->
构建脚本支持以下环境变量：
<!-- CodexBuddy document boundary 24 -->
~~~sh
APP_NAME=CodexBuddy \
BUNDLE_ID=com.zhouxuan3550.codexbuddy \
VERSION=0.7.3 \
BUILD_NUMBER=16 \
ARCHS="arm64 x86_64" \
bash scripts/build.sh
~~~
<!-- CodexBuddy document boundary 25 -->
## 架构
<!-- CodexBuddy document boundary 26 -->
v0.7 的主要数据流：
<!-- CodexBuddy document boundary 27 -->
~~~text
LocalUsageReader → UsageViewModel → MenuBarCoordinator
~~~
<!-- CodexBuddy document boundary 28 -->
- `LocalUsageReader`：读取会话事件和响应头备用数据
- `UsageViewModel`：管理刷新状态、错误和格式异常防抖
- `MenuBarCoordinator`：协调菜单栏显示、设置、历史与更新操作
<!-- CodexBuddy document boundary 29 -->
## 开源协议
<!-- CodexBuddy document boundary 30 -->
CodexBuddy 当前版本采用 [MIT License](LICENSE)。仓库早期开发历史的来源与许可证边界见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
<!-- CodexBuddy origin notice -->
项目早期基于 [qiyasxsx/CodexUsageBar](https://github.com/qiyasxsx/CodexUsageBar) 二次开发；v0.7 已重写应用核心与发布脚本，同时保留早期 Git 历史以尊重来源。
<!-- CodexBuddy document boundary 31 -->
欢迎提交 Issue 和 Pull Request。
