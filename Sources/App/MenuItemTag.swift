import AppKit

/// 菜单项标签枚举
/// 用于标识菜单项，便于状态管理和验证 
enum MenuItemTag: Int {
    
    // MARK: - 段落样式（互斥选择，1001-1099）
    
    /// 标题
    case heading = 1001
    /// 小标题
    case subheading = 1002
    /// 副标题
    case subtitle = 1003
    /// 正文
    case bodyText = 1004
    /// 有序列表
    case orderedList = 1005
    /// 无序列表
    case unorderedList = 1006
    /// 块引用
    case blockQuote = 1007
    
    // MARK: - 视图模式（互斥选择，2001-2099）
    
    /// 列表视图
    case listView = 2001
    /// 画廊视图
    case galleryView = 2002
    
    // MARK: - 切换状态（3001-3099）
    
    /// 使用浅色背景显示笔记
    case lightBackground = 3001
    /// 隐藏文件夹
    case hideFolders = 3002
    /// 显示笔记数量
    case showNoteCount = 3003
    
    // MARK: - 编辑操作（4001-4099）
    
    /// 撤销
    case undo = 4001
    /// 重做
    case redo = 4002
    /// 剪切
    case cut = 4003
    /// 拷贝
    case copy = 4004
    /// 粘贴
    case paste = 4005
    /// 粘贴并匹配样式
    case pasteAndMatchStyle = 4006
    /// 删除
    case delete = 4007
    /// 全选
    case selectAll = 4008
    /// 附加文件
    case attachFile = 4009
    /// 添加链接
    case addLink = 4010
    
    // MARK: - 查找操作（4101-4199）
    
    /// 显示查找界面
    case showFindInterface = 4101
    /// 查找下一个
    case findNext = 4102
    /// 查找上一个
    case findPrevious = 4103
    /// 显示替换界面
    case showReplaceInterface = 4104
    /// 使用所选内容查找
    case setSearchString = 4105
    
    // MARK: - 核对清单操作（5001-5099）
    
    /// 核对清单
    case checklist = 5001
    /// 标记为已勾选
    case markAsChecked = 5002
    /// 全部勾选
    case checkAll = 5003
    /// 全部取消勾选
    case uncheckAll = 5004
    /// 将勾选的项目移到底部
    case moveCheckedToBottom = 5005
    /// 删除已勾选项目
    case deleteCheckedItems = 5006
    /// 向上移动项目
    case moveItemUp = 5007
    /// 向下移动项目
    case moveItemDown = 5008
    
    // MARK: - 字体样式（6001-6099）
    
    /// 粗体
    case bold = 6001
    /// 斜体
    case italic = 6002
    /// 下划线
    case underline = 6003
    /// 删除线
    case strikethrough = 6004
    /// 高亮
    case highlight = 6005
    
    // MARK: - 文本对齐（7001-7099）
    
    /// 左对齐
    case alignLeft = 7001
    /// 居中
    case alignCenter = 7002
    /// 右对齐
    case alignRight = 7003
    
    // MARK: - 缩进（8001-8099）
    
    /// 增大缩进
    case increaseIndent = 8001
    /// 减小缩进
    case decreaseIndent = 8002
    
    // MARK: - 缩放控制（9001-9099）
    
    /// 放大
    case zoomIn = 9001
    /// 缩小
    case zoomOut = 9002
    /// 实际大小
    case actualSize = 9003
    
    // MARK: - 区域折叠（10001-10099）
    
    /// 展开区域
    case expandSection = 10001
    /// 展开所有区域
    case expandAllSections = 10002
    /// 折叠区域
    case collapseSection = 10003
    /// 折叠所有区域
    case collapseAllSections = 10004
    
    // MARK: - 文件操作（11001-11099）
    
    /// 新建笔记
    case newNote = 11001
    /// 新建文件夹
    case newFolder = 11002
    /// 新建智能文件夹
    case newSmartFolder = 11003
    /// 共享
    case share = 11004
    /// 导入至笔记
    case importNotes = 11005
    /// 导入 Markdown
    case importMarkdown = 11006
    /// 导出为 PDF
    case exportAsPDF = 11007
    /// 导出为 Markdown
    case exportAsMarkdown = 11008
    /// 导出为纯文本
    case exportAsPlainText = 11009
    /// 置顶笔记
    case toggleStar = 11010
    /// 添加到私密笔记
    case addToPrivateNotes = 11011
    /// 复制笔记
    case duplicateNote = 11012
    /// 打印
    case printNote = 11013
    
    // MARK: - 窗口操作（12001-12099）
    
    /// 最小化
    case minimize = 12001
    /// 缩放
    case zoom = 12002
    /// 填充
    case fill = 12003
    /// 居中
    case center = 12004
    /// 在新窗口中打开笔记
    case openNoteInNewWindow = 12005
    /// 前置全部窗口
    case bringAllToFront = 12006
    
    // MARK: - 辅助方法
    
    /// 判断是否为段落样式标签
    var isParagraphStyle: Bool {
        switch self {
        case .heading, .subheading, .subtitle, .bodyText, .orderedList, .unorderedList, .blockQuote:
            return true
        default:
            return false
        }
    }
    
    /// 判断是否为视图模式标签
    var isViewMode: Bool {
        switch self {
        case .listView, .galleryView:
            return true
        default:
            return false
        }
    }
    
    /// 判断是否为切换状态标签
    var isToggleState: Bool {
        switch self {
        case .lightBackground, .hideFolders, .showNoteCount:
            return true
        default:
            return false
        }
    }
    
    /// 判断是否为需要选中笔记的操作
    var requiresSelectedNote: Bool {
        switch self {
        case .share, .exportAsPDF, .exportAsMarkdown, .exportAsPlainText,
             .toggleStar, .addToPrivateNotes, .duplicateNote, .printNote,
             .openNoteInNewWindow:
            return true
        default:
            return false
        }
    }
    
    /// 判断是否为需要编辑器焦点的操作
    var requiresEditorFocus: Bool {
        switch self {
        case .heading, .subheading, .subtitle, .bodyText, .orderedList, .unorderedList, .blockQuote,
             .checklist, .markAsChecked, .checkAll, .uncheckAll, .moveCheckedToBottom, .deleteCheckedItems,
             .moveItemUp, .moveItemDown,
             .bold, .italic, .underline, .strikethrough, .highlight,
             .alignLeft, .alignCenter, .alignRight,
             .increaseIndent, .decreaseIndent:
            return true
        default:
            return false
        }
    }
    
    /// 获取所有段落样式标签
    static var allParagraphStyles: [MenuItemTag] {
        [.heading, .subheading, .subtitle, .bodyText, .orderedList, .unorderedList, .blockQuote]
    }
    
    /// 获取所有视图模式标签
    static var allViewModes: [MenuItemTag] {
        [.listView, .galleryView]
    }
}
