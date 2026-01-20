import Foundation
import AppKit

/// 文本容器布局配置
/// 定义文本容器的布局参数
/// 
/// _Requirements: 14.1, 14.2_
public struct TextContainerLayoutConfig: Sendable {
    /// 首选行长度（字符数或点数）
    public let preferredLineLength: CGFloat
    
    /// 最小边距
    public let minimumMargin: CGFloat
    
    /// 是否允许非对称布局
    public let allowAsymmetricLayout: Bool
    
    /// 默认配置
    public static let `default` = TextContainerLayoutConfig(
        preferredLineLength: 680,  // 约 80-90 个字符
        minimumMargin: 40,
        allowAsymmetricLayout: false
    )
    
    public init(
        preferredLineLength: CGFloat,
        minimumMargin: CGFloat,
        allowAsymmetricLayout: Bool
    ) {
        self.preferredLineLength = preferredLineLength
        self.minimumMargin = minimumMargin
        self.allowAsymmetricLayout = allowAsymmetricLayout
    }
}

/// 文本容器布局管理器
/// 负责智能地管理文本容器的布局，优化阅读体验
/// 
/// **核心功能**:
/// - 维护首选的行长度
/// - 在可用空间内均匀分配侧边距
/// - 响应窗口尺寸变化
/// - 支持渐进式边距折叠
/// 
/// _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6_
public class TextContainerLayoutManager {
    // MARK: - Properties
    
    /// 布局配置
    public var config: TextContainerLayoutConfig
    
    /// 关联的文本容器（弱引用）
    private weak var textContainer: NSTextContainer?
    
    /// 关联的滚动视图（弱引用）
    private weak var scrollView: NSScrollView?
    
    /// 当前计算的容器尺寸
    private var currentContainerSize: NSSize = .zero
    
    /// 当前计算的边距
    private var currentMargins: (left: CGFloat, right: CGFloat) = (0, 0)
    
    // MARK: - Initialization
    
    /// 初始化文本容器布局管理器
    /// - Parameters:
    ///   - config: 布局配置
    ///   - textContainer: 关联的文本容器
    ///   - scrollView: 关联的滚动视图
    public init(
        config: TextContainerLayoutConfig = .default,
        textContainer: NSTextContainer? = nil,
        scrollView: NSScrollView? = nil
    ) {
        self.config = config
        self.textContainer = textContainer
        self.scrollView = scrollView
        
        #if DEBUG
        print("[TextContainerLayoutManager] 初始化，配置: \(config)")
        #endif
    }
    
    // MARK: - Public Methods - 布局计算
    
    /// 计算文本容器尺寸
    /// 
    /// 根据可用宽度和配置计算最优的文本容器尺寸。
    /// 
    /// **计算策略**:
    /// 1. 如果可用宽度 >= 首选行长度 + 2 * 最小边距，使用首选行长度
    /// 2. 否则，使用可用宽度 - 2 * 最小边距
    /// 3. 确保容器宽度不小于最小值
    /// 
    /// _Requirements: 14.1, 14.2_
    /// 
    /// - Parameter availableWidth: 可用宽度
    /// - Returns: 文本容器尺寸
    public func calculateContainerSize(availableWidth: CGFloat) -> NSSize {
        let (leftMargin, rightMargin) = calculateMargins(availableWidth: availableWidth)
        
        // 计算容器宽度
        let containerWidth = availableWidth - leftMargin - rightMargin
        
        // 容器高度设为无限大，允许垂直滚动
        let containerHeight = CGFloat.greatestFiniteMagnitude
        
        let size = NSSize(width: containerWidth, height: containerHeight)
        currentContainerSize = size
        
        #if DEBUG
        print("[TextContainerLayoutManager] 计算容器尺寸: \(size), 可用宽度: \(availableWidth)")
        #endif
        
        return size
    }
    
    /// 计算边距
    /// 
    /// 根据可用宽度和配置计算左右边距。
    /// 
    /// **计算策略**:
    /// 1. 优先保持首选行长度
    /// 2. 如果空间充足，均匀分配剩余空间作为边距
    /// 3. 如果空间不足，使用最小边距
    /// 4. 使用渐进式边距折叠算法平滑过渡
    /// 
    /// _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_
    /// 
    /// - Parameter availableWidth: 可用宽度
    /// - Returns: 左右边距
    public func calculateMargins(availableWidth: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let preferredWidth = config.preferredLineLength
        let minMargin = config.minimumMargin
        
        // 计算理想情况下的总边距
        let idealTotalMargin = availableWidth - preferredWidth
        
        if idealTotalMargin >= 2 * minMargin {
            // 空间充足：均匀分配边距
            // _Requirements: 14.2 - 在可用空间内均匀分配侧边距
            let margin = idealTotalMargin / 2
            currentMargins = (margin, margin)
            
            #if DEBUG
            print("[TextContainerLayoutManager] 空间充足，均匀分配边距: \(margin)")
            #endif
        } else {
            // 空间不足：使用渐进式边距折叠
            // _Requirements: 14.5 - 使用数学函数实现渐进式边距折叠
            let margin = calculateProgressiveMargin(
                availableWidth: availableWidth,
                preferredWidth: preferredWidth,
                minMargin: minMargin
            )
            currentMargins = (margin, margin)
            
            #if DEBUG
            print("[TextContainerLayoutManager] 空间不足，渐进式边距: \(margin)")
            #endif
        }
        
        return currentMargins
    }
    
    /// 处理窗口尺寸变化
    /// 
    /// 当窗口尺寸变化时，重新计算布局并应用。
    /// 
    /// **处理策略**:
    /// 1. 优先保持行长度
    /// 2. 如果空间不足，优先保持最小边距
    /// 3. 平滑过渡，避免突变
    /// 
    /// _Requirements: 14.3, 14.4_
    /// 
    /// - Parameter newSize: 新的窗口尺寸
    public func handleWindowResize(newSize: NSSize) {
        #if DEBUG
        print("[TextContainerLayoutManager] 处理窗口尺寸变化: \(newSize)")
        #endif
        
        // 计算新的容器尺寸
        let containerSize = calculateContainerSize(availableWidth: newSize.width)
        
        // 应用到文本容器
        applyLayout(containerSize: containerSize)
    }
    
    // MARK: - Public Methods - 布局应用
    
    /// 应用布局
    /// 
    /// 将计算的布局应用到文本容器。
    /// 
    /// - Parameter containerSize: 容器尺寸
    public func applyLayout(containerSize: NSSize) {
        guard let textContainer = textContainer else {
            #if DEBUG
            print("[TextContainerLayoutManager] 警告：文本容器不可用")
            #endif
            return
        }
        
        // 设置容器尺寸
        textContainer.containerSize = containerSize
        
        // 如果支持非对称布局，可以在这里设置额外的布局参数
        // _Requirements: 14.6 - 支持非对称布局
        if config.allowAsymmetricLayout {
            // 预留：可以设置不同的左右边距
            // 例如：为标题标签留出空间
        }
        
        #if DEBUG
        print("[TextContainerLayoutManager] 布局已应用: \(containerSize)")
        #endif
    }
    
    /// 更新配置
    /// 
    /// 动态更新布局配置并重新计算布局。
    /// 
    /// - Parameter newConfig: 新的配置
    public func updateConfig(_ newConfig: TextContainerLayoutConfig) {
        config = newConfig
        
        // 重新计算并应用布局
        if let scrollView = scrollView {
            let availableWidth = scrollView.contentView.bounds.width
            let containerSize = calculateContainerSize(availableWidth: availableWidth)
            applyLayout(containerSize: containerSize)
        }
        
        #if DEBUG
        print("[TextContainerLayoutManager] 配置已更新: \(newConfig)")
        #endif
    }
    
    // MARK: - Private Helper Methods
    
    /// 计算渐进式边距
    /// 
    /// 使用数学函数实现平滑的边距折叠。
    /// 当可用空间减少时，边距逐渐从理想值过渡到最小值。
    /// 
    /// **数学模型**:
    /// 使用 sigmoid 函数的变体实现平滑过渡：
    /// margin = minMargin + (idealMargin - minMargin) * smoothFactor
    /// 
    /// _Requirements: 14.5_
    /// 
    /// - Parameters:
    ///   - availableWidth: 可用宽度
    ///   - preferredWidth: 首选行长度
    ///   - minMargin: 最小边距
    /// - Returns: 计算的边距
    private func calculateProgressiveMargin(
        availableWidth: CGFloat,
        preferredWidth: CGFloat,
        minMargin: CGFloat
    ) -> CGFloat {
        // 计算理想边距（如果空间充足）
        let idealMargin = (availableWidth - preferredWidth) / 2
        
        // 如果理想边距已经小于最小边距，直接返回最小边距
        guard idealMargin < minMargin else {
            return idealMargin
        }
        
        // 计算可用于内容的宽度（扣除最小边距）
        let contentWidth = availableWidth - 2 * minMargin
        
        // 如果内容宽度小于首选宽度，需要折叠边距
        if contentWidth < preferredWidth {
            // 计算折叠因子（0 到 1 之间）
            // 当 contentWidth = preferredWidth 时，factor = 1（不折叠）
            // 当 contentWidth = 0 时，factor = 0（完全折叠）
            let factor = max(0, contentWidth / preferredWidth)
            
            // 使用平滑函数（ease-out）
            let smoothFactor = 1 - pow(1 - factor, 2)
            
            // 计算实际边距
            let margin = minMargin * smoothFactor
            
            return max(0, margin)
        }
        
        return minMargin
    }
}

// MARK: - Convenience Methods

extension TextContainerLayoutManager {
    /// 注册文本容器和滚动视图
    /// 
    /// - Parameters:
    ///   - textContainer: 文本容器
    ///   - scrollView: 滚动视图
    public func register(textContainer: NSTextContainer, scrollView: NSScrollView) {
        self.textContainer = textContainer
        self.scrollView = scrollView
        
        // 初始化布局
        let availableWidth = scrollView.contentView.bounds.width
        let containerSize = calculateContainerSize(availableWidth: availableWidth)
        applyLayout(containerSize: containerSize)
        
        #if DEBUG
        print("[TextContainerLayoutManager] 已注册文本容器和滚动视图")
        #endif
    }
    
    /// 取消注册
    public func unregister() {
        textContainer = nil
        scrollView = nil
        
        #if DEBUG
        print("[TextContainerLayoutManager] 已取消注册")
        #endif
    }
}

// MARK: - Debug Support

extension TextContainerLayoutManager {
    /// 获取调试信息
    /// 
    /// - Returns: 包含当前状态的字符串
    public func debugDescription() -> String {
        var info = "[TextContainerLayoutManager]\n"
        info += "  首选行长度: \(config.preferredLineLength)\n"
        info += "  最小边距: \(config.minimumMargin)\n"
        info += "  允许非对称布局: \(config.allowAsymmetricLayout)\n"
        info += "  当前容器尺寸: \(currentContainerSize)\n"
        info += "  当前边距: 左=\(currentMargins.left), 右=\(currentMargins.right)\n"
        
        return info
    }
}
