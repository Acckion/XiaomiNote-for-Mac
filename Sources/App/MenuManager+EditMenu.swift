import AppKit

/// MenuManager 编辑菜单扩展
extension MenuManager {

    /// 设置编辑菜单
    /// 按照 Apple Notes 标准实现完整的编辑菜单
    /// 使用标准 NSResponder 选择器，让系统自动路由到响应链中的正确响应者
    func setupEditMenu(in mainMenu: NSMenu) {
        let editMenuItem = NSMenuItem()
        editMenuItem.title = "编辑"
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        setupUndoRedoItems(in: editMenu)
        setupBasicEditItems(in: editMenu)
        setupAttachmentItems(in: editMenu)
        setupFindItems(in: editMenu)
        setupTextProcessingItems(in: editMenu)
        setupDictationAndEmojiItems(in: editMenu)
    }

    // MARK: - 编辑菜单私有方法

    private func setupUndoRedoItems(in editMenu: NSMenu) {
        let undoItem = NSMenuItem(
            title: "撤销",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        undoItem.tag = MenuItemTag.undo.rawValue
        setMenuItemIcon(undoItem, symbolName: "arrow.uturn.backward")
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.tag = MenuItemTag.redo.rawValue
        setMenuItemIcon(redoItem, symbolName: "arrow.uturn.forward")
        editMenu.addItem(redoItem)

        editMenu.addItem(NSMenuItem.separator())
    }

    private func setupBasicEditItems(in editMenu: NSMenu) {
        let cutItem = NSMenuItem(
            title: "剪切",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        cutItem.keyEquivalentModifierMask = [.command]
        cutItem.tag = MenuItemTag.cut.rawValue
        setMenuItemIcon(cutItem, symbolName: "scissors")
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(
            title: "拷贝",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.tag = MenuItemTag.copy.rawValue
        setMenuItemIcon(copyItem, symbolName: "doc.on.doc")
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(
            title: "粘贴",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = [.command]
        pasteItem.tag = MenuItemTag.paste.rawValue
        setMenuItemIcon(pasteItem, symbolName: "doc.on.clipboard")
        editMenu.addItem(pasteItem)

        let pasteAndMatchStyleItem = NSMenuItem(
            title: "粘贴并匹配样式",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v"
        )
        pasteAndMatchStyleItem.keyEquivalentModifierMask = [.command, .option, .shift]
        pasteAndMatchStyleItem.tag = MenuItemTag.pasteAndMatchStyle.rawValue
        setMenuItemIcon(pasteAndMatchStyleItem, symbolName: "doc.on.clipboard.fill")
        editMenu.addItem(pasteAndMatchStyleItem)

        let deleteItem = NSMenuItem(
            title: "删除",
            action: #selector(NSText.delete(_:)),
            keyEquivalent: ""
        )
        deleteItem.tag = MenuItemTag.delete.rawValue
        setMenuItemIcon(deleteItem, symbolName: "trash")
        editMenu.addItem(deleteItem)

        let selectAllItem = NSMenuItem(
            title: "全选",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.keyEquivalentModifierMask = [.command]
        selectAllItem.tag = MenuItemTag.selectAll.rawValue
        setMenuItemIcon(selectAllItem, symbolName: "selection.pin.in.out")
        editMenu.addItem(selectAllItem)

        editMenu.addItem(NSMenuItem.separator())
    }

    private func setupAttachmentItems(in editMenu: NSMenu) {
        let attachFileItem = NSMenuItem(
            title: "附加文件...",
            action: #selector(MenuActionHandler.attachFile(_:)),
            keyEquivalent: ""
        )
        attachFileItem.tag = MenuItemTag.attachFile.rawValue
        setMenuItemIcon(attachFileItem, symbolName: "paperclip")
        editMenu.addItem(attachFileItem)

        let addLinkItem = NSMenuItem(
            title: "添加链接...",
            action: #selector(MenuActionHandler.addLink(_:)),
            keyEquivalent: "k"
        )
        addLinkItem.keyEquivalentModifierMask = [.command]
        addLinkItem.tag = MenuItemTag.addLink.rawValue
        setMenuItemIcon(addLinkItem, symbolName: "link")
        editMenu.addItem(addLinkItem)

        editMenu.addItem(NSMenuItem.separator())
    }

    private func setupFindItems(in editMenu: NSMenu) {
        let findMenuItem = NSMenuItem(
            title: "查找",
            action: nil,
            keyEquivalent: ""
        )
        findMenuItem.submenu = createFindSubmenu()
        setMenuItemIcon(findMenuItem, symbolName: "magnifyingglass")
        editMenu.addItem(findMenuItem)
    }

    private func setupTextProcessingItems(in editMenu: NSMenu) {
        let spellingMenuItem = NSMenuItem(
            title: "拼写和语法",
            action: nil,
            keyEquivalent: ""
        )
        spellingMenuItem.submenu = createSpellingSubmenu()
        setMenuItemIcon(spellingMenuItem, symbolName: "textformat.abc")
        editMenu.addItem(spellingMenuItem)

        let substitutionsMenuItem = NSMenuItem(
            title: "替换",
            action: nil,
            keyEquivalent: ""
        )
        substitutionsMenuItem.submenu = createSubstitutionsSubmenu()
        setMenuItemIcon(substitutionsMenuItem, symbolName: "arrow.2.squarepath")
        editMenu.addItem(substitutionsMenuItem)

        let transformationsMenuItem = NSMenuItem(
            title: "转换",
            action: nil,
            keyEquivalent: ""
        )
        transformationsMenuItem.submenu = createTransformationsSubmenu()
        setMenuItemIcon(transformationsMenuItem, symbolName: "textformat")
        editMenu.addItem(transformationsMenuItem)

        let speechMenuItem = NSMenuItem(
            title: "语音",
            action: nil,
            keyEquivalent: ""
        )
        speechMenuItem.submenu = createSpeechSubmenu()
        setMenuItemIcon(speechMenuItem, symbolName: "speaker.wave.2")
        editMenu.addItem(speechMenuItem)

        editMenu.addItem(NSMenuItem.separator())
    }

    private func setupDictationAndEmojiItems(in editMenu: NSMenu) {
        let startDictationItem = NSMenuItem(
            title: "开始听写",
            action: nil,
            keyEquivalent: ""
        )
        startDictationItem.isEnabled = false
        editMenu.addItem(startDictationItem)

        let emojiItem = NSMenuItem(
            title: "表情与符号",
            action: #selector(NSApplication.orderFrontCharacterPalette(_:)),
            keyEquivalent: " "
        )
        emojiItem.keyEquivalentModifierMask = [.control, .command]
        setMenuItemIcon(emojiItem, symbolName: "face.smiling")
        editMenu.addItem(emojiItem)
    }

    // MARK: - 子菜单创建

    func createFindSubmenu() -> NSMenu {
        let findMenu = NSMenu(title: "查找")

        let findItem = NSMenuItem(
            title: "查找...",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "f"
        )
        findItem.keyEquivalentModifierMask = [.command]
        findItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        setMenuItemIcon(findItem, symbolName: "magnifyingglass")
        findMenu.addItem(findItem)

        let findNextItem = NSMenuItem(
            title: "查找下一个",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "g"
        )
        findNextItem.keyEquivalentModifierMask = [.command]
        findNextItem.tag = Int(NSTextFinder.Action.nextMatch.rawValue)
        setMenuItemIcon(findNextItem, symbolName: "chevron.down")
        findMenu.addItem(findNextItem)

        let findPreviousItem = NSMenuItem(
            title: "查找上一个",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "g"
        )
        findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
        findPreviousItem.tag = Int(NSTextFinder.Action.previousMatch.rawValue)
        setMenuItemIcon(findPreviousItem, symbolName: "chevron.up")
        findMenu.addItem(findPreviousItem)

        let useSelectionItem = NSMenuItem(
            title: "使用所选内容查找",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "e"
        )
        useSelectionItem.keyEquivalentModifierMask = [.command]
        useSelectionItem.tag = Int(NSTextFinder.Action.setSearchString.rawValue)
        setMenuItemIcon(useSelectionItem, symbolName: "text.magnifyingglass")
        findMenu.addItem(useSelectionItem)

        let findAndReplaceItem = NSMenuItem(
            title: "查找并替换...",
            action: #selector(NSTextView.performFindPanelAction(_:)),
            keyEquivalent: "f"
        )
        findAndReplaceItem.keyEquivalentModifierMask = [.command, .option]
        findAndReplaceItem.tag = Int(NSTextFinder.Action.showReplaceInterface.rawValue)
        setMenuItemIcon(findAndReplaceItem, symbolName: "arrow.left.arrow.right")
        findMenu.addItem(findAndReplaceItem)

        return findMenu
    }

    func createSpellingSubmenu() -> NSMenu {
        let spellingMenu = NSMenu(title: "拼写和语法")

        let checkNowItem = NSMenuItem(
            title: "立即检查文稿",
            action: #selector(NSTextView.checkSpelling(_:)),
            keyEquivalent: ";"
        )
        checkNowItem.keyEquivalentModifierMask = [.command]
        setMenuItemIcon(checkNowItem, symbolName: "checkmark.circle")
        spellingMenu.addItem(checkNowItem)

        let checkSpellingItem = NSMenuItem(
            title: "检查拼写和语法",
            action: #selector(NSText.checkSpelling(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(checkSpellingItem, symbolName: "text.badge.checkmark")
        spellingMenu.addItem(checkSpellingItem)

        let autoCorrectItem = NSMenuItem(
            title: "自动更正拼写",
            action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(autoCorrectItem, symbolName: "wand.and.stars")
        spellingMenu.addItem(autoCorrectItem)

        return spellingMenu
    }

    func createSubstitutionsSubmenu() -> NSMenu {
        let substitutionsMenu = NSMenu(title: "替换")

        let showSubstitutionsItem = NSMenuItem(
            title: "显示替换",
            action: #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(showSubstitutionsItem, symbolName: "list.bullet.rectangle")
        substitutionsMenu.addItem(showSubstitutionsItem)

        substitutionsMenu.addItem(NSMenuItem.separator())

        let smartCopyPasteItem = NSMenuItem(
            title: "智能拷贝/粘贴",
            action: #selector(NSTextView.toggleSmartInsertDelete(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartCopyPasteItem, symbolName: "doc.on.doc.fill")
        substitutionsMenu.addItem(smartCopyPasteItem)

        let smartQuotesItem = NSMenuItem(
            title: "智能引号",
            action: #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartQuotesItem, symbolName: "quote.opening")
        substitutionsMenu.addItem(smartQuotesItem)

        let smartDashesItem = NSMenuItem(
            title: "智能破折号",
            action: #selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartDashesItem, symbolName: "minus")
        substitutionsMenu.addItem(smartDashesItem)

        let smartLinksItem = NSMenuItem(
            title: "智能链接",
            action: #selector(NSTextView.toggleAutomaticLinkDetection(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(smartLinksItem, symbolName: "link")
        substitutionsMenu.addItem(smartLinksItem)

        let textReplacementItem = NSMenuItem(
            title: "文本替换",
            action: #selector(NSTextView.toggleAutomaticTextReplacement(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(textReplacementItem, symbolName: "character.cursor.ibeam")
        substitutionsMenu.addItem(textReplacementItem)

        return substitutionsMenu
    }

    func createTransformationsSubmenu() -> NSMenu {
        let transformationsMenu = NSMenu(title: "转换")

        let uppercaseItem = NSMenuItem(
            title: "全部大写",
            action: #selector(NSTextView.uppercaseWord(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(uppercaseItem, symbolName: "textformat.size.larger")
        transformationsMenu.addItem(uppercaseItem)

        let lowercaseItem = NSMenuItem(
            title: "全部小写",
            action: #selector(NSTextView.lowercaseWord(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(lowercaseItem, symbolName: "textformat.size.smaller")
        transformationsMenu.addItem(lowercaseItem)

        let capitalizeItem = NSMenuItem(
            title: "首字母大写",
            action: #selector(NSTextView.capitalizeWord(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(capitalizeItem, symbolName: "textformat")
        transformationsMenu.addItem(capitalizeItem)

        return transformationsMenu
    }

    func createSpeechSubmenu() -> NSMenu {
        let speechMenu = NSMenu(title: "语音")

        let startSpeakingItem = NSMenuItem(
            title: "开始朗读",
            action: #selector(NSTextView.startSpeaking(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(startSpeakingItem, symbolName: "play.fill")
        speechMenu.addItem(startSpeakingItem)

        let stopSpeakingItem = NSMenuItem(
            title: "停止朗读",
            action: #selector(NSTextView.stopSpeaking(_:)),
            keyEquivalent: ""
        )
        setMenuItemIcon(stopSpeakingItem, symbolName: "stop.fill")
        speechMenu.addItem(stopSpeakingItem)

        return speechMenu
    }
}
