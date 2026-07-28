# CodexBuddy v0.7.3

v0.7.3 带来新的设置窗口、桌面悬浮用量和详细用量面板，并修复登录时启动与设置页切换体验。

## 主要变化

- 新增独立的毛玻璃设置窗口
- 新增点击展开的桌面悬浮用量组件
- 新增 Codex Token 使用详情面板
- 修复登录时启动开关状态同步，并支持跳转系统登录项设置
- 设置栏目切换保持固定窗口尺寸，避免窗口位置跳动
- 继续分别提供 Apple Silicon 与 Intel 安装包

## 验证

- 核心与打包自动测试通过
- Apple Silicon 与 Intel 独立构建通过
- DMG、ZIP 和 SHA-256 校验文件已生成

---

# CodexBuddy v0.7.2

v0.7.2 调整了 Dual Gauge 应用图标在 macOS 中的视觉尺寸。

## 主要变化

- 使用用户确认的新版 Dual Gauge 图标
- 增加透明安全边距，让图标在 Dock、Finder 和“应用程序”目录中保持合适尺寸
- 保留原始 SVG 作为矢量母版
- 继续分别提供 Apple Silicon 与 Intel 安装包

## 验证

- 核心与打包自动测试通过
- Apple Silicon 与 Intel 独立构建通过
- 两套应用签名、DMG、ZIP 和 SHA-256 校验通过
- 从最终 AppIcon.icns 反向提取 1024px 图标检查通过
