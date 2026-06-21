# CodexUsageBar

macOS 顶部菜单栏 Codex Usage 极简显示器。

当前版本按需求文档的第一阶段实现，顶部状态栏使用系统原生字体显示：

- 菜单栏常驻显示：`h89 w32`
- 点击显示 Usage 详情
- 支持手动刷新
- 支持打开官方 Usage 页面
- 支持退出
- 使用 `CodexUsageProvider` 从 Codex 本地日志中的官方 Usage 响应头读取数据，不读取 Cookie、不读取浏览器数据库、不要求输入密码、不上传任何信息

## 构建

```bash
./scripts/build.sh
```

构建产物在：

```text
build/CodexUsageBar.app
```

## 安装并启动

```bash
./scripts/install.sh
```

默认安装到：

```text
~/Applications/CodexUsageBar.app
```

如需改安装目录：

```bash
INSTALL_DIR=/Applications ./scripts/install.sh
```

## 数据源说明

当前版本读取 Codex 本地日志 `~/.codex/logs_2.sqlite` 里最新的官方响应头：

- `x-codex-primary-used-percent`
- `x-codex-secondary-used-percent`
- `x-codex-primary-reset-at`
- `x-codex-secondary-reset-at`

状态栏显示的是剩余百分比，即 `100 - used-percent`，格式为 `h45 w25`。

它不会读取 `auth.json`，不会读取浏览器 Cookie，不会读取浏览器数据库，不模拟登录，也不上传任何用户数据。

## 打包发布

```bash
./scripts/package.sh
```

发布包会生成到：

```text
build/CodexUsageBar-v0.1.0.zip
```

## 刷新频率

App 启动时会刷新一次，此后每 5 秒自动刷新一次；点击状态栏菜单时也会立即刷新一次。

## 隐私边界

本项目只读取 Codex 本地日志里的官方 Usage 响应头，不访问浏览器 Cookie、不读取浏览器数据库、不读取 `auth.json`、不模拟登录、不上传用户数据。
