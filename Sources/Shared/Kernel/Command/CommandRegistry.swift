//
//  CommandRegistry.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    /// 菜单分组枚举
    enum MenuGroup: String, CaseIterable, Sendable {
        /// 文件菜单
        case fileNew, fileShare, fileImport, fileExport, fileNoteActions
        // 格式菜单
        case formatParagraph, formatChecklist, formatChecklistMore
        case formatMoveItem, formatAppearance
        case formatFont, formatAlignment, formatIndent
        /// 编辑菜单
        case editAttachment
        /// 显示菜单
        case viewMode, viewFolderOptions, viewZoom, viewSections
        /// 窗口菜单
        case windowLayout, windowTile, windowNote
        /// 杂项
        case misc
    }

    /// 菜单命令条目
    struct MenuCommandEntry: Sendable {
        let tag: MenuItemTag
        let title: String
        let commandType: AppCommand.Type
        let keyEquivalent: String
        let modifiers: NSEvent.ModifierFlags
        let symbolName: String?
        let group: MenuGroup
    }

    /// 命令注册表
    @MainActor
    final class CommandRegistry {
        static let shared = CommandRegistry()
        private var entries: [MenuItemTag: MenuCommandEntry] = [:]

        private init() {
            registerAll()
        }

        func entry(for tag: MenuItemTag) -> MenuCommandEntry? {
            entries[tag]
        }

        func entries(for group: MenuGroup) -> [MenuCommandEntry] {
            entries.values
                .filter { $0.group == group }
                .sorted { $0.tag.rawValue < $1.tag.rawValue }
        }

        private func register(_ entry: MenuCommandEntry) {
            entries[entry.tag] = entry
        }

        // MARK: - 注册所有命令

        private func registerAll() {
            registerFileMenuCommands()
            registerFormatMenuCommands()
            registerEditMenuCommands()
            registerViewMenuCommands()
            registerWindowMenuCommands()
            registerMiscCommands()
        }

        private func registerFileMenuCommands() {
            // fileNew 分组
            register(MenuCommandEntry(
                tag: .newNote,
                title: "新建笔记",
                commandType: CreateNoteCommand.self,
                keyEquivalent: "n",
                modifiers: [.command],
                symbolName: "square.and.pencil",
                group: .fileNew
            ))
            register(MenuCommandEntry(
                tag: .newFolder,
                title: "新建文件夹",
                commandType: CreateFolderCommand.self,
                keyEquivalent: "n",
                modifiers: [.command, .shift],
                symbolName: "folder.badge.plus",
                group: .fileNew
            ))
            register(MenuCommandEntry(
                tag: .newSmartFolder,
                title: "新建智能文件夹",
                commandType: CreateSmartFolderCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "folder.badge.gearshape",
                group: .fileNew
            ))

            // fileShare 分组
            register(MenuCommandEntry(
                tag: .share,
                title: "共享",
                commandType: ShareNoteCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "square.and.arrow.up",
                group: .fileShare
            ))

            // fileImport 分组
            register(MenuCommandEntry(
                tag: .importNotes,
                title: "导入至笔记...",
                commandType: ImportNotesCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "square.and.arrow.down",
                group: .fileImport
            ))
            register(MenuCommandEntry(
                tag: .importMarkdown,
                title: "导入 Markdown...",
                commandType: ImportMarkdownCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "doc.text",
                group: .fileImport
            ))

            // fileExport 分组
            register(MenuCommandEntry(
                tag: .exportAsPDF,
                title: "PDF...",
                commandType: ExportAsPDFCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "doc.richtext",
                group: .fileExport
            ))
            register(MenuCommandEntry(
                tag: .exportAsMarkdown,
                title: "Markdown...",
                commandType: ExportAsMarkdownCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "doc.text",
                group: .fileExport
            ))
            register(MenuCommandEntry(
                tag: .exportAsPlainText,
                title: "纯文本...",
                commandType: ExportAsPlainTextCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "doc.plaintext",
                group: .fileExport
            ))

            // fileNoteActions 分组
            register(MenuCommandEntry(
                tag: .toggleStar,
                title: "置顶笔记",
                commandType: ToggleStarCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "pin",
                group: .fileNoteActions
            ))
            register(MenuCommandEntry(
                tag: .addToPrivateNotes,
                title: "添加到私密笔记",
                commandType: AddToPrivateNotesCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "lock",
                group: .fileNoteActions
            ))
            register(MenuCommandEntry(
                tag: .duplicateNote,
                title: "复制笔记",
                commandType: DuplicateNoteCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "doc.on.doc",
                group: .fileNoteActions
            ))
        }

        private func registerFormatMenuCommands() {
            // formatParagraph 分组
            register(MenuCommandEntry(
                tag: .heading,
                title: "大标题",
                commandType: SetHeadingCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "textformat.size.larger",
                group: .formatParagraph
            ))
            register(MenuCommandEntry(
                tag: .subheading,
                title: "二级标题",
                commandType: SetSubheadingCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "textformat.size",
                group: .formatParagraph
            ))
            register(MenuCommandEntry(
                tag: .subtitle,
                title: "三级标题",
                commandType: SetSubtitleCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "textformat.size.smaller",
                group: .formatParagraph
            ))
            register(MenuCommandEntry(
                tag: .bodyText,
                title: "正文",
                commandType: SetBodyTextCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "text.justify",
                group: .formatParagraph
            ))
            register(MenuCommandEntry(
                tag: .orderedList,
                title: "有序列表",
                commandType: ToggleOrderedListCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "list.number",
                group: .formatParagraph
            ))
            register(MenuCommandEntry(
                tag: .unorderedList,
                title: "无序列表",
                commandType: ToggleUnorderedListCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "list.bullet",
                group: .formatParagraph
            ))
            register(MenuCommandEntry(
                tag: .blockQuote,
                title: "块引用",
                commandType: ToggleBlockQuoteCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "text.quote",
                group: .formatParagraph
            ))

            // formatChecklist 分组
            register(MenuCommandEntry(
                tag: .checklist,
                title: "核对清单",
                commandType: ToggleCheckboxListCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "checklist",
                group: .formatChecklist
            ))
            register(MenuCommandEntry(
                tag: .markAsChecked,
                title: "标记为已勾选",
                commandType: MarkAsCheckedCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "checkmark.circle",
                group: .formatChecklist
            ))

            // formatChecklistMore 分组
            register(MenuCommandEntry(
                tag: .checkAll,
                title: "全部勾选",
                commandType: CheckAllCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "checkmark.circle.fill",
                group: .formatChecklistMore
            ))
            register(MenuCommandEntry(
                tag: .uncheckAll,
                title: "全部取消勾选",
                commandType: UncheckAllCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "circle",
                group: .formatChecklistMore
            ))
            register(MenuCommandEntry(
                tag: .moveCheckedToBottom,
                title: "将勾选的项目移到底部",
                commandType: MoveCheckedToBottomCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "arrow.down.to.line",
                group: .formatChecklistMore
            ))
            register(MenuCommandEntry(
                tag: .deleteCheckedItems,
                title: "删除已勾选项目",
                commandType: DeleteCheckedItemsCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "trash",
                group: .formatChecklistMore
            ))

            // formatMoveItem 分组
            register(MenuCommandEntry(
                tag: .moveItemUp,
                title: "向上",
                commandType: MoveItemUpCommand.self,
                keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!),
                modifiers: [.control, .command],
                symbolName: "arrow.up",
                group: .formatMoveItem
            ))
            register(MenuCommandEntry(
                tag: .moveItemDown,
                title: "向下",
                commandType: MoveItemDownCommand.self,
                keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!),
                modifiers: [.control, .command],
                symbolName: "arrow.down",
                group: .formatMoveItem
            ))

            // formatAppearance 分组
            register(MenuCommandEntry(
                tag: .lightBackground,
                title: "使用浅色背景显示笔记",
                commandType: ToggleLightBackgroundCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "sun.max",
                group: .formatAppearance
            ))
            register(MenuCommandEntry(
                tag: .highlight,
                title: "高亮",
                commandType: ToggleHighlightCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "highlighter",
                group: .formatAppearance
            ))

            // formatFont 分组
            register(MenuCommandEntry(
                tag: .bold,
                title: "粗体",
                commandType: ToggleBoldCommand.self,
                keyEquivalent: "b",
                modifiers: [.command],
                symbolName: "bold",
                group: .formatFont
            ))
            register(MenuCommandEntry(
                tag: .italic,
                title: "斜体",
                commandType: ToggleItalicCommand.self,
                keyEquivalent: "i",
                modifiers: [.command],
                symbolName: "italic",
                group: .formatFont
            ))
            register(MenuCommandEntry(
                tag: .underline,
                title: "下划线",
                commandType: ToggleUnderlineCommand.self,
                keyEquivalent: "u",
                modifiers: [.command],
                symbolName: "underline",
                group: .formatFont
            ))
            register(MenuCommandEntry(
                tag: .strikethrough,
                title: "删除线",
                commandType: ToggleStrikethroughCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "strikethrough",
                group: .formatFont
            ))
            register(MenuCommandEntry(
                tag: .increaseFontSize,
                title: "增大字号",
                commandType: IncreaseFontSizeCommand.self,
                keyEquivalent: "+",
                modifiers: [.command],
                symbolName: "plus.magnifyingglass",
                group: .formatFont
            ))
            register(MenuCommandEntry(
                tag: .decreaseFontSize,
                title: "减小字号",
                commandType: DecreaseFontSizeCommand.self,
                keyEquivalent: "-",
                modifiers: [.command, .option],
                symbolName: "minus.magnifyingglass",
                group: .formatFont
            ))

            // formatAlignment 分组
            register(MenuCommandEntry(
                tag: .alignLeft,
                title: "左对齐",
                commandType: AlignLeftCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "text.alignleft",
                group: .formatAlignment
            ))
            register(MenuCommandEntry(
                tag: .alignCenter,
                title: "居中",
                commandType: AlignCenterCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "text.aligncenter",
                group: .formatAlignment
            ))
            register(MenuCommandEntry(
                tag: .alignRight,
                title: "右对齐",
                commandType: AlignRightCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "text.alignright",
                group: .formatAlignment
            ))

            // formatIndent 分组
            register(MenuCommandEntry(
                tag: .increaseIndent,
                title: "增大",
                commandType: IncreaseIndentCommand.self,
                keyEquivalent: "]",
                modifiers: [.command],
                symbolName: "increase.indent",
                group: .formatIndent
            ))
            register(MenuCommandEntry(
                tag: .decreaseIndent,
                title: "减小",
                commandType: DecreaseIndentCommand.self,
                keyEquivalent: "[",
                modifiers: [.command],
                symbolName: "decrease.indent",
                group: .formatIndent
            ))
        }

        private func registerEditMenuCommands() {
            // editAttachment 分组
            register(MenuCommandEntry(
                tag: .attachFile,
                title: "附加文件...",
                commandType: AttachFileCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "paperclip",
                group: .editAttachment
            ))
            register(MenuCommandEntry(
                tag: .addLink,
                title: "添加链接...",
                commandType: AddLinkCommand.self,
                keyEquivalent: "k",
                modifiers: [.command],
                symbolName: "link",
                group: .editAttachment
            ))
        }

        private func registerViewMenuCommands() {
            // viewMode 分组
            register(MenuCommandEntry(
                tag: .listView,
                title: "列表视图",
                commandType: SetListViewCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "list.bullet",
                group: .viewMode
            ))
            register(MenuCommandEntry(
                tag: .galleryView,
                title: "画廊视图",
                commandType: SetGalleryViewCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "square.grid.2x2",
                group: .viewMode
            ))

            // viewFolderOptions 分组
            register(MenuCommandEntry(
                tag: .hideFolders,
                title: "隐藏文件夹",
                commandType: ToggleFolderVisibilityCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "folder",
                group: .viewFolderOptions
            ))
            register(MenuCommandEntry(
                tag: .showNoteCount,
                title: "显示笔记数量",
                commandType: ToggleNoteCountCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "number",
                group: .viewFolderOptions
            ))

            // viewZoom 分组
            register(MenuCommandEntry(
                tag: .zoomIn,
                title: "放大",
                commandType: ZoomInCommand.self,
                keyEquivalent: "+",
                modifiers: [.command],
                symbolName: "plus.magnifyingglass",
                group: .viewZoom
            ))
            register(MenuCommandEntry(
                tag: .zoomOut,
                title: "缩小",
                commandType: ZoomOutCommand.self,
                keyEquivalent: "-",
                modifiers: [.command],
                symbolName: "minus.magnifyingglass",
                group: .viewZoom
            ))
            register(MenuCommandEntry(
                tag: .actualSize,
                title: "实际大小",
                commandType: ActualSizeCommand.self,
                keyEquivalent: "0",
                modifiers: [.command],
                symbolName: "1.magnifyingglass",
                group: .viewZoom
            ))

            // viewSections 分组
            register(MenuCommandEntry(
                tag: .expandSection,
                title: "展开区域",
                commandType: ExpandSectionCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "chevron.down",
                group: .viewSections
            ))
            register(MenuCommandEntry(
                tag: .expandAllSections,
                title: "展开所有区域",
                commandType: ExpandAllSectionsCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "chevron.down.2",
                group: .viewSections
            ))
            register(MenuCommandEntry(
                tag: .collapseSection,
                title: "折叠区域",
                commandType: CollapseSectionCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "chevron.up",
                group: .viewSections
            ))
            register(MenuCommandEntry(
                tag: .collapseAllSections,
                title: "折叠所有区域",
                commandType: CollapseAllSectionsCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "chevron.up.2",
                group: .viewSections
            ))
        }

        private func registerWindowMenuCommands() {
            // windowLayout 分组
            register(MenuCommandEntry(
                tag: .fill,
                title: "填充",
                commandType: FillWindowCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.expand.vertical",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .center,
                title: "居中",
                commandType: CenterWindowCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.center.inset.filled",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .moveToLeftHalf,
                title: "移动到屏幕左半边",
                commandType: MoveWindowToLeftHalfCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.lefthalf.filled",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .moveToRightHalf,
                title: "移动到屏幕右半边",
                commandType: MoveWindowToRightHalfCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.righthalf.filled",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .moveToTopHalf,
                title: "移动到屏幕上半边",
                commandType: MoveWindowToTopHalfCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.tophalf.filled",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .moveToBottomHalf,
                title: "移动到屏幕下半边",
                commandType: MoveWindowToBottomHalfCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.bottomhalf.filled",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .maximizeWindow,
                title: "最大化",
                commandType: MaximizeWindowCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "arrow.up.left.and.arrow.down.right",
                group: .windowLayout
            ))
            register(MenuCommandEntry(
                tag: .restoreWindow,
                title: "恢复",
                commandType: RestoreWindowCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "arrow.down.right.and.arrow.up.left",
                group: .windowLayout
            ))

            // windowTile 分组
            register(MenuCommandEntry(
                tag: .tileToLeft,
                title: "平铺到屏幕左侧",
                commandType: TileWindowToLeftCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.split.2x1.fill",
                group: .windowTile
            ))
            register(MenuCommandEntry(
                tag: .tileToRight,
                title: "平铺到屏幕右侧",
                commandType: TileWindowToRightCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.split.2x1.fill",
                group: .windowTile
            ))

            // windowNote 分组
            register(MenuCommandEntry(
                tag: .createNewWindow,
                title: "新窗口",
                commandType: CreateNewWindowCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.on.rectangle",
                group: .windowNote
            ))
            register(MenuCommandEntry(
                tag: .openNoteInNewWindow,
                title: "在新窗口中打开笔记",
                commandType: OpenNoteInNewWindowCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "rectangle.on.rectangle",
                group: .windowNote
            ))
        }

        private func registerMiscCommands() {
            register(MenuCommandEntry(
                tag: .showSettings,
                title: "设置...",
                commandType: ShowSettingsCommand.self,
                keyEquivalent: ",",
                modifiers: [.command],
                symbolName: "gearshape",
                group: .misc
            ))
            register(MenuCommandEntry(
                tag: .showHelp,
                title: "笔记帮助",
                commandType: ShowHelpCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "questionmark.circle",
                group: .misc
            ))
            register(MenuCommandEntry(
                tag: .showLogin,
                title: "登录",
                commandType: ShowLoginCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: nil,
                group: .misc
            ))
            register(MenuCommandEntry(
                tag: .showDebugSettings,
                title: "打开调试菜单",
                commandType: ShowDebugSettingsCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "ladybug",
                group: .misc
            ))
            register(MenuCommandEntry(
                tag: .testAudioFileAPI,
                title: "测试语音文件 API",
                commandType: TestAudioFileAPICommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: "waveform",
                group: .misc
            ))
            register(MenuCommandEntry(
                tag: .showOfflineOperations,
                title: "离线操作",
                commandType: ShowOfflineOperationsCommand.self,
                keyEquivalent: "",
                modifiers: [],
                symbolName: nil,
                group: .misc
            ))
        }
    }
#endif
