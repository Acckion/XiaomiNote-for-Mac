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
        
        Settings {
            SettingsView(viewModel: viewModel)
                .accentColor(Color.yellow)  // 设置设置窗口的强调色为黄色
        }
        
        Window("调试设置", id: "debug-settings") {
            DebugSettingsView()
                .accentColor(Color.yellow)  // 设置调试设置窗口的强调色为黄色
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        
        // 笔记详情窗口（用于在新窗口打开笔记）
        WindowGroup("备忘录", id: "note-detail") {
            NoteDetailWindowView()
                .accentColor(Color.yellow)  // 设置笔记详情窗口的强调色为黄色
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 600)
    }
}
