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
    
    /// 原生编辑器上下文（用于原生编辑器）
    @StateObject private var nativeEditorContext = NativeEditorContext()
    
    /// 笔记原始数据（用于 Web 编辑器）
    let noteRawData: String?
    
    /// XML 内容（用于初始化）
    let xmlContent: String?
    
    /// 当前文件夹 ID（用于图片存储）
    let folderId: String?
    
    /// 内容变化回调
    let onContentChange: (String, String?) -> Void
    
    // MARK: - State
    
    /// 编辑器偏好设置服务
    @StateObject private var preferencesService = EditorPreferencesService.shared
    
    /// 是否正在切换编辑器
    @State private var isSwitchingEditor: Bool = false
    
    /// 上次加载的内容（用于防止重复加载）
    @State private var lastLoadedContent: String = ""
    
    /// 是否是初始加载
    @State private var isInitialLoad: Bool = true
    
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
                nativeEditorContext.updateSelectedRange(range)
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
        if !content.isEmpty {
            lastLoadedContent = content
            print("[UnifiedEditorWrapper] 初始加载内容 - 长度: \(content.count)")
        }
        isInitialLoad = false
    }
    
    /// 设置原生编辑器
    private func setupNativeEditor() {
        // 设置文件夹 ID（用于图片存储）
        nativeEditorContext.currentFolderId = folderId
        
        // 加载 XML 内容到原生编辑器
        let contentToLoad = xmlContent ?? content
        if !contentToLoad.isEmpty {
            nativeEditorContext.loadFromXML(contentToLoad)
            print("[UnifiedEditorWrapper] 原生编辑器加载内容 - 长度: \(contentToLoad.count)")
        }
    }
    
    // MARK: - Content Change Handlers
    
    /// 处理内容变化
    private func handleContentChange(oldValue: String, newValue: String) {
        guard oldValue != newValue else { return }
        
        // 内容污染防护：确保新内容与上次加载的内容不同
        if newValue != lastLoadedContent {
            print("[UnifiedEditorWrapper] 内容变化 - 从长度 \(oldValue.count) 到 \(newValue.count)")
            lastLoadedContent = newValue
            
            // 如果使用原生编辑器，同步内容
            if preferencesService.selectedEditorType == .native && preferencesService.isNativeEditorAvailable {
                nativeEditorContext.loadFromXML(newValue)
            }
        } else {
            print("[UnifiedEditorWrapper] 内容未变化，跳过更新")
        }
    }
    
    /// 处理原生编辑器内容变化
    private func handleNativeContentChange(_ attributedString: NSAttributedString) {
        // 将 NSAttributedString 转换为 XML
        let xmlContent = nativeEditorContext.exportToXML()
        
        // 更新绑定的内容
        if xmlContent != content {
            content = xmlContent
            lastLoadedContent = xmlContent
            
            // 调用内容变化回调（原生编辑器不提供 HTML 缓存）
            onContentChange(xmlContent, nil)
        }
    }
    
    /// 处理编辑器类型变化
    private func handleEditorTypeChange(from oldType: EditorType, to newType: EditorType) {
        guard oldType != newType else { return }
        
        isSwitchingEditor = true
        print("[UnifiedEditorWrapper] 编辑器类型变化: \(oldType.displayName) -> \(newType.displayName)")
        
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
        
        // 如果切换到原生编辑器，加载内容
        if newType == .native && preferencesService.isNativeEditorAvailable {
            nativeEditorContext.loadFromXML(currentContent)
        }
        
        isSwitchingEditor = false
    }
}

// MARK: - Preview

@available(macOS 14.0, *)
#Preview {
    UnifiedEditorWrapper(
        content: .constant("<text indent=\"1\">测试内容</text>"),
        isEditable: .constant(true),
        webEditorContext: WebEditorContext(),
        noteRawData: nil,
        xmlContent: nil,
        folderId: nil,
        onContentChange: { _, _ in }
    )
    .frame(width: 600, height: 400)
}
