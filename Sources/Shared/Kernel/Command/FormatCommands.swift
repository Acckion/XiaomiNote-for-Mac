//
//  FormatCommands.swift
//  MiNoteLibrary
//

#if os(macOS)
    import AppKit

    // MARK: - 基础格式命令

    /// 切换粗体
    public struct ToggleBoldCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.bold)
            } else {
                context.coordinator.mainWindowController?.toggleBold(nil)
            }
        }
    }

    /// 切换斜体
    public struct ToggleItalicCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.italic)
            } else {
                context.coordinator.mainWindowController?.toggleItalic(nil)
            }
        }
    }

    /// 切换下划线
    public struct ToggleUnderlineCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.underline)
            } else {
                context.coordinator.mainWindowController?.toggleUnderline(nil)
            }
        }
    }

    /// 切换删除线
    public struct ToggleStrikethroughCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.strikethrough)
            } else {
                context.coordinator.mainWindowController?.toggleStrikethrough(nil)
            }
        }
    }

    // MARK: - 字号命令

    /// 增大字体
    public struct IncreaseFontSizeCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.increaseFontSize()
            }
        }
    }

    /// 减小字体
    public struct DecreaseFontSizeCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.decreaseFontSize()
            }
        }
    }

    // MARK: - 段落样式命令

    /// 设置标题（heading1）
    public struct SetHeadingCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.applyFormat(.heading1)
            } else {
                context.coordinator.mainWindowController?.setHeading1(nil)
            }
        }
    }

    /// 设置小标题（heading2）
    public struct SetSubheadingCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.applyFormat(.heading2)
            } else {
                context.coordinator.mainWindowController?.setHeading2(nil)
            }
        }
    }

    /// 设置副标题（heading3）
    public struct SetSubtitleCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.applyFormat(.heading3)
            } else {
                context.coordinator.mainWindowController?.setHeading3(nil)
            }
        }
    }

    /// 设置正文
    public struct SetBodyTextCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.clearParagraphFormat()
            } else {
                context.coordinator.mainWindowController?.setBodyText(nil)
            }
        }
    }

    // MARK: - 列表命令

    /// 切换有序列表
    public struct ToggleOrderedListCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.numberedList)
            } else {
                context.coordinator.mainWindowController?.toggleNumberedList(nil)
            }
        }
    }

    /// 切换无序列表
    public struct ToggleUnorderedListCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.bulletList)
            } else {
                context.coordinator.mainWindowController?.toggleBulletList(nil)
            }
        }
    }

    /// 切换复选框列表
    public struct ToggleCheckboxListCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.checkbox)
            } else {
                context.coordinator.mainWindowController?.toggleCheckboxList(nil)
            }
        }
    }

    /// 切换块引用
    public struct ToggleBlockQuoteCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.quote)
            } else {
                context.coordinator.mainWindowController?.toggleBlockQuote(nil)
            }
        }
    }

    // MARK: - 缩进命令

    /// 增加缩进
    public struct IncreaseIndentCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.increaseIndent()
            }
        }
    }

    /// 减少缩进
    public struct DecreaseIndentCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.decreaseIndent()
            }
        }
    }

    // MARK: - 对齐命令

    /// 居左对齐
    public struct AlignLeftCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.clearAlignmentFormat()
            } else {
                context.coordinator.mainWindowController?.alignLeft(nil)
            }
        }
    }

    /// 居中对齐
    public struct AlignCenterCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.applyFormat(.alignCenter)
            } else {
                context.coordinator.mainWindowController?.alignCenter(nil)
            }
        }
    }

    /// 居右对齐
    public struct AlignRightCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.applyFormat(.alignRight)
            } else {
                context.coordinator.mainWindowController?.alignRight(nil)
            }
        }
    }

    // MARK: - 外观命令

    /// 切换浅色背景
    public struct ToggleLightBackgroundCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.toggleLightBackground(nil)
        }
    }

    /// 切换高亮
    public struct ToggleHighlightCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            if let fsm = context.coordinator.formatStateManager, fsm.hasActiveEditor {
                fsm.toggleFormat(.highlight)
            } else {
                context.coordinator.mainWindowController?.toggleHighlight(nil)
            }
        }
    }

    // MARK: - 核对清单命令

    /// 标记为已勾选
    public struct MarkAsCheckedCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.markAsChecked(nil)
        }
    }

    /// 全部勾选
    public struct CheckAllCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.checkAll(nil)
        }
    }

    /// 全部取消勾选
    public struct UncheckAllCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.uncheckAll(nil)
        }
    }

    /// 将勾选项移到底部
    public struct MoveCheckedToBottomCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.moveCheckedToBottom(nil)
        }
    }

    /// 删除已勾选项目
    public struct DeleteCheckedItemsCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.deleteCheckedItems(nil)
        }
    }

    /// 向上移动项目
    public struct MoveItemUpCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.moveItemUp(nil)
        }
    }

    /// 向下移动项目
    public struct MoveItemDownCommand: AppCommand {
        public init() {}

        public func execute(with context: CommandContext) {
            context.coordinator.mainWindowController?.moveItemDown(nil)
        }
    }

#endif
