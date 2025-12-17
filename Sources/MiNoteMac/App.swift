import SwiftUI
import AppKit

@main
struct MiNoteMacApp: App {
    @StateObject private var viewModel = NotesViewModel()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // 激活应用程序
                    NSApp.activate(ignoringOtherApps: true)
                    print("应用程序窗口已显示")
                    // 设置窗口标题，去除 MiNoteMac 字样
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.first {
                            window.title = "备忘录"
                        }
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建笔记") {
                    viewModel.createNewNote()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandGroup(after: .windowSize) {
                Divider()
                
                Button("调试设置") {
                    openDebugSettings()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            
            // 在"视图"菜单中添加调试设置入口
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
}
