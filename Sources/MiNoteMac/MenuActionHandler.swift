import AppKit
import MiNoteLibrary

/// 菜单动作处理器
/// 负责处理应用程序菜单的各种动作
@MainActor
class MenuActionHandler {
    
    // MARK: - 属性
    
    /// 主窗口控制器的弱引用
    private weak var mainWindowController: MainWindowController?
    
    /// 窗口管理器
    private let windowManager: WindowManager
    
    // MARK: - 初始化
    
    /// 初始化菜单动作处理器
    /// - Parameters:
    ///   - mainWindowController: 主窗口控制器
    ///   - windowManager: 窗口管理器
    init(mainWindowController: MainWindowController? = nil, windowManager: WindowManager) {
        self.mainWindowController = mainWindowController
        self.windowManager = windowManager
        print("菜单动作处理器初始化")
    }
    
    // MARK: - 公共方法
    
    /// 更新主窗口控制器引用
    /// - Parameter controller: 主窗口控制器
    func updateMainWindowController(_ controller: MainWindowController?) {
        self.mainWindowController = controller
    }
    
    // MARK: - 应用程序菜单动作
    
    /// 显示关于面板
    func showAboutPanel(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "小米笔记"
        alert.informativeText = "版本 2.1.0\n\n一个简洁的笔记应用程序，支持小米笔记同步。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 显示设置窗口
    func showSettings(_ sender: Any?) {
        print("显示设置窗口")
        
        // 创建设置窗口控制器
        let settingsWindowController = MiNoteLibrary.SettingsWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    /// 显示帮助
    func showHelp(_ sender: Any?) {
        print("显示帮助")
        // 这里可以打开帮助文档
        // 暂时使用控制台输出
    }
    
    // MARK: - 窗口菜单动作
    
    /// 创建新窗口
    func createNewWindow(_ sender: Any?) {
        windowManager.createNewWindow()
    }
    
    // MARK: - 编辑菜单动作
    
    /// 撤销
    func undo(_ sender: Any?) {
        print("撤销")
        // 转发到主窗口控制器
        mainWindowController?.undo(sender)
    }
    
    /// 重做
    func redo(_ sender: Any?) {
        print("重做")
        // 转发到主窗口控制器
        mainWindowController?.redo(sender)
    }
    
    /// 剪切
    func cut(_ sender: Any?) {
        print("剪切")
        // 转发到主窗口控制器
        mainWindowController?.cut(sender)
    }
    
    /// 复制
    func copy(_ sender: Any?) {
        print("复制")
        // 转发到主窗口控制器
        mainWindowController?.copy(sender)
    }
    
    /// 粘贴
    func paste(_ sender: Any?) {
        print("粘贴")
        // 转发到主窗口控制器
        mainWindowController?.paste(sender)
    }
    
    /// 全选
    func selectAll(_ sender: Any?) {
        print("全选")
        // 转发到主窗口控制器
        mainWindowController?.selectAll(sender)
    }
    
    // MARK: - 格式菜单动作
    
    /// 切换粗体
    func toggleBold(_ sender: Any?) {
        print("切换粗体")
        // 转发到主窗口控制器
        mainWindowController?.toggleBold(sender)
    }
    
    /// 切换斜体
    func toggleItalic(_ sender: Any?) {
        print("切换斜体")
        // 转发到主窗口控制器
        mainWindowController?.toggleItalic(sender)
    }
    
    /// 切换下划线
    func toggleUnderline(_ sender: Any?) {
        print("切换下划线")
        // 转发到主窗口控制器
        mainWindowController?.toggleUnderline(sender)
    }
    
    /// 切换删除线
    func toggleStrikethrough(_ sender: Any?) {
        print("切换删除线")
        // 转发到主窗口控制器
        mainWindowController?.toggleStrikethrough(sender)
    }
    
    /// 增大字体
    func increaseFontSize(_ sender: Any?) {
        print("增大字体")
        // 转发到主窗口控制器
        mainWindowController?.increaseFontSize(sender)
    }
    
    /// 减小字体
    func decreaseFontSize(_ sender: Any?) {
        print("减小字体")
        // 转发到主窗口控制器
        mainWindowController?.decreaseFontSize(sender)
    }
    
    /// 增加缩进
    func increaseIndent(_ sender: Any?) {
        print("增加缩进")
        // 转发到主窗口控制器
        mainWindowController?.increaseIndent(sender)
    }
    
    /// 减少缩进
    func decreaseIndent(_ sender: Any?) {
        print("减少缩进")
        // 转发到主窗口控制器
        mainWindowController?.decreaseIndent(sender)
    }
    
    /// 居左对齐
    func alignLeft(_ sender: Any?) {
        print("居左对齐")
        // 转发到主窗口控制器
        mainWindowController?.alignLeft(sender)
    }
    
    /// 居中对齐
    func alignCenter(_ sender: Any?) {
        print("居中对齐")
        // 转发到主窗口控制器
        mainWindowController?.alignCenter(sender)
    }
    
    /// 居右对齐
    func alignRight(_ sender: Any?) {
        print("居右对齐")
        // 转发到主窗口控制器
        mainWindowController?.alignRight(sender)
    }
    
    /// 切换无序列表
    func toggleBulletList(_ sender: Any?) {
        print("切换无序列表")
        // 转发到主窗口控制器
        mainWindowController?.toggleBulletList(sender)
    }
    
    /// 切换有序列表
    func toggleNumberedList(_ sender: Any?) {
        print("切换有序列表")
        // 转发到主窗口控制器
        mainWindowController?.toggleNumberedList(sender)
    }
    
    /// 切换复选框列表
    func toggleCheckboxList(_ sender: Any?) {
        print("切换复选框列表")
        // 转发到主窗口控制器
        mainWindowController?.toggleCheckboxList(sender)
    }
    
    /// 设置大标题
    func setHeading1(_ sender: Any?) {
        print("设置大标题")
        // 转发到主窗口控制器
        mainWindowController?.setHeading1(sender)
    }
    
    /// 设置二级标题
    func setHeading2(_ sender: Any?) {
        print("设置二级标题")
        // 转发到主窗口控制器
        mainWindowController?.setHeading2(sender)
    }
    
    /// 设置三级标题
    func setHeading3(_ sender: Any?) {
        print("设置三级标题")
        // 转发到主窗口控制器
        mainWindowController?.setHeading3(sender)
    }
    
    /// 设置正文
    func setBodyText(_ sender: Any?) {
        print("设置正文")
        // 转发到主窗口控制器
        mainWindowController?.setBodyText(sender)
    }
    
    // MARK: - 其他菜单动作
    
    /// 显示调试设置窗口
    func showDebugSettings(_ sender: Any?) {
        print("显示调试设置窗口")
        
        // 创建调试窗口控制器
        let debugWindowController = MiNoteLibrary.DebugWindowController(viewModel: mainWindowController?.viewModel)
        
        // 显示窗口
        debugWindowController.showWindow(nil)
        debugWindowController.window?.makeKeyAndOrderFront(nil)
    }
    
    /// 显示登录sheet
    func showLogin(_ sender: Any?) {
        print("显示登录sheet")
        
        // 通过主窗口控制器显示登录sheet
        mainWindowController?.showLogin(sender)
    }
    
    /// 显示Cookie刷新sheet
    func showCookieRefresh(_ sender: Any?) {
        print("显示Cookie刷新sheet")
        
        // 通过主窗口控制器显示Cookie刷新sheet
        mainWindowController?.showCookieRefresh(sender)
    }
    
    /// 显示离线操作
    func showOfflineOperations(_ sender: Any?) {
        print("显示离线操作")
        // 这里可以打开离线操作窗口
        // 暂时使用控制台输出
    }
    
    // MARK: - 文件菜单新增动作
    
    /// 创建新笔记
    func createNewNote(_ sender: Any?) {
        print("创建新笔记")
        // 转发到主窗口控制器
        mainWindowController?.createNewNote(sender)
    }
    
    /// 创建新文件夹
    func createNewFolder(_ sender: Any?) {
        print("创建新文件夹")
        // 转发到主窗口控制器
        mainWindowController?.createNewFolder(sender)
    }
    
    /// 共享笔记
    func shareNote(_ sender: Any?) {
        print("共享笔记")
        // 转发到主窗口控制器
        mainWindowController?.shareNote(sender)
    }
    
    /// 导入笔记
    func importNotes(_ sender: Any?) {
        print("导入笔记")
        // 实现导入功能
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.text, .plainText, .rtf]
        panel.message = "选择要导入的笔记文件"
        
        panel.begin { [weak self] response in
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
                                folderId: self?.mainWindowController?.viewModel?.selectedFolder?.id ?? "0",
                                isStarred: false,
                                createdAt: Date(),
                                updatedAt: Date()
                            )
                            
                            try await self?.mainWindowController?.viewModel?.createNote(newNote)
                        } catch {
                            print("[MenuActionHandler] 导入笔记失败: \(error)")
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
    func exportNote(_ sender: Any?) {
        print("导出笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = "请先选择一个要导出的笔记"
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.text]
        panel.nameFieldStringValue = note.title.isEmpty ? "无标题" : note.title
        panel.message = "导出笔记"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try note.content.write(to: url, atomically: true, encoding: String.Encoding.utf8)
                } catch {
                    print("[MenuActionHandler] 导出笔记失败: \(error)")
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
    func toggleStarNote(_ sender: Any?) {
        print("置顶/取消置顶笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else { return }
        mainWindowController?.viewModel?.toggleStar(note)
    }
    
    /// 复制笔记
    func copyNote(_ sender: Any?) {
        print("复制笔记")
        guard let note = mainWindowController?.viewModel?.selectedNote else { return }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }
    
    // MARK: - 清理
    
    deinit {
        print("菜单动作处理器释放")
    }
}
