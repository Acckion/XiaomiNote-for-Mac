//
//  UnifiedEditorWrapper.swift
//  MiNoteMac
//
//  原生编辑器包装器 - 提供内容管理、防抖和状态协调功能
//

import Combine
import SwiftUI

/// 原生编辑器包装器
///
/// 该组件为原生编辑器提供以下功能：
/// - 内容变化防抖（300ms），避免频繁保存
/// - 智能内容比较，避免保存后不必要的重新加载
/// - 笔记切换检测和内容同步
/// - 状态管理，防止循环更新
/// - XML 和 NSAttributedString 格式转换协调
@available(macOS 14.0, *)
struct UnifiedEditorWrapper: View {

    // MARK: - Properties

    /// XML 内容绑定
    @Binding var content: String

    /// 是否可编辑
    @Binding var isEditable: Bool

    /// 原生编辑器上下文 - 从外部传入以确保工具栏和编辑器使用同一个上下文
    @ObservedObject var nativeEditorContext: NativeEditorContext

    /// XML 内容（用于初始化）
    let xmlContent: String?

    /// 当前文件夹 ID（用于图片存储）
    let folderId: String?

    /// 内容变化回调
    let onContentChange: (String, String?) -> Void

    // MARK: - State

    /// 编辑器偏好设置服务
    @ObservedObject private var preferencesService = EditorPreferencesService.shared

    /// 上次加载的内容（用于防止重复加载）
    @State private var lastLoadedContent = ""

    /// 是否是初始加载
    @State private var isInitialLoad = true

    /// 是否正在从外部更新内容（防止循环更新）
    @State private var isUpdatingFromExternal = false

    /// 内容变化防抖任务
    @State private var debounceTask: Task<Void, Never>?

    /// 防抖延迟时间（毫秒）
    private let debounceDelayMs: UInt64 = 300

    // MARK: - Body

    var body: some View {
        nativeEditorView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                setupEditor()
            }
            .onChange(of: content) { oldValue, newValue in
                handleContentChange(oldValue: oldValue, newValue: newValue)
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

    // MARK: - Setup Methods

    /// 设置编辑器
    private func setupEditor() {
        setupNativeEditor()

        // 初始加载内容
        let contentToLoad = xmlContent ?? content
        if !contentToLoad.isEmpty {
            Task { @MainActor in
                lastLoadedContent = contentToLoad
                isInitialLoad = false
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
                print("[[诊断]] UnifiedEditorWrapper.onAppear: 调用 loadFromXML")
                nativeEditorContext.loadFromXML(contentToLoad)
                lastLoadedContent = contentToLoad
            }
        }
    }

    // MARK: - Content Change Handlers

    /// 处理 xmlContent 变化（切换笔记时触发）
    private func handleXMLContentChange(oldValue: String?, newValue: String?) {
        // xmlContent 变化是检测笔记切换最可靠的方式
        guard let newContent = newValue else { return }

        // 如果内容完全相同，不需要处理
        if newContent == oldValue {
            return
        }

        // ✅ 关键修复：增强内容比较逻辑，避免保存后不必要的重新加载
        // 检查是否是保存后的内容更新（而不是笔记切换）
        // 如果新内容与当前编辑器中的内容相同（或非常接近），说明这是保存后的更新
        // 不需要重新加载，避免触发 hasUnsavedChanges = true 和打断输入法
        if preferencesService.isNativeEditorAvailable {
            let currentEditorXML = nativeEditorContext.exportToXML()

            // ✅ 规范化内容比较：去除空白字符后比较
            let normalizedCurrent = currentEditorXML.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedNew = newContent.trimmingCharacters(in: .whitespacesAndNewlines)

            if !normalizedCurrent.isEmpty, normalizedCurrent == normalizedNew {
                Task { @MainActor in
                    lastLoadedContent = newContent
                }
                return
            }

            // ✅ 长度差异检查：如果内容长度差异很小（< 10 个字符），也认为是保存后的更新
            // 这可以处理格式化差异（如空格、换行符的微小变化）
            let lengthDiff = abs(currentEditorXML.count - newContent.count)
            if lengthDiff < 10, !currentEditorXML.isEmpty {
                Task { @MainActor in
                    lastLoadedContent = newContent
                }
                return
            }
        }

        // ✅ 真正的内容变化（笔记切换），执行重新加载

        // 记录内容重新加载（性能监控）
        PerformanceMonitor.shared.recordContentReload()

        Task { @MainActor in
            // 确保脱离视图更新周期，避免 loadFromXML 中修改 @Published 属性时触发警告
            await Task.yield()

            isUpdatingFromExternal = true

            // 关键修复：先更新 lastLoadedContent，再加载内容
            // 这样可以防止后续的 content 变化被误认为是用户编辑
            lastLoadedContent = newContent

            // 如果使用原生编辑器，强制重新加载内容
            if preferencesService.isNativeEditorAvailable {
                nativeEditorContext.currentFolderId = folderId

                if newContent.isEmpty {
                    print("[[诊断]] handleXMLContentChange: 直接赋值 nsAttributedText = empty")
                    nativeEditorContext.nsAttributedText = NSAttributedString()
                } else {
                    print("[[诊断]] handleXMLContentChange: 调用 loadFromXML")
                    nativeEditorContext.loadFromXML(newContent)
                }
            }

            isUpdatingFromExternal = false
        }
    }

    /// 处理内容变化
    ///
    /// 关键修复：增强内容比较逻辑，避免保存后不必要的重新加载
    private func handleContentChange(oldValue: String, newValue: String) {
        guard oldValue != newValue else { return }
        guard !isUpdatingFromExternal else { return }

        // 关键修复：检查是否是新内容（不同于上次加载的内容）
        // 这通常发生在笔记切换时，content 绑定被外部更新
        if newValue != lastLoadedContent {

            // ✅ 关键修复：检查是否是保存后的内容更新（而不是笔记切换）
            // 如果新内容与当前编辑器中的内容相同（或非常接近），说明这是保存后的更新
            // 不需要重新加载，避免触发视图更新和打断输入法
            if preferencesService.isNativeEditorAvailable {
                let currentEditorXML = nativeEditorContext.exportToXML()

                // 使用规范化比较：去除空白字符后比较
                let normalizedCurrent = currentEditorXML.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedNew = newValue.trimmingCharacters(in: .whitespacesAndNewlines)

                if !normalizedCurrent.isEmpty, normalizedCurrent == normalizedNew {
                    Task { @MainActor in
                        lastLoadedContent = newValue
                    }
                    return
                }

                // 额外检查：如果内容长度差异很小（< 10 个字符），也认为是保存后的更新
                // 这可以处理格式化差异（如空格、换行符的微小变化）
                let lengthDiff = abs(currentEditorXML.count - newValue.count)
                if lengthDiff < 10, !currentEditorXML.isEmpty {
                    Task { @MainActor in
                        lastLoadedContent = newValue
                    }
                    return
                }
            }

            // ✅ 真正的内容变化（笔记切换），执行重新加载
            Task { @MainActor in
                // 确保脱离视图更新周期，避免 loadFromXML 中修改 @Published 属性时触发警告
                await Task.yield()

                isUpdatingFromExternal = true

                // 关键修复：先更新 lastLoadedContent，再加载内容
                lastLoadedContent = newValue

                // 如果使用原生编辑器，同步内容
                if preferencesService.isNativeEditorAvailable {
                    nativeEditorContext.currentFolderId = folderId

                    // 关键修复：先清空编辑器，再加载新内容
                    if newValue.isEmpty {
                        print("[[诊断]] handleContentChange: 直接赋值 nsAttributedText = empty")
                        nativeEditorContext.nsAttributedText = NSAttributedString()
                    } else {
                        print("[[诊断]] handleContentChange: 调用 loadFromXML")
                        nativeEditorContext.loadFromXML(newValue)
                    }
                }

                isUpdatingFromExternal = false
            }
        }
    }

    /// 处理原生编辑器内容变化
    private func handleNativeContentChange(_: NSAttributedString) {
        // 如果正在从外部更新内容，跳过处理
        guard !isUpdatingFromExternal else {
            return
        }

        // 关键修复：立即标记有未保存的更改
        // 这确保用户在输入时能看到"未保存"状态
        Task { @MainActor in
            nativeEditorContext.hasUnsavedChanges = true
        }

        // 取消之前的防抖任务
        debounceTask?.cancel()

        // 创建新的防抖任务
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
            } catch {
            }
        }
    }

    /// 执行实际的内容变化处理
    private func performContentChange(_ attributedString: NSAttributedString) async {
        // 关键修复：直接使用传入的 attributedString 进行转换
        // 而不是依赖 nativeEditorContext.nsAttributedText
        // 因为 nsAttributedText 可能还没有被更新（异步更新）

        let xmlContent = XiaoMiFormatConverter.shared.safeNSAttributedStringToXML(attributedString)

        // 检查转换结果
        if xmlContent.isEmpty && attributedString.length > 0 {
            // 不触发保存，保留用户编辑的内容在内存中
            return
        }


        // 关键修复：即使 XML 内容相同，也要检查是否需要触发保存
        // 因为格式变化可能不会改变 XML 字符串，但仍需要保存
        let contentChanged = xmlContent != content
        let hasUnsavedChanges = nativeEditorContext.hasUnsavedChanges

        if contentChanged || hasUnsavedChanges {
            // 避免在视图更新过程中直接修改 @Published 属性
            await MainActor.run {
                isUpdatingFromExternal = true

                // 更新绑定的内容
                content = xmlContent
                lastLoadedContent = xmlContent

                isUpdatingFromExternal = false
            }

            // 调用内容变化回调（原生编辑器不提供 HTML 缓存）
            onContentChange(xmlContent, nil)

        } else {
        }
    }

    /// 处理文件夹 ID 变化（笔记切换时触发）
    private func handleFolderIdChange(oldValue: String?, newValue: String?) {
        // 只有当 folderId 真正变化时才处理（表示切换了笔记）
        guard oldValue != newValue else { return }


        // 获取要加载的内容
        let contentToLoad = xmlContent ?? content

        Task { @MainActor in
            // 确保脱离视图更新周期，避免 loadFromXML 中修改 @Published 属性时触发警告
            await Task.yield()

            isUpdatingFromExternal = true

            // 关键修复：先更新 lastLoadedContent，再加载内容
            lastLoadedContent = contentToLoad

            // 如果使用原生编辑器，强制重新加载内容
            if preferencesService.isNativeEditorAvailable {
                nativeEditorContext.currentFolderId = newValue

                // 关键修复：先清空编辑器，再加载新内容
                if contentToLoad.isEmpty {
                    print("[[诊断]] handleFolderIdChange: 直接赋值 nsAttributedText = empty")
                    nativeEditorContext.nsAttributedText = NSAttributedString()
                } else {
                    print("[[诊断]] handleFolderIdChange: 调用 loadFromXML")
                    nativeEditorContext.loadFromXML(contentToLoad)
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
        nativeEditorContext: NativeEditorContext(),
        xmlContent: nil,
        folderId: nil,
        onContentChange: { _, _ in }
    )
    .frame(width: 600, height: 400)
}
