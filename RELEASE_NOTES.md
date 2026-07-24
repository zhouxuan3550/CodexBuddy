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
