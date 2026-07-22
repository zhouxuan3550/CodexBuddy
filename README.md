# CodexUsage

一个原生、轻量的 macOS 菜单栏工具，用于显示 Codex 短时窗口与每周窗口的剩余用量。

> 非官方第三方项目，与 OpenAI 不存在隶属、赞助或背书关系。Codex 名称及相关商标归其权利人所有。

## v0.6.0 体验版

- 菜单栏常驻显示剩余用量，例如 `H 89% W 32%`
- 用量低于 20% 时显示红色，高于 80% 时显示绿色，其余使用系统文字颜色
- 点击菜单栏即可打开“恢复时间轴”：用克制的剩余百分比配合现在、恢复日期和相对倒计时
- 摘要同时显示“剩余 / 已使用”，避免百分比含义混淆
- 有多个用量窗口时，自动选择剩余最少的窗口作为时间轴主状态，并保留另一窗口的简要信息
- 使用 SF Symbols 和原生 macOS 菜单交互，设置、刷新、官方页面、关于和退出均可直接操作
- 实时监听 Codex 会话文件变化，模型响应后无需等待轮询即可刷新
- 菜单内显示数据来源与数据年龄；数据超过 30 分钟或窗口已重置时显示警告
- 可选 5、15、30、60 秒自动刷新，默认 15 秒
- 菜单栏支持“双窗口”和“单值（最紧张）”两种模式，单值仍保留 `H` / `W` 前缀
- Session 日志格式异常连续出现时主动提示，同时继续显示可用的响应头备用数据
- 历史记录按真实事件去重，耗尽估算只使用最近 15 分钟内的不同事件时间，并自动排除窗口重置前的数据
- 支持登录时自动启动
- 支持 10%、20%、30% 低用量提醒，并按重置周期去重
- 支持跟随系统、简体中文和 English
- 原生支持 Apple Silicon 与 Intel Mac
- 可自定义应用名称、Bundle ID、版本号和图标
- 推送 `v*` 标签后由 GitHub Actions 自动创建 Release
- 默认不显示 Dock 图标
- 启动新版时自动退出相同 Bundle ID 的旧实例，避免菜单栏同时驻留
- “关于 CodexUsage”中可查看版本号与构建号

## 隐私边界

应用读取 Codex 最近会话文件 `~/.codex/sessions/**/*.jsonl` 中的官方 `token_count.rate_limits` 事件。这个事件会在模型响应后更新，与 Codex 官方界面使用的实时用量一致。应用会监听会话目录变化，并在事件写入后立即刷新。

应用也会查询 `~/.codex/logs_2.sqlite` 中最新的官方 Usage 响应头，并在两类数据中采用更新时间较新的结果：

- `x-codex-primary-used-percent`
- `x-codex-secondary-used-percent`
- `x-codex-primary-reset-at`
- `x-codex-secondary-reset-at`

菜单栏显示的是剩余百分比，即 `100 - used-percent`。应用只在本地扫描最近会话文件的尾部并解析 `rate_limits` 字段；不读取 `auth.json`，不读取浏览器 Cookie 或浏览器数据库，不模拟登录，也不上传任何信息。

应用会按照数据报告的实际窗口时长识别短时窗口和周窗口，并忽略时长为 0 的无效窗口。如果账户当前只提供周窗口，菜单栏会只显示类似 `W 35%`，不会伪造一个短时窗口数值。菜单中会标明当前结果来自“实时事件”还是“响应头备用”。

## 系统要求

- macOS 13 Ventura 或更高版本
- 源码构建需要 Xcode Command Line Tools

## 构建

```bash
./scripts/build.sh
```

默认生成 Universal 应用：

```text
build/CodexUsage.app
```

运行数据模型与双语格式测试：

```bash
./scripts/test.sh
```

安装到 `~/Applications` 并启动：

```bash
./scripts/install.sh
```

安装脚本会先退出正在运行的同名旧实例，再替换并启动新版，避免菜单栏继续显示旧进程缓存的数据。手动替换 App 时也请先从菜单中退出旧版。

如果需要安装到系统应用目录：

```bash
INSTALL_DIR=/Applications ./scripts/install.sh
```

登录启动依赖 macOS 系统登录项接口。请先将 App 安装到 `~/Applications` 或 `/Applications`，再从菜单中开启“登录时启动”。

## 打包

```bash
./scripts/package.sh
```

默认生成：

```text
build/CodexUsage-v0.6.0.zip
build/CodexUsage-v0.6.0.zip.sha256
```

本地发布包使用 ad-hoc 签名。面向公众分发时，建议替换为 Apple Developer ID 签名并完成 notarization。

## 品牌与构建参数

```bash
APP_NAME=MyUsageBar \
BUNDLE_ID=com.example.myusagebar \
VERSION=0.6.0 \
BUILD_NUMBER=12 \
ICON_SOURCE=/absolute/path/to/icon.png \
./scripts/package.sh
```

也可以通过 `ARCHS=arm64` 或 `ARCHS=x86_64` 生成单架构版本；默认值为 `arm64 x86_64`。

## 自动发布

仓库包含 `.github/workflows/release.yml`。推送版本标签后会构建 Universal ZIP、生成 SHA-256 校验文件并创建 GitHub Release：

```bash
git tag v0.6.0
git push origin v0.6.0
```

## 来源与授权

本项目基于 [qiyasxsx/CodexUsageBar](https://github.com/qiyasxsx/CodexUsageBar) 二次开发。
