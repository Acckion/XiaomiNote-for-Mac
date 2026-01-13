//
//  UnifiedEditorWrapper.swift
//  MiNoteMac
//
//  统一编辑器包装器 - 支持在原生编辑器和 Web 编辑器之间切换
//  需求: 1.2, 1.3
//

import SwiftUI
import Combine

/// 统一编辑器包装器
/// 根据用户偏好设置自动选择原生编辑器或 Web 编辑器
@available(macOS 14.0, *)
struct UnifiedEditorWrapper: View {
    
    // MARK: - Properties
    
    /// XML 内容绑定
    @Binding var content: String
    
    /// 是否可编辑
    @Binding var isEditable: Bool
    
    /// Web 编辑器上下文（用于 Web 编辑器）
    @ObservedObject var webEditorContext: WebEditorContext
    
    /// 原生编辑器上下文（用于原生编辑器）- 从外部传入以确保工具栏和编辑器使用同一个上下文
    @ObservedObject var nativeEditorContext: NativeEditorContext
    
    /// 笔记原始数据（用于 Web 编辑器）
    let noteRawData: String?
    
    /// XML 内容（用于初始化）
    let xmlContent: String?
    
    /// 当前文件夹 ID（用于图片存储）
    let folderId: String?
    
    /// 内容变化回调
    let onContentChange: (String, String?) -> Void
    
    // MARK: - State
    
    /// 编辑器偏好设置服务 - 使用 @ObservedObject 因为是单例
    @ObservedObject private var preferencesService = EditorPreferencesService.shared
    
    /// 是否正在切换编辑器
    @State private var isSwitchingEditor: Bool = false
    
    /// 上次加载的内容（用于防止重复加载）
    @State private var lastLoadedContent: String = ""
    
    /// 是否是初始加载
    @State private var isInitialLoad: Bool = true
    
    /// 是否正在从外部更新内容（防止循环更新）
    @State private var isUpdatingFromExternal: Bool = false
    
    /// 内容变化防抖任务
    /// _Requirements: 2.3_ - 实现 300ms 防抖，避免频繁保存
    @State private var debounceTask: Task<Void, Never>? = nil
    
    /// 防抖延迟时间（毫秒）
    /// _Requirements: 2.3_
    private let debounceDelayMs: UInt64 = 300
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
                nativeEditorView
            } else {
                webEditorView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupEditor()
        }
        .onChange(of: content) { oldValue, newValue in
            handleContentChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: preferencesService.selectedEditorType) { oldValue, newValue in
            handleEditorTypeChange(from: oldValue, to: newValue)
        }
        // 监听 xmlContent 变化来检测笔记切换（最可靠的方式）
        .onChange(of: xmlContent) { oldValue, newValue in
            handleXMLContentChange(oldValue: oldValue, newValue: newValue)
        }
        // 监听 folderId 变化来检测跨文件夹笔记切换
        .onChange(of: folderId) { oldValue, newValue in
            handleFolderIdChange(oldValue: oldValue, newValue: newValue)
        }
    }
    
    // MARK: - Native Editor View
    
    @ViewBuilder
    private var nativeEditorView: some View {
        NativeEditorView(
            editorContext: nativeEditorContext,
            onContentChange: { attributedString in
                handleNativeContentChange(attributedString)
            },
            onSelectionChange: { range in
                Task { @MainActor in
                    nativeEditorContext.updateSelectedRange(range)
                }
            },
            isEditable: isEditable
        )
        .onAppear {
            setupNativeEditor()
        }
    }
    
    // MARK: - Web Editor View
    
    @ViewBuilder
    private var webEditorView: some View {
        WebEditorWrapper(
            content: $content,
            isEditable: $isEditable,
            editorContext: webEditorContext,
            noteRawData: noteRawData,
            xmlContent: xmlContent,
            onContentChange: onContentChange
        )
    }
    
    // MARK: - Setup Methods
    
    /// 设置编辑器
    private func setupEditor() {
        if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
            setupNativeEditor()
        }
        
        // 初始加载内容
        let contentToLoad = xmlContent ?? content
        if !contentToLoad.isEmpty {
            Task { @MainActor in
                lastLoadedContent = contentToLoad
                isInitialLoad = false
                print("[UnifiedEditorWrapper] 初始加载内容 - 长度: \(contentToLoad.count)")
            }
        } else {
            Task { @MainActor in
                isInitialLoad = false
            }
        }
    }
    
    /// 设置原生编辑器
    private func setupNativeEditor() {
        Task { @MainActor in
            // 设置文件夹 ID（用于图片存储）
            nativeEditorContext.currentFolderId = folderId
            
            // 加载 XML 内容到原生编辑器
            let contentToLoad = xmlContent ?? content
            if !contentToLoad.isEmpty {
                nativeEditorContext.loadFromXML(contentToLoad)
                lastLoadedContent = contentToLoad
                print("[UnifiedEditorWrapper] 原生编辑器加载内容 - 长度: \(contentToLoad.count)")
            }
        }
    }
    
    // MARK: - Content Change Handlers
    
    /// 处理 xmlContent 变化（切换笔记时触发）
    private func handleXMLContentChange(oldValue: String?, newValue: String?) {
        // xmlContent 变化是检测笔记切换最可靠的方式
        guard let newContent = newValue else { return }
        
        // 关键修复：移除过于严格的内容相同性检查
        // 只要 xmlContent 发生变化，就应该重新加载
        // 这确保笔记切换时内容一定会更新
        if newContent == oldValue {
            // 内容完全相同，不需要处理
            return
        }
        
        // 关键修复：检查是否是保存后的内容更新（而不是笔记切换）
        // 如果新内容与当前编辑器中的内容相同（或非常接近），说明这是保存后的更新
        // 不需要重新加载，避免触发 hasUnsavedChanges = true
        if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
            let currentEditorXML = nativeEditorContext.exportToXML()
            if !currentEditorXML.isEmpty && currentEditorXML == newContent {
                print("[UnifiedEditorWrapper] xmlContent 变化但与编辑器内容相同，跳过重新加载")
                // 更新 lastLoadedContent 以保持同步
                lastLoadedContent = newContent
                return
            }
        }
        
        print("[UnifiedEditorWrapper] xmlContent 变化（切换笔记）- 从长度 \(oldValue?.count ?? 0) 到 \(newContent.count)")
        
        Task { @MainActor in
            isUpdatingFromExternal = true
            
            // 关键修复：先更新 lastLoadedContent，再加载内容
            // 这样可以防止后续的 content 变化被误认为是用户编辑
            lastLoadedContent = newContent
            
            // 如果使用原生编辑器，强制重新加载内容
            if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
                nativeEditorContext.currentFolderId = folderId
                
                // 关键修复：先清空编辑器，再加载新内容
                // 这样可以避免旧内容残留
                if newContent.isEmpty {
                    nativeEditorContext.nsAttributedText = NSAttributedString()
                    print("[UnifiedEditorWrapper] 原生编辑器清空内容")
                } else {
                    nativeEditorContext.loadFromXML(newContent)
                    print("[UnifiedEditorWrapper] 原生编辑器重新加载内容 - 长度: \(newContent.count)")
                }
            }
            
            isUpdatingFromExternal = false
        }
    }
    
    /// 处理内容变化
    private func handleContentChange(oldValue: String, newValue: String) {
        guard oldValue != newValue else { return }
        guard !isUpdatingFromExternal else { return }
        
        // 关键修复：检查是否是新内容（不同于上次加载的内容）
        // 这通常发生在笔记切换时，content 绑定被外部更新
        if newValue != lastLoadedContent {
            print("[UnifiedEditorWrapper] content 变化 - 从长度 \(oldValue.count) 到 \(newValue.count), lastLoaded: \(lastLoadedContent.count)")
            
            Task { @MainActor in
                isUpdatingFromExternal = true
                
                // 关键修复：先更新 lastLoadedContent，再加载内容
                lastLoadedContent = newValue
                
                // 如果使用原生编辑器，同步内容
                if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
                    nativeEditorContext.currentFolderId = folderId
                    
                    // 关键修复：先清空编辑器，再加载新内容
                    if newValue.isEmpty {
                        nativeEditorContext.nsAttributedText = NSAttributedString()
                        print("[UnifiedEditorWrapper] 原生编辑器清空内容（从 content 绑定）")
                    } else {
                        nativeEditorContext.loadFromXML(newValue)
                        print("[UnifiedEditorWrapper] 原生编辑器从 content 绑定加载内容 - 长度: \(newValue.count)")
                    }
                }
                
                isUpdatingFromExternal = false
            }
        }
    }
    
    /// 处理原生编辑器内容变化
    /// _Requirements: 2.1_ - 确保 NSAttributedString 正确转换为 XML 并调用回调
    /// _Requirements: 2.3_ - 实现 300ms 防抖，避免频繁保存
    private func handleNativeContentChange(_ attributedString: NSAttributedString) {
        // 如果正在从外部更新内容，跳过处理
        guard !isUpdatingFromExternal else {
            print("[UnifiedEditorWrapper] handleNativeContentChange: 跳过（正在从外部更新）")
            return
        }
        
        // 关键修复：立即标记有未保存的更改
        // 这确保用户在输入时能看到"未保存"状态
        nativeEditorContext.hasUnsavedChanges = true
        
        // 取消之前的防抖任务
        debounceTask?.cancel()
        
        // 创建新的防抖任务
        // _Requirements: 2.3_ - 300ms 防抖
        debounceTask = Task { @MainActor in
            do {
                // 等待防抖延迟
                try await Task.sleep(nanoseconds: debounceDelayMs * 1_000_000)
                
                // 检查任务是否被取消
                try Task.checkCancellation()
                
                // 关键修复：使用 nativeEditorContext.nsAttributedText 获取最新内容
                // 而不是使用防抖任务创建时捕获的旧内容
                // 这确保保存的是用户最新输入的内容
                let latestContent = nativeEditorContext.nsAttributedText
                
                // 执行实际的内容变化处理
                await performContentChange(latestContent)
            } catch is CancellationError {
                // 任务被取消，这是正常的防抖行为
                print("[UnifiedEditorWrapper] handleNativeContentChange: 防抖任务被取消")
            } catch {
                print("[UnifiedEditorWrapper] handleNativeContentChange: 错误 - \(error)")
            }
        }
    }
    
    /// 执行实际的内容变化处理
    /// _Requirements: 2.1_ - 将 NSAttributedString 转换为 XML 格式并触发保存流程
    /// _Requirements: 9.3_ - 格式转换失败时记录日志并尝试使用原始内容
    private func performContentChange(_ attributedString: NSAttributedString) async {
        // 关键修复：直接使用传入的 attributedString 进行转换
        // 而不是依赖 nativeEditorContext.nsAttributedText
        // 因为 nsAttributedText 可能还没有被更新（异步更新）
        
        // _Requirements: 9.3_ - 使用安全转换方法，确保即使转换失败也能保存内容
        let xmlContent = XiaoMiFormatConverter.shared.safeNSAttributedStringToXML(attributedString)
        
        // 检查转换结果
        if xmlContent.isEmpty && attributedString.length > 0 {
            print("[UnifiedEditorWrapper] performContentChange: ⚠️ 转换结果为空，但原始内容不为空")
            print("[UnifiedEditorWrapper]   - 原始内容长度: \(attributedString.length)")
            print("[UnifiedEditorWrapper]   - 原始内容预览: \(attributedString.string.prefix(100))...")
            // 不触发保存，保留用户编辑的内容在内存中
            return
        }
        
        print("[UnifiedEditorWrapper] performContentChange: XML 转换成功 - 长度: \(xmlContent.count)")
        
        // 关键修复：即使 XML 内容相同，也要检查是否需要触发保存
        // 因为格式变化可能不会改变 XML 字符串，但仍需要保存
        let contentChanged = xmlContent != content
        let hasUnsavedChanges = nativeEditorContext.hasUnsavedChanges
        
        if contentChanged || hasUnsavedChanges {
            isUpdatingFromExternal = true
            
            // 更新绑定的内容
            content = xmlContent
            lastLoadedContent = xmlContent
            
            isUpdatingFromExternal = false
            
            // 调用内容变化回调（原生编辑器不提供 HTML 缓存）
            // _Requirements: 2.1_ - 触发保存流程
            onContentChange(xmlContent, nil)
            
            print("[UnifiedEditorWrapper] performContentChange: 已触发保存回调 - contentChanged: \(contentChanged), hasUnsavedChanges: \(hasUnsavedChanges)")
        } else {
            print("[UnifiedEditorWrapper] performContentChange: 内容未变化，跳过保存")
        }
    }
    
    /// 处理编辑器类型变化
    private func handleEditorTypeChange(from oldType: EditorType, to newType: EditorType) {
        guard oldType != newType else { return }
        
        print("[UnifiedEditorWrapper] 编辑器类型变化: \(oldType.displayName) -> \(newType.displayName)")
        
        Task { @MainActor in
            isSwitchingEditor = true
            isUpdatingFromExternal = true
            
            // 保存当前内容
            let currentContent: String
            if oldType == .native {
                // 从原生编辑器导出 XML
                currentContent = nativeEditorContext.exportToXML()
            } else {
                // 使用当前绑定的内容
                currentContent = content
            }
            
            // 更新内容
            if !currentContent.isEmpty {
                content = currentContent
                lastLoadedContent = currentContent
            }
            
            // 如果切换到原生编辑器，加载内容并注册格式提供者
            if newType == .native && preferencesService.isNativeEditorAvailable {
                nativeEditorContext.currentFolderId = folderId
                nativeEditorContext.loadFromXML(currentContent)
                // 注册原生编辑器的格式提供者
                nativeEditorContext.setEditorFocused(true)
                print("[UnifiedEditorWrapper] 已注册 NativeFormatProvider")
            } else {
                // 切换到 Web 编辑器，注册 Web 编辑器的格式提供者
                webEditorContext.setEditorFocused(true)
                print("[UnifiedEditorWrapper] 已注册 WebFormatProvider")
            }
            
            isUpdatingFromExternal = false
            isSwitchingEditor = false
        }
    }
    
    /// 处理文件夹 ID 变化（笔记切换时触发）
    private func handleFolderIdChange(oldValue: String?, newValue: String?) {
        // 只有当 folderId 真正变化时才处理（表示切换了笔记）
        guard oldValue != newValue else { return }
        
        print("[UnifiedEditorWrapper] folderId 变化（切换笔记）- 从 \(oldValue ?? "nil") 到 \(newValue ?? "nil")")
        
        // 获取要加载的内容
        let contentToLoad = xmlContent ?? content
        
        Task { @MainActor in
            isUpdatingFromExternal = true
            
            // 关键修复：先更新 lastLoadedContent，再加载内容
            lastLoadedContent = contentToLoad
            
            // 如果使用原生编辑器，强制重新加载内容
            if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
                nativeEditorContext.currentFolderId = newValue
                
                // 关键修复：先清空编辑器，再加载新内容
                if contentToLoad.isEmpty {
                    nativeEditorContext.nsAttributedText = NSAttributedString()
                    print("[UnifiedEditorWrapper] 原生编辑器清空内容（folderId 变化）")
                } else {
                    nativeEditorContext.loadFromXML(contentToLoad)
                    print("[UnifiedEditorWrapper] 原生编辑器重新加载内容（folderId 变化）- 长度: \(contentToLoad.count)")
                }
            }
            
            isUpdatingFromExternal = false
        }
    }
}

// MARK: - Preview

@available(macOS 14.0, *)
#Preview {
    UnifiedEditorWrapper(
        content: .constant("<text indent=\"1\">测试内容</text>"),
        isEditable: .constant(true),
        webEditorContext: WebEditorContext(),
        nativeEditorContext: NativeEditorContext(),
        noteRawData: nil,
        xmlContent: nil,
        folderId: nil,
        onContentChange: { _, _ in }
    )
    .frame(width: 600, height: 400)
}
