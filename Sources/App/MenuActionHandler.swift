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
        let settingsWindowController = SettingsWindowController(viewModel: mainWindowController?.viewModel)
        
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
    
    // MARK: - 格式菜单动作（Apple Notes 风格）
    
    /// 设置标题（Apple Notes 风格）
    /// - Requirements: 4.1
    @objc func setHeading(_ sender: Any?) {
        print("设置标题")
        mainWindowController?.setHeading1(sender)
    }
    
    /// 设置小标题
    /// - Requirements: 4.2
    @objc func setSubheading(_ sender: Any?) {
        print("设置小标题")
        mainWindowController?.setHeading2(sender)
    }
    
    /// 设置副标题
    /// - Requirements: 4.3
    @objc func setSubtitle(_ sender: Any?) {
        print("设置副标题")
        mainWindowController?.setHeading3(sender)
    }
    
    /// 切换有序列表
    /// - Requirements: 4.5
    @objc func toggleOrderedList(_ sender: Any?) {
        print("切换有序列表")
        mainWindowController?.toggleNumberedList(sender)
    }
    
    /// 切换无序列表
    /// - Requirements: 4.6
    @objc func toggleUnorderedList(_ sender: Any?) {
        print("切换无序列表")
        mainWindowController?.toggleBulletList(sender)
    }
    
    /// 切换块引用
    /// - Requirements: 4.9
    @objc func toggleBlockQuote(_ sender: Any?) {
        print("切换块引用")
        mainWindowController?.toggleBlockQuote(sender)
    }
    
    // MARK: - 核对清单动作
    
    /// 切换核对清单
    /// - Requirements: 5.1
    @objc func toggleChecklist(_ sender: Any?) {
        print("切换核对清单")
        mainWindowController?.toggleCheckboxList(sender)
    }
    
    /// 标记为已勾选
    /// - Requirements: 5.2
    @objc func markAsChecked(_ sender: Any?) {
        print("标记为已勾选")
        mainWindowController?.markAsChecked(sender)
    }
    
    /// 全部勾选
    /// - Requirements: 5.4
    @objc func checkAll(_ sender: Any?) {
        print("全部勾选")
        mainWindowController?.checkAll(sender)
    }
    
    /// 全部取消勾选
    /// - Requirements: 5.5
    @objc func uncheckAll(_ sender: Any?) {
        print("全部取消勾选")
        mainWindowController?.uncheckAll(sender)
    }
    
    /// 将勾选的项目移到底部
    /// - Requirements: 5.6
    @objc func moveCheckedToBottom(_ sender: Any?) {
        print("将勾选的项目移到底部")
        mainWindowController?.moveCheckedToBottom(sender)
    }
    
    /// 删除已勾选项目
    /// - Requirements: 5.7
    @objc func deleteCheckedItems(_ sender: Any?) {
        print("删除已勾选项目")
        mainWindowController?.deleteCheckedItems(sender)
    }
    
    /// 向上移动项目
    /// - Requirements: 5.10
    @objc func moveItemUp(_ sender: Any?) {
        print("向上移动项目")
        mainWindowController?.moveItemUp(sender)
    }
    
    /// 向下移动项目
    /// - Requirements: 5.11
    @objc func moveItemDown(_ sender: Any?) {
        print("向下移动项目")
        mainWindowController?.moveItemDown(sender)
    }
    
    // MARK: - 外观动作
    
    /// 切换浅色背景
    /// - Requirements: 6.2
    @objc func toggleLightBackground(_ sender: Any?) {
        print("切换浅色背景")
        mainWindowController?.toggleLightBackground(sender)
    }
    
    /// 切换高亮
    /// - Requirements: 6.9
    @objc func toggleHighlight(_ sender: Any?) {
        print("切换高亮")
        mainWindowController?.toggleHighlight(sender)
    }
    
    // MARK: - 其他菜单动作
    
    /// 显示调试设置窗口
    func showDebugSettings(_ sender: Any?) {
        print("显示调试设置窗口")
        
        // 创建调试窗口控制器
        let debugWindowController = DebugWindowController(viewModel: mainWindowController?.viewModel)
        
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
    
    // MARK: - 文件菜单新增动作（Requirements: 2.1-2.20）
    
    /// 创建智能文件夹
    /// - Requirements: 2.3
    func createSmartFolder(_ sender: Any?) {
        print("创建智能文件夹")
        // 智能文件夹功能待实现
        let alert = NSAlert()
        alert.messageText = "功能开发中"
        alert.informativeText = "智能文件夹功能正在开发中，敬请期待。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 导入 Markdown 文件
    /// - Requirements: 2.10
    func importMarkdown(_ sender: Any?) {
        print("导入 Markdown")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
        panel.message = "选择要导入的 Markdown 文件"
        
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
                            print("[MenuActionHandler] 成功导入 Markdown 文件: \(fileName)")
                        } catch {
                            print("[MenuActionHandler] 导入 Markdown 失败: \(error)")
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
    
    /// 导出为 PDF
    /// - Requirements: 2.12, 2.13
    func exportAsPDF(_ sender: Any?) {
        print("导出为 PDF")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".pdf"
        panel.message = "导出笔记为 PDF"
        
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.exportNoteToPDF(note: note, url: url)
            }
        }
    }
    
    /// 导出为 Markdown
    /// - Requirements: 2.12, 2.13
    func exportAsMarkdown(_ sender: Any?) {
        print("导出为 Markdown")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".md"
        panel.message = "导出笔记为 Markdown"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    // 将笔记内容转换为 Markdown 格式
                    let markdownContent = self.convertToMarkdown(note: note)
                    try markdownContent.write(to: url, atomically: true, encoding: .utf8)
                    print("[MenuActionHandler] 成功导出 Markdown: \(url.path)")
                } catch {
                    print("[MenuActionHandler] 导出 Markdown 失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /// 导出为纯文本
    /// - Requirements: 2.12, 2.13
    func exportAsPlainText(_ sender: Any?) {
        print("导出为纯文本")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".txt"
        panel.message = "导出笔记为纯文本"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    // 组合标题和内容
                    let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    print("[MenuActionHandler] 成功导出纯文本: \(url.path)")
                } catch {
                    print("[MenuActionHandler] 导出纯文本失败: \(error)")
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "导出失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    /// 添加到私密笔记
    /// - Requirements: 2.16
    func addToPrivateNotes(_ sender: Any?) {
        print("添加到私密笔记")
        // 私密笔记功能待实现
        let alert = NSAlert()
        alert.messageText = "功能开发中"
        alert.informativeText = "私密笔记功能正在开发中，敬请期待。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 复制笔记（创建副本）
    /// - Requirements: 2.17
    func duplicateNote(_ sender: Any?) {
        print("复制笔记（创建副本）")
        guard let note = mainWindowController?.viewModel?.selectedNote else {
            showNoNoteSelectedAlert()
            return
        }
        
        Task {
            do {
                // 创建笔记副本
                let duplicatedNote = Note(
                    id: UUID().uuidString,
                    title: note.title.isEmpty ? "无标题 副本" : "\(note.title) 副本",
                    content: note.content,
                    folderId: note.folderId,
                    isStarred: false,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                
                try await mainWindowController?.viewModel?.createNote(duplicatedNote)
                print("[MenuActionHandler] 成功复制笔记: \(duplicatedNote.title)")
            } catch {
                print("[MenuActionHandler] 复制笔记失败: \(error)")
                DispatchQueue.main.async {
                    let errorAlert = NSAlert()
                    errorAlert.messageText = "复制失败"
                    errorAlert.informativeText = error.localizedDescription
                    errorAlert.alertStyle = .warning
                    errorAlert.runModal()
                }
            }
        }
    }
    
    // MARK: - 私有辅助方法
    
    /// 显示未选中笔记的提示
    private func showNoNoteSelectedAlert() {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = "请先选择一个笔记"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    /// 将笔记导出为 PDF
    private func exportNoteToPDF(note: Note, url: URL) {
        // 创建打印信息
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 612, height: 792) // Letter size
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        
        // 创建文本视图用于渲染
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        textView.string = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        
        // 创建 PDF 数据
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        
        do {
            try pdfData.write(to: url)
            print("[MenuActionHandler] 成功导出 PDF: \(url.path)")
        } catch {
            print("[MenuActionHandler] 导出 PDF 失败: \(error)")
            let errorAlert = NSAlert()
            errorAlert.messageText = "导出失败"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }
    
    /// 将笔记转换为 Markdown 格式
    private func convertToMarkdown(note: Note) -> String {
        var markdown = ""
        
        // 添加标题
        if !note.title.isEmpty {
            markdown += "# \(note.title)\n\n"
        }
        
        // 添加内容（简单处理，实际可能需要更复杂的 HTML 到 Markdown 转换）
        markdown += note.content
        
        return markdown
    }

    // MARK: - 查找功能

    /// 显示查找面板
    func showFindPanel(_ sender: Any?) {
        print("显示查找面板")
        print("[DEBUG] MenuActionHandler - mainWindowController: \(mainWindowController != nil)")
        if let controller = mainWindowController {
            print("[DEBUG] MenuActionHandler - 调用主窗口控制器的showFindPanel")
            controller.showFindPanel(sender)
        } else {
            print("[ERROR] MenuActionHandler - mainWindowController为nil")
        }
    }

    /// 显示查找和替换面板
    func showFindAndReplacePanel(_ sender: Any?) {
        print("显示查找和替换面板")
        mainWindowController?.showFindAndReplacePanel(sender)
    }

    /// 查找下一个
    func findNext(_ sender: Any?) {
        print("查找下一个")
        mainWindowController?.findNext(sender)
    }

    /// 查找上一个
    func findPrevious(_ sender: Any?) {
        print("查找上一个")
        mainWindowController?.findPrevious(sender)
    }
    
    // MARK: - 附件操作
    
    /// 附加文件
    /// - Requirements: 3.12
    @objc func attachFile(_ sender: Any?) {
        print("附加文件")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择要附加的文件"
        
        panel.begin { [weak self] response in
            if response == .OK {
                for url in panel.urls {
                    print("[MenuActionHandler] 附加文件: \(url.path)")
                    // 将文件附加到当前笔记
                    self?.mainWindowController?.attachFile(url)
                }
            }
        }
    }
    
    /// 添加链接
    /// - Requirements: 3.13
    @objc func addLink(_ sender: Any?) {
        print("添加链接")
        // 显示添加链接对话框
        let alert = NSAlert()
        alert.messageText = "添加链接"
        alert.informativeText = "请输入链接地址："
        alert.alertStyle = .informational
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputField.placeholderString = "https://example.com"
        alert.accessoryView = inputField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let urlString = inputField.stringValue
            if !urlString.isEmpty {
                print("[MenuActionHandler] 添加链接: \(urlString)")
                mainWindowController?.addLink(urlString)
            }
        }
    }
    
    // MARK: - 显示菜单动作（Requirements: 8.1-8.5, 9.1-9.8, 10.1-10.4, 11.1-11.5）
    
    /// 设置列表视图
    /// - Requirements: 8.1
    @objc func setListView(_ sender: Any?) {
        print("设置列表视图")
        ViewOptionsManager.shared.setViewMode(.list)
    }
    
    /// 设置画廊视图
    /// - Requirements: 8.2
    @objc func setGalleryView(_ sender: Any?) {
        print("设置画廊视图")
        ViewOptionsManager.shared.setViewMode(.gallery)
    }
    
    /// 切换文件夹可见性
    /// - Requirements: 9.2
    @objc func toggleFolderVisibility(_ sender: Any?) {
        print("切换文件夹可见性")
        // 通过 MainWindowController 切换侧边栏
        if let window = NSApp.mainWindow,
           let splitViewController = window.contentViewController as? NSSplitViewController,
           splitViewController.splitViewItems.count > 0 {
            let sidebarItem = splitViewController.splitViewItems[0]
            sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
        }
    }
    
    /// 切换笔记数量显示
    /// - Requirements: 9.3
    @objc func toggleNoteCount(_ sender: Any?) {
        print("切换笔记数量显示")
        // TODO: 实现笔记数量显示切换功能
        // 这需要在 ViewOptionsManager 中添加相应的状态和方法
    }
    
    /// 放大
    /// - Requirements: 10.2
    @objc func zoomIn(_ sender: Any?) {
        print("放大")
        mainWindowController?.zoomIn(sender)
    }
    
    /// 缩小
    /// - Requirements: 10.3
    @objc func zoomOut(_ sender: Any?) {
        print("缩小")
        mainWindowController?.zoomOut(sender)
    }
    
    /// 实际大小
    /// - Requirements: 10.4
    @objc func actualSize(_ sender: Any?) {
        print("实际大小")
        mainWindowController?.actualSize(sender)
    }
    
    /// 展开区域
    /// - Requirements: 11.2
    @objc func expandSection(_ sender: Any?) {
        print("展开区域")
        mainWindowController?.expandSection(sender)
    }
    
    /// 展开所有区域
    /// - Requirements: 11.3
    @objc func expandAllSections(_ sender: Any?) {
        print("展开所有区域")
        mainWindowController?.expandAllSections(sender)
    }
    
    /// 折叠区域
    /// - Requirements: 11.4
    @objc func collapseSection(_ sender: Any?) {
        print("折叠区域")
        mainWindowController?.collapseSection(sender)
    }
    
    /// 折叠所有区域
    /// - Requirements: 11.5
    @objc func collapseAllSections(_ sender: Any?) {
        print("折叠所有区域")
        mainWindowController?.collapseAllSections(sender)
    }

    // MARK: - 清理

    deinit {
        print("菜单动作处理器释放")
    }
}
