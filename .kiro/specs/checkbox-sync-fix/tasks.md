# 实现计划：复选框同步修复

## 概述

本任务列表描述了修复原生编辑器中复选框同步问题的实现步骤。核心改动是将 `processCheckboxElement` 和 `processCheckboxElementToNSAttributedString` 方法从使用 Unicode 字符改为使用 `InteractiveCheckboxAttachment`。

## 任务

- [x] 1. 修复复选框 XML 解析方法
  - [x] 1.1 修改 processCheckboxElementToNSAttributedString 方法
    - 使用 CustomRenderer.shared.createCheckboxAttachment() 创建复选框附件
    - 提取 indent 和 level 属性并设置到附件
    - 将复选框后的文本内容追加到 NSAttributedString
    - 设置正确的段落样式
    - _需求: 1.1, 1.2, 1.3_

  - [x] 1.2 修改 processCheckboxElement 方法
    - 调用 processCheckboxElementToNSAttributedString 并转换为 AttributedString
    - 保持向后兼容性
    - _需求: 1.1_

- [ ]* 1.3 编写属性测试验证解析正确性
  - **Property 1: 复选框解析正确性**
  - 验证解析后的附件类型为 InteractiveCheckboxAttachment
  - 验证 indent 和 level 属性正确
  - 验证文本内容正确追加
  - **Validates: Requirements 1.1, 1.2, 1.3**

- [x] 2. 修复复选框 XML 导出方法
  - [x] 2.1 修改 convertNSLineToXML 方法
    - 检测 InteractiveCheckboxAttachment 类型的附件
    - 生成正确的复选框 XML 格式
    - 将附件后的文本内容追加到 XML
    - _需求: 2.1, 2.2, 2.3, 2.4_

- [ ]* 2.2 编写属性测试验证导出正确性
  - **Property 2: 复选框导出正确性**
  - 验证导出的 XML 格式正确
  - 验证 indent 和 level 属性正确
  - 验证文本内容正确追加
  - **Validates: Requirements 2.1, 2.2, 2.3, 2.4**

- [ ] 3. 验证往返转换一致性
  - [ ]* 3.1 编写属性测试验证往返转换
    - **Property 3: 复选框往返转换一致性**
    - 生成随机复选框 XML
    - 解析后导出
    - 验证结果与原始 XML 等价
    - **Validates: Requirements 3.1**

- [ ] 4. 验证选中状态处理
  - [ ]* 4.1 编写属性测试验证选中状态不影响导出
    - **Property 4: 选中状态不影响导出**
    - 创建选中和未选中状态的复选框
    - 验证导出的 XML 格式相同
    - **Validates: Requirements 4.5**

- [x] 5. Checkpoint - 确保所有测试通过
  - 运行所有单元测试和属性测试
  - 确保没有回归问题
  - 如有问题，询问用户

- [ ] 6. 集成测试
  - [ ] 6.1 测试从小米笔记同步的复选框显示
    - 验证复选框正确显示为可交互图标
    - 验证点击可以切换选中状态
    - _需求: 1.4, 4.1, 4.2, 4.3, 4.4_

  - [ ] 6.2 测试编辑后同步回小米笔记
    - 验证复选框正确导出为 XML 格式
    - 验证同步后在其他设备上显示正确
    - _需求: 2.1, 3.1_

- [ ] 7. Final Checkpoint - 确保所有测试通过
  - 运行完整测试套件
  - 验证功能正常工作
  - 如有问题，询问用户

## 注意事项

- 任务标记 `*` 的为可选测试任务，可以跳过以加快 MVP 开发
- 每个任务都引用了具体的需求以便追溯
- Checkpoint 任务用于确保增量验证
- 属性测试验证通用正确性属性
