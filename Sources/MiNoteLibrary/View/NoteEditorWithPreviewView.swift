import SwiftUI

@available(macOS 26.0, *)
struct NoteEditorWithPreviewView: View {
    @ObservedObject var viewModel: NotesViewModel
    @State private var editedRTFData: Data? = nil  // macOS 26 原生存储：RTF 格式
    @State private var isEditing: Bool = true
    
    var body: some View {
        VStack {
            if let note = viewModel.selectedNote {
                // 编辑器
                MiNoteEditor(rtfData: $editedRTFData, isEditable: $isEditing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        // macOS 26 原生存储：优先使用 RTF 数据
                        if let rtfData = note.rtfData {
                            editedRTFData = rtfData
                        } else {
                            // 向后兼容：从 XML 转换
                            editedRTFData = convertXMLToRTF(note.primaryXMLContent, noteRawData: note.rawData)
                        }
                    }
                    .onChange(of: note) { oldValue, newValue in
                        // 当笔记切换时更新内容
                        if let rtfData = newValue.rtfData {
                            editedRTFData = rtfData
                        } else {
                            editedRTFData = convertXMLToRTF(newValue.primaryXMLContent, noteRawData: newValue.rawData)
                        }
                    }
                    .onChange(of: editedRTFData) { oldValue, newValue in
                        // 自动保存更改
                        Task {
                            do {
                                // 从 RTF 转换为 XML（用于同步）
                                let xmlContent = convertRTFToXML(newValue) ?? note.primaryXMLContent
                                let updatedNote = note.withPrimaryXMLContent(xmlContent)
                                var finalNote = updatedNote
                                finalNote.rtfData = newValue  // 保存 RTF 数据
                                try await viewModel.updateNote(finalNote)
                            } catch {
                                print("自动保存失败: \(error)")
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
    
    // MARK: - RTF 和 XML 转换辅助方法
    
    /// 将 XML 转换为 RTF 数据（向后兼容）
    private func convertXMLToRTF(_ xmlContent: String, noteRawData: [String: Any]?) -> Data? {
        guard !xmlContent.isEmpty else { return nil }
        
        // 确保正文以 <new-format/> 开头
        var bodyContent = xmlContent
        if !bodyContent.hasPrefix("<new-format/>") {
            bodyContent = "<new-format/>" + bodyContent
        }
        
        // 将 XML 转换为 NSAttributedString
        let attributedString = MiNoteContentParser.parseToAttributedString(bodyContent, noteRawData: noteRawData)
        
        // 将 NSAttributedString 转换为 RTF 数据
        let rtfRange = NSRange(location: 0, length: attributedString.length)
        return try? attributedString.data(from: rtfRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
    
    /// 将 RTF 数据转换为 XML（用于同步）
    private func convertRTFToXML(_ rtfData: Data?) -> String? {
        guard let rtfData = rtfData else { return nil }
        
        // 从 RTF 数据创建 NSAttributedString
        guard let attributedString = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else {
            return nil
        }
        
        // 将 NSAttributedString 转换为 XML
        var xmlContent = MiNoteContentParser.parseToXML(attributedString)
        
        // 清理内容：移除开头的空段落
        xmlContent = xmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if xmlContent.isEmpty {
            xmlContent = "<new-format/><text indent=\"1\"></text>"
        }
        
        return xmlContent
    }
}

@available(macOS 26.0, *)
#Preview {
    NoteEditorWithPreviewView(viewModel: NotesViewModel())
}
