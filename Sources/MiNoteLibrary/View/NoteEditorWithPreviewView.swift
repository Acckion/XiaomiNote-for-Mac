import SwiftUI

struct NoteEditorWithPreviewView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var editedContent: String = ""
    @State private var isEditing: Bool = true
    
    var body: some View {
        VStack {
            if let note = viewModel.selectedNote {
                // 编辑器
                MiNoteEditor(xmlContent: $editedContent, isEditable: $isEditing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // 使用统一的 primaryXMLContent 获取内容
                        editedContent = note.primaryXMLContent
                    }
                    .onChange(of: note) { oldValue, newValue in
                        // 当笔记切换时更新内容
                        editedContent = newValue.primaryXMLContent
                    }
                    .onChange(of: editedContent) { oldValue, newValue in
                        // 自动保存更改
                        if newValue != note.primaryXMLContent {
                            Task {
                                do {
                                    let updatedNote = note.withPrimaryXMLContent(newValue)
                                    try await viewModel.updateNote(updatedNote)
                                } catch {
                                    print("自动保存失败: \(error)")
                                }
                            }
                        }
                    }
            } else {
                // 没有选中笔记时的占位视图
                VStack {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择笔记以开始编辑")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NoteEditorWithPreviewView(viewModel: NotesViewModel())
}
