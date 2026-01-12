# 设计文档

## 概述

本设计实现将录音功能从"内嵌在笔记内容中显示"改为"四栏式布局"。当用户触发录音或播放音频时，主窗口右侧会显示第四栏音频面板，提供独立的录制和播放界面，类似 Apple Notes 的设计。

## 架构

### 整体架构

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           MainWindowController                           │
├─────────────────────────────────────────────────────────────────────────┤
│  NSSplitViewController                                                   │
│  ┌──────────┬──────────────┬─────────────────┬─────────────────────────┐│
│  │ 侧边栏   │  笔记列表    │    编辑器       │     音频面板（可选）    ││
│  │ 180-300  │  200-350     │    400+         │     280-400             ││
│  │          │              │                 │                         ││
│  │ Sidebar  │ NotesList    │  NoteDetail     │   AudioPanel            ││
│  │ Hosting  │ Hosting      │  Hosting        │   Hosting               ││
│  │ Controller│ Controller  │  Controller     │   Controller            ││
│  └──────────┴──────────────┴─────────────────┴─────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### 状态管理

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AudioPanelStateManager                            │
├─────────────────────────────────────────────────────────────────────────┤
│  - isVisible: Bool                                                       │
│  - mode: AudioPanelMode (.recording, .playback)                         │
│  - recordingState: RecordingState                                        │
│  - playbackState: PlaybackState                                          │
│  - currentFileId: String?                                                │
│  - currentNoteId: String?                                                │
├─────────────────────────────────────────────────────────────────────────┤
│  + showForRecording()                                                    │
│  + showForPlayback(fileId: String)                                       │
│  + hide()                                                                │
│  + canClose() -> Bool                                                    │
└─────────────────────────────────────────────────────────────────────────┘
```

## 组件和接口

### 1. AudioPanelStateManager

音频面板状态管理器，负责管理面板的显示/隐藏状态和当前模式。

```swift
/// 音频面板状态管理器
/// 
/// 负责管理音频面板的显示状态、模式和与其他组件的协调
/// 
/// Requirements: 1.1, 1.3, 2.1, 2.2, 2.3, 5.1
@MainActor
class AudioPanelStateManager: ObservableObject {
    
    /// 面板模式
    enum Mode {
        case recording  // 录制模式
        case playback   // 播放模式
    }
    
    /// 面板是否可见
    @Published private(set) var isVisible: Bool = false
    
    /// 当前模式
    @Published private(set) var mode: Mode = .recording
    
    /// 当前播放的文件 ID（播放模式）
    @Published private(set) var currentFileId: String?
    
    /// 当前关联的笔记 ID
    @Published private(set) var currentNoteId: String?
    
    /// 录制服务引用
    private let recorderService: AudioRecorderService
    
    /// 播放服务引用
    private let playerService: AudioPlayerService
    
    /// 显示面板进入录制模式
    /// - Parameter noteId: 当前笔记 ID
    func showForRecording(noteId: String)
    
    /// 显示面板进入播放模式
    /// - Parameters:
    ///   - fileId: 音频文件 ID
    ///   - noteId: 当前笔记 ID
    func showForPlayback(fileId: String, noteId: String)
    
    /// 隐藏面板
    /// - Returns: 是否成功隐藏（录制中可能需要确认）
    func hide() -> Bool
    
    /// 检查是否可以安全关闭
    /// - Returns: 是否可以关闭（录制中返回 false）
    func canClose() -> Bool
    
    /// 处理笔记切换
    /// - Parameter newNoteId: 新笔记 ID
    /// - Returns: 是否允许切换（录制中可能需要确认）
    func handleNoteSwitch(to newNoteId: String) -> Bool
}
```

### 2. AudioPanelView

音频面板 SwiftUI 视图，根据模式显示录制或播放界面。

```swift
/// 音频面板视图
/// 
/// 显示在主窗口第四栏，提供录制和播放功能
/// 
/// Requirements: 1.1, 3.1, 4.1, 6.1, 6.2, 6.5
struct AudioPanelView: View {
    
    @ObservedObject var stateManager: AudioPanelStateManager
    @ObservedObject var recorderService: AudioRecorderService
    @ObservedObject var playerService: AudioPlayerService
    
    /// 录制完成回调
    let onRecordingComplete: (URL) -> Void
    
    /// 关闭回调
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            panelHeader
            
            Divider()
            
            // 内容区域（根据模式切换）
            switch stateManager.mode {
            case .recording:
                recordingContent
            case .playback:
                playbackContent
            }
        }
        .frame(minWidth: 280, maxWidth: 400)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
```

### 3. AudioPanelHostingController

AppKit 托管控制器，用于将 SwiftUI 视图嵌入 NSSplitViewController。

```swift
/// 音频面板托管控制器
/// 
/// 将 AudioPanelView 嵌入 NSSplitViewController
/// 
/// Requirements: 1.1, 1.2
class AudioPanelHostingController: NSHostingController<AudioPanelView> {
    
    private let stateManager: AudioPanelStateManager
    private let viewModel: NotesViewModel
    
    init(stateManager: AudioPanelStateManager, viewModel: NotesViewModel)
}
```

### 4. MainWindowController 扩展

扩展主窗口控制器以支持四栏布局。

```swift
extension MainWindowController {
    
    /// 音频面板状态管理器
    private var audioPanelStateManager: AudioPanelStateManager
    
    /// 显示音频面板
    /// - Parameter mode: 面板模式
    /// Requirements: 1.1, 1.2
    func showAudioPanel(mode: AudioPanelStateManager.Mode, fileId: String? = nil)
    
    /// 隐藏音频面板
    /// Requirements: 1.3, 2.3
    func hideAudioPanel()
    
    /// 更新布局以显示/隐藏第四栏
    /// Requirements: 1.2, 1.5
    private func updateLayoutForAudioPanel(visible: Bool)
}
```

## 数据模型

### AudioPanelState

```swift
/// 音频面板状态
struct AudioPanelState {
    /// 是否可见
    var isVisible: Bool
    
    /// 当前模式
    var mode: AudioPanelStateManager.Mode
    
    /// 录制状态（录制模式）
    var recordingState: AudioRecorderService.RecordingState
    
    /// 播放状态（播放模式）
    var playbackState: AudioPlayerService.PlaybackState
    
    /// 当前文件 ID
    var currentFileId: String?
    
    /// 当前笔记 ID
    var currentNoteId: String?
}
```

## 正确性属性

*正确性属性是系统应该在所有有效执行中保持为真的特征或行为——本质上是关于系统应该做什么的形式化陈述。属性作为人类可读规范和机器可验证正确性保证之间的桥梁。*

### Property 1: 四栏布局切换一致性

*对于任意* 主窗口状态，当显示音频面板时，分割视图应包含四个子视图；当隐藏音频面板时，分割视图应恢复为三个子视图。

**Validates: Requirements 1.1, 1.3, 2.3**

### Property 2: 布局不变性

*对于任意* 音频面板显示/隐藏操作，前三栏（侧边栏、笔记列表、编辑器）的相对位置和最小/最大宽度约束应保持不变。

**Validates: Requirements 1.2**

### Property 3: 面板宽度约束

*对于任意* 音频面板实例，其宽度应始终在 280-400 像素范围内。

**Validates: Requirements 1.4**

### Property 4: 录制流程完整性

*对于任意* 录制会话，从开始录制到确认/取消的完整流程应正确更新状态：idle → recording → (paused) → preview → (confirmed/cancelled) → idle。

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

### Property 5: 播放流程完整性

*对于任意* 播放会话，从加载音频到播放完成的完整流程应正确更新状态和进度。

**Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

### Property 6: 笔记切换状态同步

*对于任意* 笔记切换操作，如果音频面板正在播放，应停止播放并关闭面板；如果正在录制，应显示确认对话框。

**Validates: Requirements 5.1, 5.2**

### Property 7: 音频附件插入一致性

*对于任意* 成功的录制确认操作，编辑器中应在光标位置插入对应的音频附件占位符。

**Validates: Requirements 5.3**

## 错误处理

### 录制错误

1. **麦克风权限被拒绝**
   - 显示权限提示对话框
   - 提供打开系统设置的选项
   - 面板保持显示但禁用录制按钮

2. **录制过程中断**
   - 保存已录制的内容
   - 显示错误提示
   - 允许用户预览已录制部分或重新录制

3. **存储空间不足**
   - 停止录制
   - 显示错误提示
   - 保存已录制的内容

### 播放错误

1. **音频文件不存在**
   - 显示错误提示
   - 关闭面板
   - 从笔记中移除无效附件引用

2. **解密失败**
   - 显示错误提示
   - 提供重试选项

3. **网络错误（云端音频）**
   - 显示离线提示
   - 提供稍后重试选项

### 状态同步错误

1. **笔记切换时录制未保存**
   - 显示确认对话框
   - 提供保存、放弃、取消选项

2. **面板关闭时录制未保存**
   - 显示确认对话框
   - 提供保存、放弃、取消选项

## 测试策略

### 单元测试

1. **AudioPanelStateManager 测试**
   - 测试状态转换逻辑
   - 测试 canClose() 在各种状态下的返回值
   - 测试 handleNoteSwitch() 的行为

2. **布局计算测试**
   - 测试四栏布局的宽度分配
   - 测试窗口缩小时的压缩优先级

### 属性测试

使用 Swift 的 XCTest 框架进行属性测试，每个属性测试至少运行 100 次迭代。

1. **Property 1 测试**: 生成随机的显示/隐藏序列，验证分割视图子视图数量
2. **Property 2 测试**: 生成随机的面板操作，验证前三栏布局不变
3. **Property 4 测试**: 生成随机的录制操作序列，验证状态转换正确性
4. **Property 5 测试**: 生成随机的播放操作序列，验证状态和进度更新
5. **Property 6 测试**: 生成随机的笔记切换场景，验证面板状态同步

### 集成测试

1. **完整录制流程测试**
   - 打开面板 → 录制 → 暂停 → 继续 → 停止 → 预览 → 确认
   - 验证音频附件正确插入笔记

2. **完整播放流程测试**
   - 点击音频附件 → 打开面板 → 播放 → 暂停 → 跳转 → 播放完成
   - 验证播放状态正确更新

3. **笔记切换测试**
   - 在播放/录制状态下切换笔记
   - 验证确认对话框和状态清理
