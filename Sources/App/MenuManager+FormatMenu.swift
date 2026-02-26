import AppKit

/// MenuManager 格式菜单扩展
extension MenuManager {

    /// 设置格式菜单
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
        formatMenu.addItem(buildMenuItem(for: .heading))
        formatMenu.addItem(buildMenuItem(for: .subheading))
        formatMenu.addItem(buildMenuItem(for: .subtitle))
        formatMenu.addItem(buildMenuItem(for: .bodyText))
        formatMenu.addItem(buildMenuItem(for: .orderedList))
        formatMenu.addItem(buildMenuItem(for: .unorderedList))

        formatMenu.addItem(NSMenuItem.separator())

        formatMenu.addItem(buildMenuItem(for: .blockQuote))

        formatMenu.addItem(NSMenuItem.separator())
    }

    private func setupChecklistItems(in formatMenu: NSMenu) {
        formatMenu.addItem(buildMenuItem(for: .checklist))
        formatMenu.addItem(buildMenuItem(for: .markAsChecked))

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
        formatMenu.addItem(buildMenuItem(for: .lightBackground))

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
        moreMenu.addItem(buildMenuItem(for: .checkAll))
        moreMenu.addItem(buildMenuItem(for: .uncheckAll))
        moreMenu.addItem(buildMenuItem(for: .moveCheckedToBottom))
        moreMenu.addItem(buildMenuItem(for: .deleteCheckedItems))
        return moreMenu
    }

    func createMoveItemSubmenu() -> NSMenu {
        let moveMenu = NSMenu(title: "移动项目")
        moveMenu.addItem(buildMenuItem(for: .moveItemUp))
        moveMenu.addItem(buildMenuItem(for: .moveItemDown))
        return moveMenu
    }

    func createFontSubmenu() -> NSMenu {
        let fontMenu = NSMenu(title: "字体")
        fontMenu.addItem(buildMenuItem(for: .bold))
        fontMenu.addItem(buildMenuItem(for: .italic))
        fontMenu.addItem(buildMenuItem(for: .underline))
        fontMenu.addItem(buildMenuItem(for: .strikethrough))
        fontMenu.addItem(buildMenuItem(for: .highlight))
        return fontMenu
    }

    func createTextAlignmentSubmenu() -> NSMenu {
        let textMenu = NSMenu(title: "文本")
        textMenu.addItem(buildMenuItem(for: .alignLeft))
        textMenu.addItem(buildMenuItem(for: .alignCenter))
        textMenu.addItem(buildMenuItem(for: .alignRight))
        return textMenu
    }

    func createIndentSubmenu() -> NSMenu {
        let indentMenu = NSMenu(title: "缩进")
        indentMenu.addItem(buildMenuItem(for: .increaseIndent))
        indentMenu.addItem(buildMenuItem(for: .decreaseIndent))
        return indentMenu
    }
}
