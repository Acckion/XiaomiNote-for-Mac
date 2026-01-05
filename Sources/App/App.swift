import AppKit

// 应用程序入口点
@main
struct MiNoteMacApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
