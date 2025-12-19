import SwiftUI
import AppKit
import MiNoteLibrary

@main
struct MiNoteMacApp: App {
    @StateObject private var viewModel = NotesViewModel()
    @Environment(\.openWindow) private var openWindow
    
    init() {
        // 设置应用强调色为黄色
        // 注意：根据 macOS 官方文档，应用强调色只有在系统设置中
        // "系统设置 > 外观 > 强调色" 设置为"多色"时才会生效。
        // 如果系统强调色设置为其他颜色（如紫色、蓝色），系统会使用用户选择的颜色。
        // 
        // 要让应用显示黄色强调色，用户需要：
        // 1. 打开"系统设置"
        // 2. 点击"外观"
        // 3. 将"强调色"设置为"多色"
        // 
        // 然后应用会自动使用我们在 Info.plist 中设置的黄色强调色。
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .accentColor(.yellow)  // 设置应用强调色为黄色（当系统强调色为"多色"时生效）
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
                .accentColor(.yellow)  // 设置设置窗口的强调色为黄色
        }
        
        Window("调试设置", id: "debug-settings") {
            DebugSettingsView()
                .accentColor(.yellow)  // 设置调试设置窗口的强调色为黄色
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        
        // 笔记详情窗口（用于在新窗口打开笔记）
        WindowGroup("备忘录", id: "note-detail") {
            NoteDetailWindowView()
                .accentColor(.yellow)  // 设置笔记详情窗口的强调色为黄色
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)
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
        
        if let window = NSApp.windows.first(where: { $0.isKeyWindow }),
           let contentView = window.contentView {
            sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: NSRectEdge.minY)
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
                    try note.content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
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
