# Git 提交规范

## 提交信息格式

```
<type>(<scope>): <subject>

<body>
```

## 类型（type）

- `feat`: 新功能
- `fix`: 修复 bug
- `refactor`: 代码重构（不影响功能）
- `perf`: 性能优化
- `style`: 代码格式调整（不影响逻辑）
- `docs`: 文档更新
- `test`: 测试相关
- `chore`: 构建、配置等杂项
- `revert`: 回滚提交

## 作用域（scope）可选

常用作用域：
- `editor`: 编辑器相关
- `sync`: 同步功能
- `api`: API 服务
- `db`: 数据库
- `ui`: 界面组件
- `window`: 窗口管理
- `toolbar`: 工具栏
- `format`: 格式化功能

## 提交示例

```
feat(editor): 添加原生富文本编辑器支持

fix(sync): 修复离线操作队列重复执行问题

refactor(api): 重构网络请求错误处理逻辑

docs: 更新技术文档
```

## 分支管理

- `main`: 主分支，保持稳定
- `develop`: 开发分支
- `feature/*`: 功能分支
- `fix/*`: 修复分支

## 提交频率

- 完成一个独立功能或修复后立即提交
- 大型任务拆分为多个小提交
- 每个提交应该是可编译、可运行的状态

## 注意事项

- 提交前确保代码可以编译通过
- 不要提交 `.build/`、`build/` 等构建产物
- 敏感信息（Cookie、密钥等）不要提交
