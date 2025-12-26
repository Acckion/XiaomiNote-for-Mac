import SwiftUI

/// Web编辑器包装器，用于在NoteDetailView中替换RichTextEditorWrapper
struct WebEditorWrapper: View {
    @Binding var content: String
    @Binding var isEditable: Bool
    @ObservedObject var editorContext: WebEditorContext
    let noteRawData: String?
    let xmlContent: String?
    let onContentChange: (String) -> Void
    
    var body: some View {
        WebEditorView(
            content: $content,
            onContentChanged: { newContent in
                // 内容变化时通知父组件
                onContentChange(newContent)
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
                editorContext.getCurrentContentClosure = coordinator.getCurrentContentClosure
                editorContext.forceSaveContentClosure = coordinator.forceSaveContentClosure
                editorContext.undoClosure = coordinator.undoClosure
                editorContext.redoClosure = coordinator.redoClosure
                editorContext.openWebInspectorClosure = { [weak coordinator] in
                    coordinator?.openWebInspector()
                }
                editorContext.highlightSearchTextClosure = coordinator.highlightSearchTextClosure
                
                editorContext.editorReady()
                print("Web编辑器已准备就绪")
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // 初始加载内容
            if !content.isEmpty {
                // 内容已经通过绑定传递
            }
        }
        .onChange(of: content) { oldValue, newValue in
            // 当外部内容变化时（如切换笔记），更新编辑器
            if oldValue != newValue {
                // 内容会通过WebEditorView的updateNSView自动更新
            }
        }
        .onChange(of: isEditable) { oldValue, newValue in
            // 处理编辑状态变化
            // Web编辑器始终可编辑，但可以添加逻辑来禁用某些功能
        }
    }
}

