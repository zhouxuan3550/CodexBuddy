# CodexUsageBar

macOS 顶部菜单栏 Codex Usage 极简显示器。

当前版本按需求文档的第一阶段实现，顶部状态栏使用系统原生字体显示：

- 菜单栏常驻显示：`h89 w32`
- 点击显示 Usage 详情
- 支持手动刷新
- 支持打开官方 Usage 页面
- 支持退出
- 使用 `MockUsageProvider`，不读取 Cookie、不读取浏览器数据库、不要求输入密码、不上传任何信息

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

第一版使用固定 Mock 数据，菜单栏会简化显示为 `h89 w32`：

```text
5 小时 89% · 23:31
1 周 32% · 6月26日
```

`CodexUsageProvider` 已预留真实数据源入口；在没有稳定官方 API、CLI 输出或官方本地状态文件前，它会返回“当前没有可用的官方 Usage 数据源”。后续接入真实数据时，应只使用官方可读接口或官方本地状态，不抓取浏览器 Cookie，不模拟登录，不读取浏览器数据库。

## 打包发布

```bash
./scripts/package.sh
```

发布包会生成到：

```text
build/CodexUsageBar-v0.1.0.zip
```

## 隐私边界

本项目当前只展示 Mock 数据，不访问浏览器 Cookie、不读取浏览器数据库、不模拟登录、不上传用户数据。
