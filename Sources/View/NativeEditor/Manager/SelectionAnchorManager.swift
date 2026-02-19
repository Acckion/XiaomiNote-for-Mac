import AppKit
import Foundation

/// 选择锚点管理器
/// 负责管理文本选择的锚点，支持自然的选择扩展和收缩
///
/// **核心功能**:
/// - 记录选择开始时的锚点位置
/// - 在选择扩展/收缩时保持锚点不变
/// - 处理选择方向变化
/// - 支持键盘和鼠标混合扩展选择
///
/// _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6_
public class SelectionAnchorManager {
    // MARK: - Properties

    /// 当前锚点位置
    /// 锚点是选择的固定端，在扩展选择时保持不变
    public private(set) var anchorLocation: Int?

    /// 当前活动端位置
    /// 活动端是选择的可移动端，随着用户操作而变化
    private var activeLocation: Int?

    /// 选择方向
    /// true 表示向前选择（从锚点向后），false 表示向后选择（从锚点向前）
    private var isForwardSelection = true

    /// 是否正在进行选择操作
    private var isSelecting = false

    /// 关联的 NSTextView（弱引用）
    private weak var textView: NSTextView?

    // MARK: - Initialization

    /// 初始化选择锚点管理器
    /// - Parameter textView: 关联的 NSTextView
    public init(textView: NSTextView? = nil) {
        self.textView = textView
    }

    // MARK: - Public Methods - 锚点管理

    /// 设置锚点
    ///
    /// 在选择开始时调用此方法设置锚点位置。
    /// 锚点是选择的固定端，在后续的扩展/收缩操作中保持不变。
    /// - Parameter location: 锚点位置
    public func setAnchor(at location: Int) {
        anchorLocation = location
        activeLocation = location
        isSelecting = true
        isForwardSelection = true
    }

    /// 清除锚点
    public func clearAnchor() {
        anchorLocation = nil
        activeLocation = nil
        isSelecting = false
    }

    /// 开始选择操作
    public func beginSelection(at location: Int) {
        if anchorLocation == nil {
            setAnchor(at: location)
        }
        isSelecting = true
    }

    /// 结束选择操作
    public func endSelection() {
        isSelecting = false
    }

    // MARK: - Public Methods - 选择扩展

    /// 扩展选择到新位置
    ///
    /// 根据新位置和锚点计算新的选择范围。
    /// 锚点保持不变，活动端移动到新位置。
    ///
    /// - Parameters:
    ///   - newLocation: 新的位置
    ///   - currentSelection: 当前选择范围
    /// - Returns: 新的选择范围
    public func extendSelection(
        to newLocation: Int,
        from currentSelection: NSRange
    ) -> NSRange {
        // 如果没有锚点，设置当前选择的起始位置为锚点
        guard let anchor = anchorLocation else {
            setAnchor(at: currentSelection.location)
            return extendSelection(to: newLocation, from: currentSelection)
        }

        // 计算新的选择方向
        let newIsForward = newLocation >= anchor

        // 检测方向变化
        if newIsForward != isForwardSelection {
            handleDirectionChange(to: newLocation, from: currentSelection)
        }

        // 更新状态
        isForwardSelection = newIsForward
        activeLocation = newLocation

        // 计算新的选择范围
        let newRange = if newIsForward {
            // 向前选择：从锚点到新位置
            NSRange(location: anchor, length: newLocation - anchor)
        } else {
            // 向后选择：从新位置到锚点
            NSRange(location: newLocation, length: anchor - newLocation)
        }

        return newRange
    }

    /// 处理选择方向变化
    ///
    /// 当用户改变选择方向时（例如从向前选择变为向后选择），
    /// 需要切换锚点和活动端。
    ///
    /// - Parameters:
    ///   - newLocation: 新的位置
    ///   - currentSelection: 当前选择范围
    public func handleDirectionChange(
        to _: Int,
        from _: NSRange
    ) {
        // 在方向变化时，锚点保持不变
    }

    /// 处理拖动选择边缘
    ///
    /// 当用户拖动选择边缘时，被拖动的边缘成为活动端，
    /// 另一边成为锚点。
    ///
    /// - Parameters:
    ///   - edge: 被拖动的边缘（.start 或 .end）
    ///   - currentSelection: 当前选择范围
    public func handleDragEdge(
        _ edge: SelectionEdge,
        from currentSelection: NSRange
    ) {
        let start = currentSelection.location
        let end = NSMaxRange(currentSelection)

        switch edge {
        case .start:
            // 拖动起始边缘：结束位置成为锚点
            anchorLocation = end
            activeLocation = start
            isForwardSelection = false

        case .end:
            // 拖动结束边缘：起始位置成为锚点
            anchorLocation = start
            activeLocation = end
            isForwardSelection = true
        }

    }

    // MARK: - Public Methods - 键盘选择

    /// 处理键盘选择扩展
    ///
    /// - Parameters:
    ///   - direction: 移动方向
    ///   - currentSelection: 当前选择范围
    ///   - textLength: 文本总长度
    /// - Returns: 新的选择范围
    public func handleKeyboardSelection(
        direction: SelectionDirection,
        from currentSelection: NSRange,
        textLength: Int
    ) -> NSRange {
        // 如果没有锚点，设置当前选择的起始位置为锚点
        if anchorLocation == nil {
            setAnchor(at: currentSelection.location)
        }

        guard let anchor = anchorLocation else {
            return currentSelection
        }

        // 计算新的活动端位置
        let currentActive = activeLocation ?? currentSelection.location
        var newActive = currentActive

        switch direction {
        case .left:
            newActive = max(0, currentActive - 1)
        case .right:
            newActive = min(textLength, currentActive + 1)
        case .up, .down:
            // 上下移动需要考虑行布局，这里简化处理
            // 实际应该使用 NSTextView 的 layoutManager 计算
            break
        }

        // 使用 extendSelection 计算新范围
        return extendSelection(to: newActive, from: currentSelection)
    }

    // MARK: - Public Methods - 鼠标选择

    /// 处理鼠标选择
    ///
    /// 支持鼠标拖动选择和 Shift + 点击扩展选择。
    ///
    /// - Parameters:
    ///   - location: 鼠标点击位置
    ///   - isShiftPressed: 是否按下 Shift 键
    ///   - currentSelection: 当前选择范围
    /// - Returns: 新的选择范围
    public func handleMouseSelection(
        at location: Int,
        isShiftPressed: Bool,
        from currentSelection: NSRange
    ) -> NSRange {
        if isShiftPressed {
            // Shift + 点击：扩展选择
            if anchorLocation == nil {
                setAnchor(at: currentSelection.location)
            }
            return extendSelection(to: location, from: currentSelection)
        } else {
            // 普通点击：清除锚点，设置新的光标位置
            clearAnchor()
            return NSRange(location: location, length: 0)
        }
    }

    // MARK: - Public Methods - 状态查询

    /// 获取当前选择状态
    ///
    /// - Returns: 包含锚点、活动端和方向的状态信息
    public func getSelectionState() -> SelectionState {
        SelectionState(
            anchor: anchorLocation,
            active: activeLocation,
            isForward: isForwardSelection,
            isSelecting: isSelecting
        )
    }

    /// 判断是否有活动的选择
    ///
    /// - Returns: 如果有活动的选择返回 true，否则返回 false
    public func hasActiveSelection() -> Bool {
        anchorLocation != nil && isSelecting
    }
}

// MARK: - Supporting Types

/// 选择边缘
public enum SelectionEdge {
    case start // 起始边缘
    case end // 结束边缘
}

/// 选择方向
public enum SelectionDirection {
    case left // 向左
    case right // 向右
    case up // 向上
    case down // 向下
}

/// 选择状态
public struct SelectionState {
    /// 锚点位置
    public let anchor: Int?

    /// 活动端位置
    public let active: Int?

    /// 是否向前选择
    public let isForward: Bool

    /// 是否正在选择
    public let isSelecting: Bool

    public init(anchor: Int?, active: Int?, isForward: Bool, isSelecting: Bool) {
        self.anchor = anchor
        self.active = active
        self.isForward = isForward
        self.isSelecting = isSelecting
    }
}

// MARK: - Debug Support

public extension SelectionAnchorManager {
    /// 获取调试信息
    ///
    /// - Returns: 包含当前状态的字符串
    func debugDescription() -> String {
        var info = "[SelectionAnchorManager]\n"

        if let anchor = anchorLocation {
            info += "  锚点: \(anchor)\n"
        } else {
            info += "  锚点: 无\n"
        }

        if let active = activeLocation {
            info += "  活动端: \(active)\n"
        } else {
            info += "  活动端: 无\n"
        }

        info += "  方向: \(isForwardSelection ? "向前" : "向后")\n"
        info += "  选择中: \(isSelecting)\n"

        return info
    }
}
