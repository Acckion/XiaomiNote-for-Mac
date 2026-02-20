//
//  DebugModeView.swift
//  MiNoteMac
//
//  从 NoteDetailView 提取的调试模式视图组件
//

import SwiftUI

/// 调试模式编辑器视图
///
/// 封装 XMLDebugEditorView 及其回调
@available(macOS 14.0, *)
struct DebugModeEditorView: View {
    @Binding var debugXMLContent: String
    @Binding var isEditable: Bool
    @Binding var debugSaveStatus: DebugSaveStatus
    let onSave: () -> Void
    let onContentChange: (String) -> Void

    var body: some View {
        XMLDebugEditorView(
            xmlContent: $debugXMLContent,
            isEditable: $isEditable,
            saveStatus: $debugSaveStatus,
            onSave: onSave,
            onContentChange: onContentChange
        )
    }
}

/// 调试模式指示器
@available(macOS 14.0, *)
struct DebugModeIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 8))
            Text("调试模式")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(4)
    }
}

/// 调试模式保存状态指示器
@available(macOS 14.0, *)
struct DebugSaveStatusIndicator: View {
    let debugSaveStatus: DebugSaveStatus
    @Binding var showSaveErrorAlert: Bool
    @Binding var saveErrorMessage: String

    var body: some View {
        Group {
            switch debugSaveStatus {
            case .saved:
                Text("已保存")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
            case .saving:
                Text("保存中...")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            case .unsaved:
                Text("未保存")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            case let .error(message):
                Text("保存失败")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .onTapGesture {
                        saveErrorMessage = message
                        showSaveErrorAlert = true
                    }
            }
        }
    }
}
