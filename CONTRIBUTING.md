# 贡献指南

感谢你对 MiNoteMac 项目的关注。在提交贡献之前，请阅读以下说明。

## 项目性质

本项目是个人学习和研究项目，仅供学习使用，不用于商业目的。

## 基本要求

- 你确认你有权提交该贡献
- 你同意本项目的许可证（MIT）
- 如提交中包含第三方代码或资源，请在 PR 描述中注明来源与许可证

## 开发环境

- macOS 15.0+
- Xcode 15.0+
- Swift 6.0

## 构建与测试

提交 PR 前请确保以下命令通过：

```bash
# 生成 Xcode 项目
xcodegen generate

# 构建项目
xcodebuild -project MiNoteMac.xcodeproj -scheme MiNoteMac -configuration Debug

# 运行测试
xcodebuild test -project MiNoteMac.xcodeproj -scheme MiNoteMac -destination 'platform=macOS'
```

## 代码规范

### 禁止事项

- 禁止在代码、注释、控制台输出中使用 emoji
- 禁止添加过多解释性注释
- 禁止提交敏感信息（Cookie、密钥等）
- 禁止提交构建产物

### 注释规范

- 只在复杂逻辑处添加注释
- 注释使用中文
- 避免注释描述"做什么"，而应描述"为什么"

### 命名规范

- 类型名使用 PascalCase
- 变量和函数名使用 camelCase
- 文件名与主要类型名一致

## Git 提交规范

```
<type>(<scope>): <subject>
```

类型：feat, fix, refactor, perf, style, docs, test, chore, revert

示例：
- `feat(editor): 添加原生富文本编辑器支持`
- `fix(sync): 修复离线操作队列重复执行问题`

## 贡献流程

1. Fork 仓库并创建分支
2. 完成修改并确保编译通过
3. 提交 PR，并在描述中说明变更内容

## 注意事项

- 本项目不依赖外部开源库
- 修改 `project.yml` 后必须执行 `xcodegen generate`
- 大型任务拆分为多个小提交
- 每个提交应该是可编译、可运行的状态
