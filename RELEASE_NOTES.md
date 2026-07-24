# CodexBuddy v0.7.1

v0.7.1 是一次视觉与发布可靠性更新。

## 主要变化

- 应用图标更换为全新的 **Dual Gauge / 01 · PRECISE** 方案
- 使用双层仪表弧表达短时窗口与每周窗口
- 保留 Paper 导出的 SVG 矢量源文件，便于后续迭代
- “官方 Usage”菜单打开 OpenAI 当前 Usage 页面
- 自动更新会根据 Mac 架构选择对应的 arm64 或 x86_64 安装包

## 验证

- 核心与打包自动测试通过
- Apple Silicon 与 Intel 独立构建通过
- 两套应用签名、DMG、ZIP 和 SHA-256 校验通过
- 最终 AppIcon.icns 已从新图标生成并反向提取检查

## 隐私

所有用量解析仍在本机完成。应用不会读取 Cookie、浏览器数据库或 `auth.json`，不会模拟登录，也不会上传对话或用量信息。
