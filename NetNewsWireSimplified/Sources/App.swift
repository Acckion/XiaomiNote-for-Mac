import AppKit
import SwiftUI

@main
struct NetNewsWireSimplifiedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    appDelegate.createNewWindow()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        createNewWindow()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func createNewWindow() {
        if mainWindowController == nil {
            let viewModel = NotesViewModel()
            mainWindowController = MainWindowController(viewModel: viewModel)
        }
        
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

struct ContentView: View {
    var body: some View {
        Text("NetNewsWire Simplified")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
