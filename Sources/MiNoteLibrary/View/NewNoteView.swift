import SwiftUI

@available(macOS 14.0, *)
struct NewNoteView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var xmlContent: String = "<new-format/><text indent=\"1\"></text>"
    @State private var selectedFolderId: String?
    @State private var isCreating: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isEditable: Bool = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 编辑器背景
                Color(nsColor: NSColor.textBackgroundColor)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 标题（作为放大的正文，不单独区分）
                    HStack {
                        TextField("笔记标题", text: $title)
                            .font(.system(size: 28, weight: .regular))
                            .textFieldStyle(.plain)
                            .foregroundColor(Color(nsColor: NSColor.labelColor))
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        Spacer()
                        
                        if !viewModel.folders.isEmpty {
                            Picker("", selection: $selectedFolderId) {
                                Text("未分类").tag(String?.none)
                                ForEach(viewModel.folders.filter { !$0.isSystem || $0.id == "0" }) { folder in
                                    Text(folder.name).tag(folder.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(.trailing, 16)
                            .padding(.top, 16)
                        }
                    }
                    
                    // 编辑器区域（正文）
                    MiNoteEditor(rtfData: Binding(
                        get: { 
                            // 从 XML 转换为 RTF（向后兼容）
                            return convertXMLToRTF(xmlContent)
                        },
                        set: { newRTFData in
                            // 从 RTF 转换为 XML
                            if let xml = convertRTFToXML(newRTFData) {
                                xmlContent = xml
                            }
                        }
                    ), isEditable: $isEditable)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("新建笔记")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: createNote) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("创建")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .alert("创建失败", isPresented: $showError) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // 默认选择第一个文件夹
                if selectedFolderId == nil, let firstFolder = viewModel.folders.first(where: { !$0.isSystem || $0.id == "0" }) {
                    selectedFolderId = firstFolder.id
                }
            }
        }
        .frame(width: 600, height: 700)
    }
    
    private func createNote() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                // 确保 XML 内容格式正确
                let finalContent = xmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
                    ? "<new-format/><text indent=\"1\"></text>"
                    : xmlContent
                
                let newNote = Note(
                    id: UUID().uuidString,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    content: finalContent,
                    folderId: selectedFolderId ?? "0",
                    isStarred: false,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                
                try await viewModel.createNote(newNote)
                
                // 创建成功后关闭视图
                await MainActor.run {
                    dismiss()
                }
                
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isCreating = false
            }
        }
    }
    
    // MARK: - RTF 和 XML 转换辅助方法
    
    /// 将 XML 转换为 RTF 数据
    private func convertXMLToRTF(_ xmlContent: String) -> Data? {
        guard !xmlContent.isEmpty else { return nil }
        
        var bodyContent = xmlContent
        if !bodyContent.hasPrefix("<new-format/>") {
            bodyContent = "<new-format/>" + bodyContent
        }
        
        let attributedString = MiNoteContentParser.parseToAttributedString(bodyContent, noteRawData: nil)
        // 使用 archivedData 格式
        return try? attributedString.richTextData(for: .archivedData)
    }
    
    /// 将 archivedData 转换为 XML
    private func convertRTFToXML(_ rtfData: Data?) -> String? {
        guard let rtfData = rtfData else { return nil }
        
        // 使用 archivedData 格式读取
        guard let attributedString = try? NSAttributedString(data: rtfData, format: .archivedData) else {
            return nil
        }
        
        var xmlContent = MiNoteContentParser.parseToXML(attributedString)
        xmlContent = xmlContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if xmlContent.isEmpty {
            xmlContent = "<new-format/><text indent=\"1\"></text>"
        }
        
        return xmlContent
    }
}

@available(macOS 14.0, *)
#Preview {
    NewNoteView(viewModel: NotesViewModel())
}
