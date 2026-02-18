import AppKit
import Foundation

/// 撤销合并策略
/// 定义如何将连续的编辑操作合并为单个撤销操作
public enum UndoCoalescingStrategy {
    /// 连续输入合并：将连续的文本输入合并为一个撤销操作
    case continuous

    /// 基于单词边界：在单词边界处分组撤销操作
    case wordBased

    /// 基于时间间隔：在指定时间间隔后开始新的撤销分组
    case timeBased(TimeInterval)

    /// 混合策略：结合多种策略
    case hybrid([UndoCoalescingStrategy])
}

/// 撤销合并管理器
/// 负责智能地将连续的编辑操作合并为合理的撤销分组
///
/// **核心功能**:
/// - 连续输入合并：将连续的文本输入合并为单个撤销操作
/// - 单词边界检测：在单词边界处自动分组
/// - 时间间隔检测：超过指定时间后开始新分组
/// - 非输入操作检测：格式切换、光标移动等操作结束当前分组
///
/// _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_
public class UndoCoalescingManager {
    // MARK: - Properties

    /// 当前使用的撤销合并策略
    public var strategy: UndoCoalescingStrategy

    /// 当前撤销分组的起始位置
    private var currentGroupStart: Int?

    /// 上次输入的时间
    private var lastInputTime: Date?

    /// 上次输入的位置
    private var lastInputLocation: Int?

    /// 当前分组是否处于活动状态
    private var isGroupActive = false

    /// 默认的时间间隔阈值（秒）
    private let defaultTimeInterval: TimeInterval = 2.0

    /// 撤销管理器引用
    private weak var undoManager: UndoManager?

    // MARK: - Initialization

    /// 初始化撤销合并管理器
    /// - Parameters:
    ///   - strategy: 撤销合并策略，默认为连续输入合并
    ///   - undoManager: 撤销管理器引用
    public init(
        strategy: UndoCoalescingStrategy = .continuous,
        undoManager: UndoManager? = nil
    ) {
        self.strategy = strategy
        self.undoManager = undoManager
    }

    // MARK: - Public Methods

    /// 判断是否应该开始新的撤销分组
    ///
    /// 根据当前策略和输入上下文判断是否需要结束当前分组并开始新分组。
    ///
    /// **判断依据**:
    /// - 连续性：输入位置是否连续
    /// - 时间间隔：距离上次输入的时间
    /// - 单词边界：是否在单词边界处
    /// - 字符类型：是否为特殊字符（换行符、标点等）
    ///
    /// _Requirements: 11.1, 11.3, 11.4, 11.5, 11.6_
    ///
    /// - Parameters:
    ///   - change: 文本变化内容
    ///   - location: 变化位置
    /// - Returns: 如果应该开始新分组返回 true，否则返回 false
    public func shouldStartNewGroup(for change: String, at location: Int) -> Bool {
        // 如果没有活动分组，应该开始新分组
        guard isGroupActive else {
            return true
        }

        // 根据策略判断
        switch strategy {
        case .continuous:
            return shouldStartNewGroupForContinuous(change: change, location: location)

        case .wordBased:
            return shouldStartNewGroupForWordBased(change: change, location: location)

        case let .timeBased(interval):
            return shouldStartNewGroupForTimeBased(interval: interval)

        case let .hybrid(strategies):
            // 混合策略：任何一个策略认为应该开始新分组，就开始新分组
            for subStrategy in strategies {
                let tempManager = UndoCoalescingManager(strategy: subStrategy)
                tempManager.currentGroupStart = currentGroupStart
                tempManager.lastInputTime = lastInputTime
                tempManager.lastInputLocation = lastInputLocation
                tempManager.isGroupActive = isGroupActive

                if tempManager.shouldStartNewGroup(for: change, at: location) {
                    return true
                }
            }
            return false
        }
    }

    /// 开始新的撤销分组
    ///
    /// 结束当前分组（如果存在）并开始新的撤销分组。
    ///
    /// _Requirements: 11.2_
    ///
    /// - Parameter location: 新分组的起始位置
    public func beginNewGroup(at location: Int) {
        // 如果有活动分组，先结束它
        if isGroupActive {
            endCurrentGroup()
        }

        // 开始新分组
        currentGroupStart = location
        lastInputTime = Date()
        lastInputLocation = location
        isGroupActive = true

        // 通知撤销管理器开始新分组
        undoManager?.beginUndoGrouping()

        #if DEBUG
            print("[UndoCoalescingManager] 开始新的撤销分组，位置: \(location)")
        #endif
    }

    /// 结束当前撤销分组
    ///
    /// 结束当前活动的撤销分组，使其成为一个完整的撤销操作。
    ///
    /// _Requirements: 11.2_
    public func endCurrentGroup() {
        guard isGroupActive else {
            return
        }

        // 结束分组
        isGroupActive = false
        currentGroupStart = nil
        lastInputTime = nil
        lastInputLocation = nil

        // 通知撤销管理器结束分组
        undoManager?.endUndoGrouping()

        #if DEBUG
            print("[UndoCoalescingManager] 结束当前撤销分组")
        #endif
    }

    /// 记录输入操作
    ///
    /// 更新输入状态，用于后续的分组判断。
    ///
    /// - Parameters:
    ///   - change: 文本变化内容
    ///   - location: 变化位置
    public func recordInput(change _: String, at location: Int) {
        lastInputTime = Date()
        lastInputLocation = location

        // 如果还没有活动分组，开始新分组
        if !isGroupActive {
            beginNewGroup(at: location)
        }
    }

    /// 处理非输入操作
    ///
    /// 当用户执行非输入操作（如格式切换、光标移动等）时调用。
    /// 这些操作应该结束当前的撤销分组。
    ///
    /// _Requirements: 11.2_
    public func handleNonTypingAction() {
        if isGroupActive {
            endCurrentGroup()
        }

        #if DEBUG
            print("[UndoCoalescingManager] 处理非输入操作，结束当前分组")
        #endif
    }

    /// 更新策略
    ///
    /// 动态更改撤销合并策略。
    ///
    /// - Parameter newStrategy: 新的策略
    public func updateStrategy(_ newStrategy: UndoCoalescingStrategy) {
        // 如果有活动分组，先结束它
        if isGroupActive {
            endCurrentGroup()
        }

        strategy = newStrategy

        #if DEBUG
            print("[UndoCoalescingManager] 更新策略: \(newStrategy)")
        #endif
    }

    // MARK: - Private Helper Methods

    /// 连续输入策略的分组判断
    ///
    /// **判断规则**:
    /// - 输入位置不连续 → 开始新分组
    /// - 输入换行符 → 开始新分组
    /// - 删除操作方向改变 → 开始新分组
    ///
    /// _Requirements: 11.1_
    private func shouldStartNewGroupForContinuous(
        change: String,
        location: Int
    ) -> Bool {
        guard let lastLocation = lastInputLocation else {
            return true
        }

        // 检查输入位置是否连续
        // 对于插入操作，新位置应该紧跟在上次位置之后
        // 对于删除操作，新位置应该等于上次位置
        let isInsert = !change.isEmpty
        let expectedLocation = isInsert ? lastLocation + 1 : lastLocation

        if location != expectedLocation && location != lastLocation {
            #if DEBUG
                print("[UndoCoalescingManager] 位置不连续: \(location) vs \(expectedLocation)")
            #endif
            return true
        }

        // 检查是否输入了换行符
        if change.contains("\n") || change.contains("\r") {
            #if DEBUG
                print("[UndoCoalescingManager] 输入换行符")
            #endif
            return true
        }

        return false
    }

    /// 基于单词边界的分组判断
    ///
    /// **判断规则**:
    /// - 输入空格或标点 → 开始新分组
    /// - 输入换行符 → 开始新分组
    /// - 位置不连续 → 开始新分组
    ///
    /// _Requirements: 11.4_
    private func shouldStartNewGroupForWordBased(
        change: String,
        location: Int
    ) -> Bool {
        // 首先检查连续性
        if shouldStartNewGroupForContinuous(change: change, location: location) {
            return true
        }

        // 检查是否在单词边界
        if isWordBoundary(change) {
            #if DEBUG
                print("[UndoCoalescingManager] 单词边界: \(change)")
            #endif
            return true
        }

        return false
    }

    /// 基于时间间隔的分组判断
    ///
    /// **判断规则**:
    /// - 距离上次输入超过指定时间间隔 → 开始新分组
    ///
    /// _Requirements: 11.3_
    private func shouldStartNewGroupForTimeBased(interval: TimeInterval) -> Bool {
        guard let lastTime = lastInputTime else {
            return true
        }

        let elapsed = Date().timeIntervalSince(lastTime)
        if elapsed > interval {
            #if DEBUG
                print("[UndoCoalescingManager] 时间间隔超过阈值: \(elapsed)s > \(interval)s")
            #endif
            return true
        }

        return false
    }

    /// 判断字符是否为单词边界
    ///
    /// **单词边界字符**:
    /// - 空格
    /// - 标点符号
    /// - 换行符
    ///
    /// - Parameter text: 要检查的文本
    /// - Returns: 如果是单词边界返回 true，否则返回 false
    private func isWordBoundary(_ text: String) -> Bool {
        // 空字符串不是单词边界
        guard !text.isEmpty else {
            return false
        }

        // 检查是否包含空格或换行符
        if text.contains(" ") || text.contains("\n") || text.contains("\r") || text.contains("\t") {
            return true
        }

        // 检查是否为标点符号
        let punctuationSet = CharacterSet.punctuationCharacters
        for scalar in text.unicodeScalars {
            if punctuationSet.contains(scalar) {
                return true
            }
        }

        return false
    }
}

// MARK: - Strategy Configuration

public extension UndoCoalescingManager {
    /// 创建默认的混合策略
    ///
    /// 结合连续输入、单词边界和时间间隔三种策略。
    ///
    /// - Parameter timeInterval: 时间间隔阈值，默认 2 秒
    /// - Returns: 混合策略
    static func defaultHybridStrategy(
        timeInterval: TimeInterval = 2.0
    ) -> UndoCoalescingStrategy {
        .hybrid([
            .continuous,
            .wordBased,
            .timeBased(timeInterval),
        ])
    }

    /// 创建适合代码编辑的策略
    ///
    /// 更频繁地在单词边界和换行符处分组。
    ///
    /// - Returns: 代码编辑策略
    static func codeEditingStrategy() -> UndoCoalescingStrategy {
        .hybrid([
            .wordBased,
            .timeBased(1.5),
        ])
    }

    /// 创建适合长文本编辑的策略
    ///
    /// 更宽松的分组策略，减少撤销操作的数量。
    ///
    /// - Returns: 长文本编辑策略
    static func longTextEditingStrategy() -> UndoCoalescingStrategy {
        .hybrid([
            .continuous,
            .timeBased(3.0),
        ])
    }
}

// MARK: - Debug Support

public extension UndoCoalescingManager {
    /// 获取当前状态的调试信息
    ///
    /// - Returns: 包含当前状态的字符串
    func debugDescription() -> String {
        var info = "[UndoCoalescingManager]\n"
        info += "  策略: \(strategy)\n"
        info += "  活动分组: \(isGroupActive)\n"

        if let start = currentGroupStart {
            info += "  分组起始位置: \(start)\n"
        }

        if let lastTime = lastInputTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            info += "  距离上次输入: \(String(format: "%.2f", elapsed))s\n"
        }

        if let lastLoc = lastInputLocation {
            info += "  上次输入位置: \(lastLoc)\n"
        }

        return info
    }
}
