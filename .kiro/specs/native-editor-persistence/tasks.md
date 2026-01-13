# 实现计划：原生编辑器内容持久化

## 概述

本实现计划将原生编辑器的内容持久化功能分解为可执行的任务，确保原生编辑器具有与 Web 编辑器同等的数据持久化能力。

## 任务

- [x] 1. 修复 UnifiedEditorWrapper 中的内容变化处理
  - [x] 1.1 修复 handleNativeContentChange 方法，确保正确触发保存流程
    - 当前问题：原生编辑器内容变化后未正确触发 onContentChange 回调
    - 修复方案：确保 NSAttributedString 正确转换为 XML 并调用回调
    - _Requirements: 2.1_
  - [x] 1.2 添加内容变化防抖逻辑
    - 实现 300ms 防抖，避免频繁保存
    - _Requirements: 2.3_
  - [ ]* 1.3 编写单元测试验证内容变化处理
    - 测试内容变化时 XML 转换和回调触发
    - _Requirements: 2.1_

- [x] 2. 完善 NativeEditorContext 的内容管理
  - [x] 2.1 修复 exportToXML 方法
    - 确保使用最新的 nsAttributedText 进行转换
    - 处理空内容和特殊字符
    - _Requirements: 2.1, 5.1_
  - [x] 2.2 添加内容变化通知机制
    - 通过 contentChangeSubject 发布内容变化
    - 确保 hasUnsavedChanges 正确更新
    - _Requirements: 2.1, 6.1_
  - [ ]* 2.3 编写属性测试验证 XML 往返一致性
    - **Property 1: XML 往返一致性**
    - **Validates: Requirements 5.11**

- [x] 3. 检查点 - 确保基础保存流程正常
  - 确保所有测试通过，如有问题请询问用户

- [x] 4. 完善 XiaoMiFormatConverter 的格式转换
  - [x] 4.1 修复 nsAttributedStringToXML 方法中的格式标签生成
    - 确保粗体、斜体、下划线、删除线、高亮正确转换
    - 处理嵌套格式标签
    - _Requirements: 5.2, 5.3, 5.4, 5.5, 5.6_
  - [x] 4.2 修复标题格式的转换
    - 根据字体大小生成正确的标题标签
    - _Requirements: 5.7_
  - [x] 4.3 修复附件转换逻辑
    - 确保复选框、图片、音频附件正确转换
    - 保留所有必要属性（checked、fileId 等）
    - _Requirements: 5.8, 5.9, 5.10_
  - [ ]* 4.4 编写属性测试验证格式标签转换
    - **Property 2: 格式标签转换正确性**
    - **Validates: Requirements 5.2, 5.3, 5.4, 5.5, 5.6, 5.7**
  - [ ]* 4.5 编写属性测试验证附件转换
    - **Property 3: 附件转换正确性**
    - **Validates: Requirements 5.8, 5.9, 5.10, 8.4**

- [x] 5. 完善复选框状态保留
  - [x] 5.1 修复 processCheckboxElementToNSAttributedString 方法
    - 确保正确解析 checked 属性
    - 创建 InteractiveCheckboxAttachment 时传入正确的状态
    - _Requirements: 1.4, 5.8_
  - [x] 5.2 修复复选框导出逻辑
    - 确保导出时保留 checked 属性
    - _Requirements: 5.8_
  - [ ]* 5.3 编写属性测试验证复选框状态保留
    - **Property 4: 复选框状态保留**
    - **Validates: Requirements 1.4, 5.8**

- [ ] 6. 检查点 - 确保格式转换正常
  - 确保所有测试通过，如有问题请询问用户

- [x] 7. 完善 NoteDetailView 的保存流程
  - [x] 7.1 实现多层级保存策略
    - Tier 0: 立即更新内存缓存 (<1ms)
    - Tier 2: 异步保存到数据库 (防抖 300ms)
    - Tier 3: 调度云端同步 (延迟 3s)
    - _Requirements: 2.2, 2.3, 3.1_
  - [x] 7.2 修复笔记切换时的保存逻辑
    - 切换笔记前先保存当前内容
    - 防止内容丢失
    - _Requirements: 2.6_
  - [x] 7.3 修复文件夹切换时的保存逻辑
    - 通过 ViewStateCoordinator 的 saveContentCallback 触发保存
    - _Requirements: 2.7_
  - [ ]* 7.4 编写属性测试验证内存缓存更新
    - **Property 8: 内存缓存更新及时性**
    - **Validates: Requirements 2.2**

- [x] 8. 完善保存状态指示器
  - [x] 8.1 实现保存状态的正确更新
    - 内容变化时设置为 unsaved
    - 保存中设置为 saving
    - 保存完成设置为 saved
    - 保存失败设置为 error
    - _Requirements: 6.1, 6.2, 6.3, 6.4_
  - [x] 8.2 实现错误状态的详情显示
    - 点击错误状态可查看错误详情
    - _Requirements: 6.4_

- [x] 9. 完善错误处理和内容保护
  - [x] 9.1 实现保存失败时的内容保护
    - 保存失败时保留编辑内容在内存中
    - 提供重试选项
    - _Requirements: 2.5, 9.1_
  - [x] 9.2 实现格式转换失败的回退逻辑
    - 转换失败时记录日志并尝试使用原始内容
    - _Requirements: 9.3_
  - [ ]* 9.3 编写属性测试验证内容保护
    - **Property 5: 保存失败时内容保护**
    - **Validates: Requirements 2.5, 9.1**

- [ ] 10. 检查点 - 确保保存流程和错误处理正常
  - 确保所有测试通过，如有问题请询问用户

- [x] 11. 完善离线操作支持
  - [x] 11.1 实现离线时的操作队列添加
    - 网络不可用时将编辑操作加入离线队列
    - _Requirements: 4.1_
  - [x] 11.2 实现网络恢复时的队列处理
    - 按顺序处理离线队列中的操作
    - _Requirements: 4.3_
  - [x] 11.3 实现冲突解决策略
    - 使用时间戳比较策略解决冲突
    - _Requirements: 4.4_
  - [ ]* 11.4 编写属性测试验证离线队列顺序
    - **Property 6: 离线队列操作顺序**
    - **Validates: Requirements 4.3**
  - [ ]* 11.5 编写属性测试验证冲突解决
    - **Property 7: 冲突解决策略**
    - **Validates: Requirements 4.4**

- [ ] 12. 完善编辑器切换逻辑
  - [ ] 12.1 修复从 Web 编辑器切换到原生编辑器的内容同步
    - 保存 Web 编辑器内容并在原生编辑器中加载
    - _Requirements: 7.1_
  - [ ] 12.2 修复从原生编辑器切换到 Web 编辑器的内容同步
    - 导出原生编辑器 XML 并在 Web 编辑器中加载
    - _Requirements: 7.2_
  - [ ] 12.3 确保切换时保持笔记选中状态
    - _Requirements: 7.3_
  - [ ] 12.4 确保切换时注册正确的格式提供者
    - _Requirements: 7.4_

- [ ] 13. 完善录音模板支持
  - [ ] 13.1 修复录音模板插入逻辑
    - 确保占位符正确插入
    - _Requirements: 8.1_
  - [ ] 13.2 修复录音模板更新逻辑
    - 确保占位符正确更新为实际音频附件
    - _Requirements: 8.2_
  - [ ] 13.3 确保录音更新后立即保存
    - _Requirements: 8.3_

- [ ] 14. 最终检查点 - 确保所有功能正常
  - 确保所有测试通过，如有问题请询问用户

## 注意事项

- 任务标记 `*` 的为可选测试任务，可以跳过以加快 MVP 开发
- 每个属性测试需要引用设计文档中的属性编号
- 检查点任务用于验证阶段性成果
