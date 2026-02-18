import AppKit

/// MenuManager 格式菜单扩展
extension MenuManager {

    /// 设置格式菜单
    /// 按照 Apple Notes 标准实现完整的格式菜单
    func setupFormatMenu(in mainMenu: NSMenu) {
        let formatMenuItem = NSMenuItem()
        formatMenuItem.title = "格式"
        let formatMenu = NSMenu(title: "格式")
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        setupParagraphStyleItems(in: formatMenu)
        setupChecklistItems(in: formatMenu)
        setupAppearanceItems(in: formatMenu)
        setupFontAndTextItems(in: formatMenu)
    }

    // MARK: - 格式菜单私有方法

    private func setupParagraphStyleItems(in formatMenu: NSMenu) {
        let headingItem = NSMenuItem(
            title: "大标题",
            action: #selector(AppDelegate.setHeading(_:)),
            keyEquivalent: ""
        )
        headingItem.tag = MenuItemTag.heading.rawValue
        setMenuItemIcon(headingItem, symbolName: "textformat.size.larger")
        formatMenu.addItem(headingItem)

        let subheadingItem = NSMenuItem(
            title: "二级标题",
            action: #selector(AppDelegate.setSubheading(_:)),
            keyEquivalent: ""
        )
        subheadingItem.tag = MenuItemTag.subheading.rawValue
        setMenuItemIcon(subheadingItem, symbolName: "textformat.size")
        formatMenu.addItem(subheadingItem)

        let subtitleItem = NSMenuItem(
            title: "三级标题",
            action: #selector(AppDelegate.setSubtitle(_:)),
            keyEquivalent: ""
        )
        subtitleItem.tag = MenuItemTag.subtitle.rawValue
        setMenuItemIcon(subtitleItem, symbolName: "textformat.size.smaller")
        formatMenu.addItem(subtitleItem)

        let bodyTextItem = NSMenuItem(
            title: "正文",
            action: #selector(AppDelegate.setBodyText(_:)),
            keyEquivalent: ""
        )
        bodyTextItem.tag = MenuItemTag.bodyText.rawValue
        setMenuItemIcon(bodyTextItem, symbolName: "text.justify")
        formatMenu.addItem(bodyTextItem)

        let orderedListItem = NSMenuItem(
            title: "有序列表",
            action: #selector(AppDelegate.toggleOrderedList(_:)),
            keyEquivalent: ""
        )
        orderedListItem.tag = MenuItemTag.orderedList.rawValue
        setMenuItemIcon(orderedListItem, symbolName: "list.number")
        formatMenu.addItem(orderedListItem)

        let unorderedListItem = NSMenuItem(
            title: "无序列表",
            action: #selector(AppDelegate.toggleUnorderedList(_:)),
            keyEquivalent: ""
        )
        unorderedListItem.tag = MenuItemTag.unorderedList.rawValue
        setMenuItemIcon(unorderedListItem, symbolName: "list.bullet")
        formatMenu.addItem(unorderedListItem)

        formatMenu.addItem(NSMenuItem.separator())

        let blockQuoteItem = NSMenuItem(
            title: "块引用",
            action: #selector(AppDelegate.toggleBlockQuote(_:)),
            keyEquivalent: ""
        )
        blockQuoteItem.tag = MenuItemTag.blockQuote.rawValue
        setMenuItemIcon(blockQuoteItem, symbolName: "text.quote")
        formatMenu.addItem(blockQuoteItem)

        formatMenu.addItem(NSMenuItem.separator())
    }

    private func setupChecklistItems(in formatMenu: NSMenu) {
        let checklistItem = NSMenuItem(
            title: "核对清单",
            action: #selector(AppDelegate.toggleChecklist(_:)),
            keyEquivalent: ""
        )
        checklistItem.tag = MenuItemTag.checklist.rawValue
        setMenuItemIcon(checklistItem, symbolName: "checklist")
        formatMenu.addItem(checklistItem)

        let markAsCheckedItem = NSMenuItem(
            title: "标记为已勾选",
            action: #selector(AppDelegate.markAsChecked(_:)),
            keyEquivalent: ""
        )
        markAsCheckedItem.tag = MenuItemTag.markAsChecked.rawValue
        setMenuItemIcon(markAsCheckedItem, symbolName: "checkmark.circle")
        formatMenu.addItem(markAsCheckedItem)

        let moreMenuItem = NSMenuItem(
            title: "更多",
            action: nil,
            keyEquivalent: ""
        )
        moreMenuItem.submenu = createChecklistMoreSubmenu()
        setMenuItemIcon(moreMenuItem, symbolName: "ellipsis.circle")
        formatMenu.addItem(moreMenuItem)

        formatMenu.addItem(NSMenuItem.separator())

        let moveItemMenuItem = NSMenuItem(
            title: "移动项目",
            action: nil,
            keyEquivalent: ""
        )
        moveItemMenuItem.submenu = createMoveItemSubmenu()
        setMenuItemIcon(moveItemMenuItem, symbolName: "arrow.up.arrow.down")
        formatMenu.addItem(moveItemMenuItem)

        formatMenu.addItem(NSMenuItem.separator())
    }

    private func setupAppearanceItems(in formatMenu: NSMenu) {
        let lightBackgroundItem = NSMenuItem(
            title: "使用浅色背景显示笔记",
            action: #selector(AppDelegate.toggleLightBackground(_:)),
            keyEquivalent: ""
        )
        lightBackgroundItem.tag = MenuItemTag.lightBackground.rawValue
        setMenuItemIcon(lightBackgroundItem, symbolName: "sun.max")
        formatMenu.addItem(lightBackgroundItem)

        formatMenu.addItem(NSMenuItem.separator())
    }

    private func setupFontAndTextItems(in formatMenu: NSMenu) {
        let fontMenuItem = NSMenuItem(
            title: "字体",
            action: nil,
            keyEquivalent: ""
        )
        fontMenuItem.submenu = createFontSubmenu()
        setMenuItemIcon(fontMenuItem, symbolName: "textformat")
        formatMenu.addItem(fontMenuItem)

        let textMenuItem = NSMenuItem(
            title: "文本",
            action: nil,
            keyEquivalent: ""
        )
        textMenuItem.submenu = createTextAlignmentSubmenu()
        setMenuItemIcon(textMenuItem, symbolName: "text.alignleft")
        formatMenu.addItem(textMenuItem)

        let indentMenuItem = NSMenuItem(
            title: "缩进",
            action: nil,
            keyEquivalent: ""
        )
        indentMenuItem.submenu = createIndentSubmenu()
        setMenuItemIcon(indentMenuItem, symbolName: "increase.indent")
        formatMenu.addItem(indentMenuItem)
    }

    // MARK: - 子菜单创建

    func createChecklistMoreSubmenu() -> NSMenu {
        let moreMenu = NSMenu(title: "更多")

        let checkAllItem = NSMenuItem(
            title: "全部勾选",
            action: #selector(AppDelegate.checkAll(_:)),
            keyEquivalent: ""
        )
        checkAllItem.tag = MenuItemTag.checkAll.rawValue
        setMenuItemIcon(checkAllItem, symbolName: "checkmark.circle.fill")
        moreMenu.addItem(checkAllItem)

        let uncheckAllItem = NSMenuItem(
            title: "全部取消勾选",
            action: #selector(AppDelegate.uncheckAll(_:)),
            keyEquivalent: ""
        )
        uncheckAllItem.tag = MenuItemTag.uncheckAll.rawValue
        setMenuItemIcon(uncheckAllItem, symbolName: "circle")
        moreMenu.addItem(uncheckAllItem)

        let moveCheckedToBottomItem = NSMenuItem(
            title: "将勾选的项目移到底部",
            action: #selector(AppDelegate.moveCheckedToBottom(_:)),
            keyEquivalent: ""
        )
        moveCheckedToBottomItem.tag = MenuItemTag.moveCheckedToBottom.rawValue
        setMenuItemIcon(moveCheckedToBottomItem, symbolName: "arrow.down.to.line")
        moreMenu.addItem(moveCheckedToBottomItem)

        let deleteCheckedItemsItem = NSMenuItem(
            title: "删除已勾选项目",
            action: #selector(AppDelegate.deleteCheckedItems(_:)),
            keyEquivalent: ""
        )
        deleteCheckedItemsItem.tag = MenuItemTag.deleteCheckedItems.rawValue
        setMenuItemIcon(deleteCheckedItemsItem, symbolName: "trash")
        moreMenu.addItem(deleteCheckedItemsItem)

        return moreMenu
    }

    func createMoveItemSubmenu() -> NSMenu {
        let moveMenu = NSMenu(title: "移动项目")

        let moveUpItem = NSMenuItem(
            title: "向上",
            action: #selector(AppDelegate.moveItemUp(_:)),
            keyEquivalent: ""
        )
        moveUpItem.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        moveUpItem.keyEquivalentModifierMask = [.control, .command]
        moveUpItem.tag = MenuItemTag.moveItemUp.rawValue
        setMenuItemIcon(moveUpItem, symbolName: "arrow.up")
        moveMenu.addItem(moveUpItem)

        let moveDownItem = NSMenuItem(
            title: "向下",
            action: #selector(AppDelegate.moveItemDown(_:)),
            keyEquivalent: ""
        )
        moveDownItem.keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        moveDownItem.keyEquivalentModifierMask = [.control, .command]
        moveDownItem.tag = MenuItemTag.moveItemDown.rawValue
        setMenuItemIcon(moveDownItem, symbolName: "arrow.down")
        moveMenu.addItem(moveDownItem)

        return moveMenu
    }

    func createFontSubmenu() -> NSMenu {
        let fontMenu = NSMenu(title: "字体")

        let boldItem = NSMenuItem(
            title: "粗体",
            action: #selector(AppDelegate.toggleBold(_:)),
            keyEquivalent: "b"
        )
        boldItem.keyEquivalentModifierMask = [.command]
        boldItem.tag = MenuItemTag.bold.rawValue
        setMenuItemIcon(boldItem, symbolName: "bold")
        fontMenu.addItem(boldItem)

        let italicItem = NSMenuItem(
            title: "斜体",
            action: #selector(AppDelegate.toggleItalic(_:)),
            keyEquivalent: "i"
        )
        italicItem.keyEquivalentModifierMask = [.command]
        italicItem.tag = MenuItemTag.italic.rawValue
        setMenuItemIcon(italicItem, symbolName: "italic")
        fontMenu.addItem(italicItem)

        let underlineItem = NSMenuItem(
            title: "下划线",
            action: #selector(AppDelegate.toggleUnderline(_:)),
            keyEquivalent: "u"
        )
        underlineItem.keyEquivalentModifierMask = [.command]
        underlineItem.tag = MenuItemTag.underline.rawValue
        setMenuItemIcon(underlineItem, symbolName: "underline")
        fontMenu.addItem(underlineItem)

        let strikethroughItem = NSMenuItem(
            title: "删除线",
            action: #selector(AppDelegate.toggleStrikethrough(_:)),
            keyEquivalent: ""
        )
        strikethroughItem.tag = MenuItemTag.strikethrough.rawValue
        setMenuItemIcon(strikethroughItem, symbolName: "strikethrough")
        fontMenu.addItem(strikethroughItem)

        let highlightItem = NSMenuItem(
            title: "高亮",
            action: #selector(AppDelegate.toggleHighlight(_:)),
            keyEquivalent: ""
        )
        highlightItem.tag = MenuItemTag.highlight.rawValue
        setMenuItemIcon(highlightItem, symbolName: "highlighter")
        fontMenu.addItem(highlightItem)

        return fontMenu
    }

    func createTextAlignmentSubmenu() -> NSMenu {
        let textMenu = NSMenu(title: "文本")

        let alignLeftItem = NSMenuItem(
            title: "左对齐",
            action: #selector(AppDelegate.alignLeft(_:)),
            keyEquivalent: ""
        )
        alignLeftItem.tag = MenuItemTag.alignLeft.rawValue
        setMenuItemIcon(alignLeftItem, symbolName: "text.alignleft")
        textMenu.addItem(alignLeftItem)

        let alignCenterItem = NSMenuItem(
            title: "居中",
            action: #selector(AppDelegate.alignCenter(_:)),
            keyEquivalent: ""
        )
        alignCenterItem.tag = MenuItemTag.alignCenter.rawValue
        setMenuItemIcon(alignCenterItem, symbolName: "text.aligncenter")
        textMenu.addItem(alignCenterItem)

        let alignRightItem = NSMenuItem(
            title: "右对齐",
            action: #selector(AppDelegate.alignRight(_:)),
            keyEquivalent: ""
        )
        alignRightItem.tag = MenuItemTag.alignRight.rawValue
        setMenuItemIcon(alignRightItem, symbolName: "text.alignright")
        textMenu.addItem(alignRightItem)

        return textMenu
    }

    func createIndentSubmenu() -> NSMenu {
        let indentMenu = NSMenu(title: "缩进")

        let increaseIndentItem = NSMenuItem(
            title: "增大",
            action: #selector(AppDelegate.increaseIndent(_:)),
            keyEquivalent: "]"
        )
        increaseIndentItem.keyEquivalentModifierMask = [.command]
        increaseIndentItem.tag = MenuItemTag.increaseIndent.rawValue
        setMenuItemIcon(increaseIndentItem, symbolName: "increase.indent")
        indentMenu.addItem(increaseIndentItem)

        let decreaseIndentItem = NSMenuItem(
            title: "减小",
            action: #selector(AppDelegate.decreaseIndent(_:)),
            keyEquivalent: "["
        )
        decreaseIndentItem.keyEquivalentModifierMask = [.command]
        decreaseIndentItem.tag = MenuItemTag.decreaseIndent.rawValue
        setMenuItemIcon(decreaseIndentItem, symbolName: "decrease.indent")
        indentMenu.addItem(decreaseIndentItem)

        return indentMenu
    }
}
