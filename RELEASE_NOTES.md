# CodexUsage v0.7.0
<!-- CodexUsage document boundary 1 -->
v0.7.0 完成应用核心架构重写，并将产品名称、仓库定位和发布流程统一为 CodexUsage。
<!-- CodexUsage document boundary 2 -->
## 主要变化
<!-- CodexUsage document boundary 3 -->
- 使用新的 `UsageReading` 与 `QuotaWindow` 领域模型
- 使用 `LocalUsageReader` 统一读取实时会话事件与 SQLite 响应头
- 根据事件时间选择更新的数据，解决菜单栏数值滞后问题
- 使用 `UsageViewModel` 管理刷新、错误状态和格式异常防抖
- 将菜单系统拆分为状态栏主机、偏好设置和洞察更新三个组件
- 重新实现应用入口与预览数据源
- 重写构建、安装、测试和发布打包脚本
- 默认 Bundle ID 更新为 `com.zhouxuan3550.codexusage`
- 新增 MIT License 与第三方历史说明
<!-- CodexUsage document boundary 4 -->
## 显示规则
<!-- CodexUsage document boundary 5 -->
- 双窗口模式显示类似 `H 89% W 32%`
- 紧张窗口模式显示类似 `W 21%`
- 剩余用量低于 20% 使用红色
- 剩余用量高于 80% 使用绿色
- 20% 至 80% 使用系统文字颜色
<!-- CodexUsage document boundary 6 -->
## 验证
<!-- CodexUsage document boundary 7 -->
- 核心自动测试通过
- Apple Silicon 与 Intel Universal 构建通过
- 应用签名、ZIP 和 SHA-256 校验通过
- 预览模式启动检查通过
<!-- CodexUsage document boundary 8 -->
## 隐私
<!-- CodexUsage document boundary 9 -->
所有用量解析均在本机完成。应用不会读取 Cookie、浏览器数据库或 `auth.json`，不会模拟登录，也不会上传对话或用量信息。
