import SwiftUI
import AppKit
import MiNoteLibrary

@main
struct MiNoteMacApp: App {
    @StateObject private var viewModel = NotesViewModel()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .navigationTitle("备忘录")
                .onAppear {
                    // 激活应用程序
                    NSApp.activate(ignoringOtherApps: true)
                    print("应用程序窗口已显示")
                    // 设置窗口标题，去除 MiNoteMac 字样
                    DispatchQueue.main.async {
                        // 设置所有窗口的标题
                        for window in NSApplication.shared.windows {
                            window.title = "备忘录"
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                    // 当窗口获得焦点时，确保标题正确
                    if let window = notification.object as? NSWindow {
                        window.title = "备忘录"
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // MARK: - 文件菜单
            CommandGroup(replacing: .newItem) {
                Button("新建备忘录") {
                    viewModel.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("新建文件夹") {
                    createNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            
            // 在新建项后添加分割线和共享
            CommandGroup(after: .newItem) {
                Divider()
                
                Button("共享") {
                    shareNote()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(viewModel.selectedNote == nil)
            }
            
            // 在关闭窗口后添加导入、导出等
            CommandGroup(after: .windowArrangement) {
                Divider()
                
                Button("导入") {
                    importNotes()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("导出为...") {
                    exportNote()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(viewModel.selectedNote == nil)
                
                Divider()
                
                Button("置顶备忘录") {
                    toggleStarNote()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(viewModel.selectedNote == nil)
                
                Button("复制备忘录") {
                    copyNote()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(viewModel.selectedNote == nil)
            }
            
            CommandGroup(after: .toolbar) {
                Divider()
                
                Button("调试设置") {
                    openDebugSettings()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift, .option])
            }
        }
        
        Settings {
            SettingsView(viewModel: viewModel)
        }
        
        Window("调试设置", id: "debug-settings") {
            DebugSettingsView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
    }
    
    private func openDebugSettings() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("debug-settings") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "debug-settings")
        }
    }
    
    // MARK: - 文件菜单操作
    
    /// 新建文件夹
    private func createNewFolder() {
        let alert = NSAlert()
        alert.messageText = "新建文件夹"
        alert.informativeText = "请输入文件夹名称："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "文件夹名称"
        alert.accessoryView = inputField
        
        alert.window.initialFirstResponder = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let folderName = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !folderName.isEmpty {
                Task {
                    do {
                        try await viewModel.createFolder(name: folderName)
                    } catch {
                        print("[App] 创建文件夹失败: \(error)")
                        DispatchQueue.main.async {
                            let errorAlert = NSAlert()
                            errorAlert.messageText = "创建文件夹失败"
                            errorAlert.informativeText = error.localizedDescription
                            errorAlert.alertStyle = .warning
                            errorAlert.runModal()
                        }
                    }
                }
            }
        }
    }
    
    /// 共享笔记
    private func shareNote() {
        guard let note = viewModel.selectedNote else { return }
        
        let sharingService = NSSharingServicePicker(items: [
            note.title,
            note.content
        ])
        
        if let window = NSApp.windows.first(where: { $0.isKeyWindow }) {
            sharingService.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
        }
    }
    
    /// 导入笔记
    private func importNotes() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.text, .plainText, .rtf]
        panel.message = "选择要导入的笔记文件"
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    Task {
                        do {
                            let content = try String(contentsOf: url, encoding: .utf8)
                            let fileName = url.deletingPathExtension().lastPathComponent
                            
                            let newNote = Note(
                                id: UUID().uuidString,
                                title: fileName,
                                content: content,
                                folderId: viewModel.selectedFolder?.id ?? "0",
                                isStarred: false,
                                createdAt: Date(),
                                updatedAt: Date()
                            )
                            
                            try await viewModel.createNote(newNote)
                        } catch {
                            print("[App] 导入笔记失败: \(error)")
                            DispatchQueue.main.async {
                                let errorAlert = NSAlert()
                                errorAlert.messageText = "导入失败"
                                errorAlert.informativeText = "无法导入文件: \(url.lastPathComponent)\n\(error.localizedDescription)"
                                errorAlert.alertStyle = .warning
                                errorAlert.runModal()
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// 导出笔记
    private func exportNote() {
        guard let note = viewModel.selectedNote else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = note.title.isEmpty ? "无标题" : note.title
        panel.message = "导出笔记"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try note.content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("[App] 导出笔记失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /// 置顶/取消置顶笔记
    private func toggleStarNote() {
        guard let note = viewModel.selectedNote else { return }
        viewModel.toggleStar(note)
    }
    
    /// 复制笔记
    private func copyNote() {
        guard let note = viewModel.selectedNote else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }
}
