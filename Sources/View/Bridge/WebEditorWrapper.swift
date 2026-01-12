import SwiftUI

/// Web编辑器包装器，用于在NoteDetailView中替换RichTextEditorWrapper
struct WebEditorWrapper: View {
    @Binding var content: String
    @Binding var isEditable: Bool
    @ObservedObject var editorContext: WebEditorContext
    let noteRawData: String?
    let xmlContent: String?
    let onContentChange: (String, String?) -> Void
    
    @State private var lastLoadedContent: String = ""
    @State private var isInitialLoad: Bool = true
    
    var body: some View {
        WebEditorView(
            content: $content,
            onContentChanged: { newContent, html in
                // 内容变化时通知父组件，同时传递新获取的 HTML 缓存
                onContentChange(newContent, html)
                // 使用Task延迟更新，避免在视图更新期间修改@Published属性
                Task { @MainActor in
                    editorContext.content = newContent
                }
            },
            onEditorReady: { coordinator in
                // 编辑器准备就绪，设置操作闭包到 editorContext
                coordinator.webEditorContext = editorContext
                editorContext.executeFormatActionClosure = coordinator.executeFormatActionClosure
                editorContext.insertImageClosure = coordinator.insertImageClosure
                editorContext.insertAudioClosure = coordinator.insertAudioClosure
                editorContext.insertRecordingTemplateClosure = coordinator.insertRecordingTemplateClosure
                editorContext.updateRecordingTemplateClosure = coordinator.updateRecordingTemplateClosure
                editorContext.getCurrentContentClosure = coordinator.getCurrentContentClosure
                editorContext.forceSaveContentClosure = coordinator.forceSaveContentClosure
                editorContext.undoClosure = coordinator.undoClosure
                editorContext.redoClosure = coordinator.redoClosure
                editorContext.openWebInspectorClosure = { [weak coordinator] in
                    coordinator?.openWebInspector()
                }
                editorContext.highlightSearchTextClosure = coordinator.highlightSearchTextClosure
                editorContext.findTextClosure = { [weak coordinator] options in
                    guard let coordinator = coordinator else {
                        print("[WebEditorWrapper] findTextClosure: coordinator为nil")
                        return
                    }

                    let searchText = options["text"] as? String ?? ""
                    let direction = options["direction"] as? String ?? "next"
                    let caseSensitive = options["caseSensitive"] as? Bool ?? false
                    let wholeWord = options["wholeWord"] as? Bool ?? false
                    let regex = options["regex"] as? Bool ?? false

                    print("[WebEditorWrapper] === 调用Web编辑器查找API ===")
                    print("[WebEditorWrapper] 查找文本: '\(searchText)'")
                    print("[WebEditorWrapper] 查找方向: \(direction)")
                    print("[WebEditorWrapper] 查找选项: 区分大小写=\(caseSensitive), 全字匹配=\(wholeWord), 正则表达式=\(regex)")

                    let javascript = """
                    window.MiNoteWebEditor.findText({
                        text: '\(searchText)',
                        direction: '\(direction)',
                        caseSensitive: \(caseSensitive),
                        wholeWord: \(wholeWord),
                        regex: \(regex)
                    })
                    """
                    print("[WebEditorWrapper] 执行JavaScript: \(javascript)")

                    coordinator.webView?.evaluateJavaScript(javascript) { result, error in
                        if let error = error {
                            print("[WebEditorWrapper] findText执行失败: \(error)")
                        } else {
                            print("[WebEditorWrapper] findText执行成功, 返回结果: \(String(describing: result))")
                        }
                    }
                }
                editorContext.replaceTextClosure = { [weak coordinator] options in
                    guard let coordinator = coordinator else { return }
                    let javascript = """
                    window.MiNoteWebEditor.replaceText({
                        searchText: '\(options["searchText"] as? String ?? "")',
                        replaceText: '\(options["replaceText"] as? String ?? "")',
                        replaceAll: \(options["replaceAll"] as? Bool ?? false),
                        caseSensitive: \(options["caseSensitive"] as? Bool ?? false),
                        wholeWord: \(options["wholeWord"] as? Bool ?? false),
                        regex: \(options["regex"] as? Bool ?? false)
                    })
                    """
                    coordinator.webView?.evaluateJavaScript(javascript) { result, error in
                        if let error = error {
                            print("[WebEditorWrapper] replaceText执行失败: \(error)")
                        }
                    }
                }

                editorContext.editorReady()
                print("Web编辑器已准备就绪")
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 初始加载内容
            if !content.isEmpty {
                lastLoadedContent = content
                print("[WebEditorWrapper] 初始加载内容 - 长度: \(content.count)")
            }
            isInitialLoad = false
        }
        .onChange(of: content) { oldValue, newValue in
            // 当外部内容变化时（如切换笔记），更新编辑器
            if oldValue != newValue {
                // 内容污染防护：确保新内容与上次加载的内容不同
                if newValue != lastLoadedContent {
                    print("[WebEditorWrapper] 内容变化 - 从长度 \(oldValue.count) 到 \(newValue.count)")
                    lastLoadedContent = newValue
                } else {
                    print("[WebEditorWrapper] 内容未变化，跳过更新")
                }
            }
        }
        .onChange(of: isEditable) { oldValue, newValue in
            // 处理编辑状态变化
            // Web编辑器始终可编辑，但可以添加逻辑来禁用某些功能
        }
    }
}
