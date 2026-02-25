//
//  NoteCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 新建笔记命令
    public struct CreateNoteCommand: AppCommand {
        public let folderId: String?

        public init(folderId: String?) {
            self.folderId = folderId
        }

        public func execute(with context: CommandContext) {
            let targetFolderId = folderId ?? context.coordinator.folderState.selectedFolderId ?? "0"
            Task {
                await context.coordinator.noteListState.createNewNote(inFolder: targetFolderId)
            }
        }
    }

    /// 删除笔记命令
    public struct DeleteNoteCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }

            let alert = NSAlert()
            alert.messageText = "删除笔记"
            alert.informativeText = "确定要删除笔记 \"\(note.title)\" 吗？此操作无法撤销。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                Task {
                    await context.coordinator.noteListState.deleteNote(note)
                }
            }
        }
    }

    /// 切换星标命令
    public struct ToggleStarCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }
            Task {
                await context.coordinator.noteListState.toggleStar(note)
            }
        }
    }

    /// 分享笔记命令
    public struct ShareNoteCommand: AppCommand, @unchecked Sendable {
        public let window: NSWindow?

        public init(window: NSWindow?) {
            self.window = window
        }

        public func execute(with context: CommandContext) {
            guard let note = context.coordinator.noteListState.selectedNote else { return }

            let sharingService = NSSharingServicePicker(items: [
                note.title,
                note.content,
            ])

            if let window,
               let contentView = window.contentView
            {
                sharingService.show(relativeTo: NSRect.zero, of: contentView, preferredEdge: .minY)
            }
        }
    }

    /// 新建文件夹命令
    public struct CreateFolderCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
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
                        await context.coordinator.folderState.createFolder(name: folderName)
                    }
                }
            }
        }
    }
#endif
