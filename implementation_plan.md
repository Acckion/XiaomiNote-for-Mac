# Implementation Plan

重构MiNote for Mac同步系统，优化数据库结构，并确保三种同步类型清晰分离且能正确保存syncTag。

## [Overview]
本计划旨在重构MiNote for Mac的同步系统，解决当前同步功能混乱的问题，并优化数据库结构。根据技术文档，同步系统应清晰分离三种同步类型：完整同步、增量同步和轻量级增量同步。同时，需要修复数据库中的tags字段存储问题，移除无用字段，并确保所有同步方式都能正确保存syncTag。

**范围**：重构SyncService以清晰分离三种同步类型，优化DatabaseService以修复tags字段和移除无用字段，更新相关模型和存储逻辑。

**上下文**：当前SyncService实现了三种同步类型但逻辑有重叠，DatabaseService中的notes表有tags字段但无法存入数据，且存在无用字段需要清理。sync_status表需要简化。

**高级方法**：1) 重构SyncService，按照技术文档清晰定义三种同步类型；2) 修复DatabaseService中的tags字段存储；3) 移除无用数据库字段；4) 简化sync_status表；5) 确保所有同步路径都能正确保存syncTag。

## [Types]
同步系统类型定义和数据结构优化。

**SyncStatus结构优化**：
```swift
struct SyncStatus: Codable {
    var lastSyncTime: Date?      // 上次同步时间
    var syncTag: String?         // 同步标记（用于增量同步）
    // 移除 lastPageSyncTime 字段
}
```

**Note模型优化**：
```swift
struct Note: Identifiable, Codable, Hashable, @unchecked Sendable {
    public let id: String
    public var title: String
    public var content: String
    public var folderId: String
    public var isStarred: Bool = false
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String] = []  // 修复存储问题
    // 移除 htmlContent 字段
    public var rawData: [String: Any]?  // 保留，但确保不包含无用备份数据
}
```

**数据库字段变更**：
- notes表：修复tags字段存储，移除html_content字段，移除raw_data_backup字段
- sync_status表：移除last_page_sync_time字段

## [Files]
文件修改详细清单。

**新文件创建**：
- 无新文件创建，所有修改在现有文件基础上进行

**现有文件修改**：

1. **Sources/Service/SyncService.swift** - 同步服务重构
   - 清晰分离三种同步类型：performFullSync, performIncrementalSync, performLightweightIncrementalSync
   - 确保每种同步类型都能正确提取和保存syncTag
   - 移除重复逻辑，统一syncTag提取和保存机制
   - 更新冲突解决策略，遵循技术文档的时间戳比较策略

2. **Sources/Service/DatabaseService.swift** - 数据库服务优化
   - 修复saveNote方法中的tags字段存储问题
   - 移除notes表中的html_content字段相关代码
   - 移除raw_data_backup字段相关代码
   - 修改sync_status表结构，移除last_page_sync_time字段
   - 更新数据库迁移逻辑

3. **Sources/Service/LocalStorageService.swift** - 本地存储服务更新
   - 更新SyncStatus结构定义，移除lastPageSyncTime字段
   - 更新saveSyncStatus和loadSyncStatus方法

4. **Sources/Model/Note.swift** - Note模型优化
   - 移除htmlContent字段
   - 修复tags字段的编码/解码逻辑
   - 更新toMinoteData和fromMinoteData方法

5. **Sources/ViewModel/NotesViewModel.swift** - 视图模型更新
   - 更新与Note模型相关的代码，移除htmlContent引用
   - 确保tags字段能正确显示

6. **Sources/View/SwiftUIViews/NoteDetailView.swift** - 笔记详情视图更新
   - 移除对htmlContent的依赖
   - 更新内容加载逻辑

**文件删除**：
- 无文件删除，仅字段移除

**配置文件更新**：
- 无配置文件需要更新

## [Functions]
函数修改详细清单。

**新函数**：
- SyncService.swift: 添加清晰的syncTag提取和验证函数
- DatabaseService.swift: 添加数据库迁移函数，处理字段移除

**修改函数**：

1. **SyncService.performFullSync()** - 完整同步
   - 确保清除所有本地数据后重新拉取
   - 正确提取和保存syncTag
   - 遵循技术文档的完整同步流程

2. **SyncService.performIncrementalSync()** - 增量同步
   - 重构为清晰的增量同步逻辑
   - 使用syncTag获取自上次同步以来的更改
   - 正确处理冲突解决（时间戳比较策略）
   - 确保保存新的syncTag

3. **SyncService.performLightweightIncrementalSync()** - 轻量级增量同步
   - 优化现有实现，确保高效性
   - 只同步有修改的条目
   - 支持删除操作同步
   - 确保保存新的syncTag

4. **SyncService.extractSyncTags(from:)** - syncTag提取
   - 统一和优化syncTag提取逻辑
   - 支持多种API响应格式
   - 添加更健壮的错误处理

5. **DatabaseService.saveNote(_:)** - 笔记保存
   - 修复tags字段的JSON编码存储
   - 移除html_content字段的存储
   - 移除raw_data_backup字段的存储

6. **DatabaseService.parseNote(from:)** - 笔记解析
   - 修复tags字段的JSON解码
   - 移除html_content字段的解析
   - 移除raw_data_backup字段的解析

7. **DatabaseService.saveSyncStatus(_:)** - 同步状态保存
   - 移除last_page_sync_time字段的保存
   - 更新数据库表结构

8. **DatabaseService.loadSyncStatus()** - 同步状态加载
   - 移除last_page_sync_time字段的加载
   - 更新数据库查询

**移除函数**：
- DatabaseService.migrateNotesTable()中的html_content和raw_data_backup相关代码
- 所有与htmlContent字段相关的辅助函数

## [Classes]
类修改详细清单。

**新类**：
- 无新类创建

**修改类**：

1. **SyncService类** - 同步服务主类
   - 重构三种同步方法的实现
   - 添加清晰的同步状态管理
   - 统一syncTag处理逻辑
   - 优化错误处理和重试机制

2. **DatabaseService类** - 数据库服务类
   - 更新表结构创建逻辑
   - 修复tags字段存储
   - 移除无用字段处理
   - 更新数据库迁移逻辑

3. **LocalStorageService类** - 本地存储服务类
   - 更新SyncStatus结构
   - 移除lastPageSyncTime相关逻辑

4. **Note结构体** - 笔记数据模型
   - 移除htmlContent字段
   - 修复tags字段编码/解码
   - 更新相等性比较和哈希计算

**移除类**：
- 无类移除

## [Dependencies]
依赖修改详细清单。

**新包依赖**：
- 无新包依赖

**现有依赖更新**：
- 无依赖版本更新

**集成要求**：
- 确保所有同步类型都能与小米笔记API正确交互
- 保持与现有文件系统和网络层的兼容性
- 由于是开发阶段，可以直接使用新数据库结构

## [Testing]
测试策略和方法。

**测试文件要求**：
- 更新现有单元测试，适应修改后的接口
- 添加同步类型测试，验证三种同步类型的正确性
- 添加数据库迁移测试，验证字段移除不影响现有数据
- 添加tags字段存储测试，验证修复效果

**现有测试修改**：
- 更新Note模型的单元测试，移除htmlContent相关测试
- 更新DatabaseService的单元测试，验证tags字段存储
- 更新SyncService的单元测试，验证三种同步类型

**验证策略**：
1. 单元测试：覆盖所有修改的函数和类
2. 集成测试：验证同步功能端到端工作正常
3. 数据库结构测试：验证新表结构正确
4. 性能测试：验证同步性能不受影响

## [Implementation Order]
实现步骤顺序。

1. **第一步：数据库结构优化**
   - 修改DatabaseService，移除html_content和raw_data_backup字段
   - 修改sync_status表，移除last_page_sync_time字段
   - 直接更新表创建语句，无需迁移脚本
   - 测试新数据库结构

2. **第二步：数据模型更新**
   - 修改Note模型，移除htmlContent字段
   - 修复tags字段的编码/解码逻辑
   - 更新相关视图模型和视图

3. **第三步：同步服务重构**
   - 重构SyncService，清晰分离三种同步类型
   - 统一syncTag提取和保存逻辑
   - 确保所有同步路径都能正确保存syncTag
   - 更新冲突解决策略

4. **第四步：集成测试**
   - 测试三种同步类型的正确性
   - 验证tags字段能正确存储和读取
   - 验证新数据库结构正常工作
   - 性能测试和回归测试

5. **第五步：文档和清理**
   - 更新代码注释和文档
   - 清理无用代码和注释
   - 最终验证和代码审查

**关键路径**：
1. 数据库结构优化可以直接进行，无需考虑数据迁移
2. 数据模型更新必须在同步服务重构之前完成
3. 同步服务重构是核心，需要充分测试
4. 集成测试确保整体功能正常

**风险缓解**：
- 由于程序在开发阶段，可以直接创建新数据库，无需考虑数据迁移
- 分阶段实施，每阶段充分测试
- 简化实现，专注于核心功能
- 详细记录变更，便于问题排查
