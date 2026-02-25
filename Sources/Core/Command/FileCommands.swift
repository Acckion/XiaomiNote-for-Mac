//
//  FileCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit
    import UniformTypeIdentifiers

    // MARK: - 导入命令

    /// 导入笔记
    public struct ImportNotesCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
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
                                await createImportedNote(title: fileName, content: content, context: context)
                            } catch {
                                await MainActor.run {
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
    }

    /// 导入 Markdown 文件
    public struct ImportMarkdownCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!]
            panel.message = "选择要导入的 Markdown 文件"

            panel.begin { response in
                if response == .OK {
                    for url in panel.urls {
                        Task {
                            do {
                                let content = try String(contentsOf: url, encoding: .utf8)
                                let fileName = url.deletingPathExtension().lastPathComponent
                                await createImportedNote(title: fileName, content: content, context: context)
                            } catch {
                                await MainActor.run {
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
    }

    // MARK: - 导出命令

    /// 导出笔记
    public struct ExportNoteCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else {
                showNoNoteSelectedAlert()
                return
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.text]
            panel.nameFieldStringValue = note.title.isEmpty ? "无标题" : note.title
            panel.message = "导出笔记"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try note.content.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "导出失败"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.alertStyle = .warning
                        errorAlert.runModal()
                    }
                }
            }
        }
    }

    /// 导出为 PDF
    public struct ExportAsPDFCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else {
                showNoNoteSelectedAlert()
                return
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = (note.title.isEmpty ? "无标题" : note.title) + ".pdf"
            panel.message = "导出笔记为 PDF"

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    exportNoteToPDF(note: note, url: url)
                }
            }
        }
    }

    /// 导出为 Markdown
    public struct ExportAsMarkdownCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else {
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
                        let markdownContent = convertToMarkdown(note: note)
                        try markdownContent.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "导出失败"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.alertStyle = .warning
                        errorAlert.runModal()
                    }
                }
            }
        }
    }

    /// 导出为纯文本
    public struct ExportAsPlainTextCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else {
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
                        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
                        try content.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        let errorAlert = NSAlert()
                        errorAlert.messageText = "导出失败"
                        errorAlert.informativeText = error.localizedDescription
                        errorAlert.alertStyle = .warning
                        errorAlert.runModal()
                    }
                }
            }
        }
    }

    // MARK: - 笔记操作命令

    /// 复制笔记（创建副本）
    public struct DuplicateNoteCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else {
                showNoNoteSelectedAlert()
                return
            }

            Task {
                await context.coordinator.noteListState.createNewNote(inFolder: note.folderId)
            }
        }
    }

    /// 复制笔记内容到剪贴板
    public struct CopyNoteCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
            pasteboard.setString(content, forType: .string)
        }
    }

    // MARK: - 占位命令

    /// 创建智能文件夹（功能开发中）
    public struct CreateSmartFolderCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            let alert = NSAlert()
            alert.messageText = "功能开发中"
            alert.informativeText = "智能文件夹功能正在开发中，敬请期待。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    /// 添加到私密笔记（功能开发中）
    public struct AddToPrivateNotesCommand: AppCommand {
        public init() {}

        public func execute(with _: CommandContext) {
            let alert = NSAlert()
            alert.messageText = "功能开发中"
            alert.informativeText = "私密笔记功能正在开发中，敬请期待。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    // MARK: - 私有辅助函数

    /// 显示未选中笔记的提示
    @MainActor private func showNoNoteSelectedAlert() {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = "请先选择一个笔记"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    /// 创建导入笔记并选中
    @MainActor private func createImportedNote(title: String, content: String, context: CommandContext) async {
        let coordinator = context.coordinator
        let folderId = coordinator.folderState.selectedFolder?.id ?? "0"
        let normalizedContent = content.isEmpty ? "<new-format/><text indent=\"1\"></text>" : content

        do {
            let note = try await coordinator.noteStore.createNoteOffline(
                title: title,
                content: normalizedContent,
                folderId: folderId
            )
            coordinator.noteListState.selectedNote = note
        } catch {
            LogService.shared.error(.app, "导入笔记落库失败: \(error)")
        }
    }

    /// 将笔记导出为 PDF
    @MainActor private func exportNoteToPDF(note: Note, url: URL) {
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 612, height: 792)
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        textView.string = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"

        let pdfData = textView.dataWithPDF(inside: textView.bounds)

        do {
            try pdfData.write(to: url)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "导出失败"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }

    /// 将笔记转换为 Markdown 格式
    @MainActor private func convertToMarkdown(note: Note) -> String {
        var markdown = ""

        if !note.title.isEmpty {
            markdown += "# \(note.title)\n\n"
        }

        markdown += note.content

        return markdown
    }
#endif
