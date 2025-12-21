import SwiftUI
import AppKit
import MiNoteLibrary

/// 笔记详情窗口视图（用于在新窗口打开笔记）
public struct NoteDetailWindowView: View {
    @StateObject private var viewModel = NotesViewModel()
    @State private var noteId: String?
    
    public init() {}
    
    public var body: some View {
        Group {
            if let noteId = noteId,
               let note = viewModel.notes.first(where: { $0.id == noteId }) {
                // 使用 ContentView 来显示笔记详情
                ContentView(viewModel: viewModel)
                    .onAppear {
                        viewModel.selectedNote = note
                        viewModel.selectedFolder = viewModel.folders.first { $0.id == note.folderId } ?? viewModel.folders.first { $0.id == "0" }
                    }
            } else {
                ContentUnavailableView(
                    "未找到笔记",
                    systemImage: "note.text",
                    description: Text("笔记可能已被删除")
                )
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNoteInNewWindow"))) { notification in
            if let noteId = notification.object as? String {
                self.noteId = noteId
            } else if let userInfo = notification.userInfo,
                      let note = userInfo["note"] as? Note {
                self.noteId = note.id
            }
        }
    }
}

