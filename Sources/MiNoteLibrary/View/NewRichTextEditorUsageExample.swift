//
//  NewRichTextEditorUsageExample.swift
//  MiNoteMac
//
//  新编辑器使用示例
//  展示如何在 NoteDetailView 中使用 NewRichTextEditor
//

import SwiftUI

/// 新编辑器使用示例
/// 
/// 这个文件展示了如何在 NoteDetailView 中使用 NewRichTextEditor
/// 替换现有的 RichTextEditorWrapper
@available(macOS 14.0, *)
struct NewRichTextEditorUsageExample: View {
    
    @State private var editedRTFData: Data? = nil
    @State private var isEditable: Bool = true
    @State private var lastSavedRTFData: Data? = nil
    @State private var isInitializing: Bool = true
    
    var noteRawData: [String: Any]? = nil
    var xmlContent: String? = nil
    var onContentChange: ((Data?) -> Void)? = nil
    
    var body: some View {
        NewRichTextEditor(
            rtfData: $editedRTFData,
            isEditable: $isEditable,
            noteRawData: noteRawData,
            xmlContent: xmlContent,
            onContentChange: { newRTFData in
                // RTF数据变化时，更新 editedRTFData 并检查是否需要保存
                guard !isInitializing, let rtfData = newRTFData else {
                    return
                }
                
                // 检查内容是否真的变化了（避免仅打开笔记就触发保存）
                if let lastSaved = lastSavedRTFData, lastSaved == rtfData {
                    // RTF 数据相同，不需要保存
                    editedRTFData = rtfData
                    return
                }
                
                editedRTFData = rtfData
                
                // 内容确实变化了，触发保存
                onContentChange?(rtfData)
            }
        )
    }
}

/*
 在 NoteDetailView 中使用新编辑器的步骤：
 
 1. 在 bodyEditorView 中，将 RichTextEditorWrapper 替换为 NewRichTextEditor：
 
 ```swift
 private var bodyEditorView: some View {
     NewRichTextEditor(
         rtfData: $editedRTFData,
         isEditable: $isEditable,
         noteRawData: viewModel.selectedNote?.rawData,
         xmlContent: viewModel.selectedNote?.primaryXMLContent,
         onContentChange: { newRTFData in
             guard !isInitializing, let rtfData = newRTFData else {
                 return
             }
             
             if let lastSaved = lastSavedRTFData, lastSaved == rtfData {
                 editedRTFData = rtfData
                 return
             }
             
             editedRTFData = rtfData
             
             if let attributedText = AttributedStringConverter.rtfDataToAttributedString(rtfData) {
                 editedAttributedText = attributedText
             }
             
             guard let note = viewModel.selectedNote else {
                 return
             }
             
             Task { @MainActor in
                 await saveToLocalOnly(for: note)
                 scheduleCloudUpload(for: note)
             }
         }
     )
     .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
 }
 ```
 
 2. 移除不再需要的 editorContext（NewRichTextEditor 内部管理自己的 context）
 
 3. 新编辑器的优势：
    - 内置格式工具栏（macOS）
    - 内置 Inspector 侧边栏（格式面板）
    - 更好的图片附件支持
    - 更简洁的 API
    - 与 Demo 实现一致，功能完善
 */


