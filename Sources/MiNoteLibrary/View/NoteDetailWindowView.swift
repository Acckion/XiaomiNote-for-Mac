import SwiftUI
import AppKit
import MiNoteLibrary

/// 笔记详情窗口视图（用于在新窗口打开笔记）
public struct NoteDetailWindowView: View {
    @StateObject private var viewModel = NotesViewModel()
    @State private var noteId: String?
    @State private var showingPasswordDialog = false
    @State private var noteToOpen: Note?
    
    public init() {}
    
    public var body: some View {
        Group {
            if let noteId = noteId,
               let note = viewModel.notes.first(where: { $0.id == noteId }) {
                // 使用 ContentView 来显示笔记详情
                ContentView(viewModel: viewModel)
                    .onAppear {
                        // 检查是否为私密笔记
                        if note.folderId == "2" {
                            handlePrivateNoteAccess(note: note)
                        } else {
                            // 非私密笔记，直接设置
                            viewModel.selectedNote = note
                            viewModel.selectedFolder = viewModel.folders.first { $0.id == note.folderId } ?? viewModel.folders.first { $0.id == "0" }
                        }
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
        .sheet(isPresented: $showingPasswordDialog) {
            if let note = noteToOpen {
                PrivateNotesPasswordInputDialogView(viewModel: viewModel)
                    .onDisappear {
                        // 检查是否已解锁
                        if viewModel.isPrivateNotesUnlocked {
                            // 已解锁，设置笔记
                            viewModel.selectedNote = note
                            viewModel.selectedFolder = viewModel.folders.first { $0.id == note.folderId } ?? viewModel.folders.first { $0.id == "0" }
                        } else {
                            // 未解锁，清空笔记ID
                            self.noteId = nil
                            self.noteToOpen = nil
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenNoteInNewWindow"))) { notification in
            if let noteId = notification.object as? String {
                self.noteId = noteId
            } else if let userInfo = notification.userInfo,
                      let note = userInfo["note"] as? Note {
                self.noteId = note.id
            }
        }
    }
    
    private func handlePrivateNoteAccess(note: Note) {
        let passwordManager = PrivateNotesPasswordManager.shared
        
        if passwordManager.hasPassword() {
            // 已设置密码，需要验证
            noteToOpen = note
            showingPasswordDialog = true
        } else {
            // 未设置密码，直接允许访问
            viewModel.isPrivateNotesUnlocked = true
            viewModel.selectedNote = note
            viewModel.selectedFolder = viewModel.folders.first { $0.id == note.folderId } ?? viewModel.folders.first { $0.id == "0" }
        }
    }
}
