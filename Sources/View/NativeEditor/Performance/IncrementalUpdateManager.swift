import Foundation
import AppKit

/// 增量更新管理器
/// 
/// 负责实现编辑器的增量更新机制，包括：
/// 1. 识别受影响的段落
/// 2. 跟踪段落版本
/// 3. 优化更新性能，只更新必要的段落
/// 
/// 设计理念：
/// - 根据变化范围确定受影响的段落
/// - 检查元属性是否变化，决定是否需要完整重新解析
/// - 使用版本号跟踪段落状态，跳过未变化的段落
/// 
/// _Requirements: 4.2, 4.3, 4.4, 4.5_
public class IncrementalUpdateManager {
    // MARK: - Properties
    
    /// 段落管理器引用
    private weak var paragraphManager: ParagraphManager?
    
    /// 调试日志开关
    private let enableDebugLog: Bool
    
    // MARK: - Initialization
    
    /// 初始化增量更新管理器
    /// - Parameters:
    ///   - paragraphManager: 段落管理器
    ///   - enableDebugLog: 是否启用调试日志，默认为 false
    public init(paragraphManager: ParagraphManager, enableDebugLog: Bool = false) {
        self.paragraphManager = paragraphManager
        self.enableDebugLog = enableDebugLog
    }
    
    // MARK: - 8.1 受影响段落识别
    
    /// 识别受变化影响的段落
    /// 
    /// 根据变化范围确定哪些段落受到影响，需要重新解析或更新。
    /// 
    /// 识别策略：
    /// 1. 查找与变化范围有交集的所有段落
    /// 2. 检查元属性是否变化（如段落类型、列表类型等）
    /// 3. 标记需要重新解析的段落
    /// 
    /// - Parameters:
    ///   - changedRange: 文本变化的范围
    ///   - textStorage: 文本存储
    /// - Returns: 受影响的段落数组
    /// 
    /// _Requirements: 4.2, 4.3_
    public func identifyAffectedParagraphs(
        changedRange: NSRange,
        in textStorage: NSTextStorage
    ) -> [Paragraph] {
        guard let paragraphManager = paragraphManager else {
            logDebug("⚠️ 段落管理器不可用")
            return []
        }
        
        logDebug("🔍 识别受影响的段落，变化范围: \(changedRange)")
        
        // 1. 获取与变化范围有交集的所有段落
        let intersectingParagraphs = paragraphManager.paragraphs(in: changedRange)
        
        logDebug("   找到 \(intersectingParagraphs.count) 个交集段落")
        
        // 2. 检查每个段落的元属性是否变化
        var affectedParagraphs: [Paragraph] = []
        
        for paragraph in intersectingParagraphs {
            var needsUpdate = false
            var updateReason = ""
            
            // 检查段落范围是否与变化范围有交集
            let intersection = NSIntersectionRange(paragraph.range, changedRange)
            if intersection.length > 0 {
                needsUpdate = true
                updateReason = "范围交集"
            }
            
            // 检查元属性是否变化
            if hasMetaAttributeChanged(in: paragraph, textStorage: textStorage) {
                needsUpdate = true
                updateReason += (updateReason.isEmpty ? "" : ", ") + "元属性变化"
            }
            
            // 检查段落是否已标记为需要重新解析
            if paragraph.needsReparse {
                needsUpdate = true
                updateReason += (updateReason.isEmpty ? "" : ", ") + "已标记需要重新解析"
            }
            
            if needsUpdate {
                affectedParagraphs.append(paragraph)
                logDebug("   ✓ 段落 \(paragraph.range) 受影响: \(updateReason)")
            } else {
                logDebug("   - 段落 \(paragraph.range) 未受影响")
            }
        }
        
        logDebug("✅ 识别完成，共 \(affectedParagraphs.count) 个受影响段落")
        
        return affectedParagraphs
    }
    
    /// 检查段落的元属性是否变化
    /// 
    /// 元属性包括：
    /// - 段落类型（.paragraphType）
    /// - 列表类型（.listType）
    /// - 标题标记（.isTitle）
    /// - 列表级别（.listLevel）
    /// 
    /// - Parameters:
    ///   - paragraph: 段落对象
    ///   - textStorage: 文本存储
    /// - Returns: 如果元属性变化返回 true，否则返回 false
    private func hasMetaAttributeChanged(
        in paragraph: Paragraph,
        textStorage: NSTextStorage
    ) -> Bool {
        // 如果段落范围无效，认为元属性未变化
        guard paragraph.range.location + paragraph.range.length <= textStorage.length else {
            return false
        }
        
        // 获取段落起始位置的当前属性
        let currentAttributes = textStorage.attributes(
            at: paragraph.range.location,
            effectiveRange: nil
        )
        
        // 检查段落类型是否变化
        let currentParagraphType = currentAttributes[.paragraphType] as? ParagraphType
        let storedParagraphType = paragraph.metaAttributes["paragraphType"] as? ParagraphType
        
        if currentParagraphType != storedParagraphType {
            logDebug("      元属性变化: 段落类型 \(String(describing: storedParagraphType)) -> \(String(describing: currentParagraphType))")
            return true
        }
        
        // 检查列表类型是否变化
        let currentListType = currentAttributes[.listType] as? ListType
        let storedListType = paragraph.metaAttributes["listType"] as? ListType
        
        if currentListType != storedListType {
            logDebug("      元属性变化: 列表类型 \(String(describing: storedListType)) -> \(String(describing: currentListType))")
            return true
        }
        
        // 检查标题标记是否变化
        let currentIsTitle = currentAttributes[.isTitle] as? Bool ?? false
        let storedIsTitle = paragraph.metaAttributes["isTitle"] as? Bool ?? false
        
        if currentIsTitle != storedIsTitle {
            logDebug("      元属性变化: 标题标记 \(storedIsTitle) -> \(currentIsTitle)")
            return true
        }
        
        // 检查列表级别是否变化
        let currentListLevel = currentAttributes[.listLevel] as? Int
        let storedListLevel = paragraph.metaAttributes["listLevel"] as? Int
        
        if currentListLevel != storedListLevel {
            logDebug("      元属性变化: 列表级别 \(String(describing: storedListLevel)) -> \(String(describing: currentListLevel))")
            return true
        }
        
        return false
    }
    
    // MARK: - 8.2 段落版本跟踪
    
    /// 为段落递增版本号
    /// 
    /// 当段落内容变化时，递增其版本号。
    /// 版本号用于判断段落是否需要更新。
    /// 
    /// - Parameter paragraph: 段落对象
    /// - Returns: 版本号递增后的新段落对象
    /// 
    /// _Requirements: 4.4_
    public func incrementParagraphVersion(_ paragraph: Paragraph) -> Paragraph {
        let newParagraph = paragraph.incrementVersion()
        logDebug("📈 段落 \(paragraph.range) 版本递增: \(paragraph.version) -> \(newParagraph.version)")
        return newParagraph
    }
    
    /// 检查段落是否需要更新
    /// 
    /// 基于版本号和重新解析标记判断段落是否需要更新。
    /// 
    /// - Parameters:
    ///   - paragraph: 段落对象
    ///   - lastProcessedVersion: 上次处理的版本号
    /// - Returns: 如果需要更新返回 true，否则返回 false
    /// 
    /// _Requirements: 4.4_
    public func shouldUpdateParagraph(
        _ paragraph: Paragraph,
        lastProcessedVersion: Int
    ) -> Bool {
        // 如果段落标记为需要重新解析，则需要更新
        if paragraph.needsReparse {
            logDebug("   段落 \(paragraph.range) 需要更新: 标记为需要重新解析")
            return true
        }
        
        // 如果版本号大于上次处理的版本，则需要更新
        if paragraph.version > lastProcessedVersion {
            logDebug("   段落 \(paragraph.range) 需要更新: 版本 \(paragraph.version) > \(lastProcessedVersion)")
            return true
        }
        
        logDebug("   段落 \(paragraph.range) 无需更新: 版本 \(paragraph.version) <= \(lastProcessedVersion)")
        return false
    }
    
    /// 标记段落需要重新解析
    /// 
    /// - Parameter paragraph: 段落对象
    /// - Returns: 标记后的新段落对象
    public func markParagraphNeedsReparse(_ paragraph: Paragraph) -> Paragraph {
        let newParagraph = paragraph.markNeedsReparse()
        logDebug("🔄 段落 \(paragraph.range) 标记为需要重新解析")
        return newParagraph
    }
    
    /// 清除段落的重新解析标记
    /// 
    /// - Parameter paragraph: 段落对象
    /// - Returns: 清除标记后的新段落对象
    public func clearParagraphReparseFlag(_ paragraph: Paragraph) -> Paragraph {
        let newParagraph = paragraph.clearReparseFlag()
        logDebug("✓ 段落 \(paragraph.range) 清除重新解析标记")
        return newParagraph
    }
    
    // MARK: - 8.3 增量更新逻辑
    
    /// 执行增量更新
    /// 
    /// 只更新受影响的段落，跳过未变化的段落，以优化性能。
    /// 
    /// 更新策略：
    /// 1. 识别受影响的段落
    /// 2. 对于每个受影响的段落：
    ///    - 如果元属性变化，执行完整重新解析
    ///    - 如果只是内容变化，只更新布局和装饰属性
    /// 3. 跳过未受影响的段落
    /// 
    /// - Parameters:
    ///   - changedRange: 文本变化的范围
    ///   - textStorage: 文本存储
    ///   - updateHandler: 更新处理闭包，接收需要更新的段落
    /// - Returns: 更新的段落数量
    /// 
    /// _Requirements: 4.5_
    public func performIncrementalUpdate(
        changedRange: NSRange,
        in textStorage: NSTextStorage,
        updateHandler: (Paragraph) -> Void
    ) -> Int {
        logDebug("🚀 开始增量更新，变化范围: \(changedRange)")
        
        // 1. 识别受影响的段落
        let affectedParagraphs = identifyAffectedParagraphs(
            changedRange: changedRange,
            in: textStorage
        )
        
        guard !affectedParagraphs.isEmpty else {
            logDebug("✅ 无受影响段落，跳过更新")
            return 0
        }
        
        // 2. 更新受影响的段落
        var updatedCount = 0
        
        for paragraph in affectedParagraphs {
            logDebug("   更新段落 \(paragraph.range)")
            updateHandler(paragraph)
            updatedCount += 1
        }
        
        logDebug("✅ 增量更新完成，共更新 \(updatedCount) 个段落")
        
        return updatedCount
    }
    
    /// 批量更新段落版本
    /// 
    /// 为多个段落批量递增版本号。
    /// 
    /// - Parameter paragraphs: 段落数组
    /// - Returns: 版本号递增后的新段落数组
    public func batchIncrementVersions(_ paragraphs: [Paragraph]) -> [Paragraph] {
        logDebug("📊 批量更新 \(paragraphs.count) 个段落的版本")
        return paragraphs.map { incrementParagraphVersion($0) }
    }
    
    /// 优化更新：跳过未变化的段落
    /// 
    /// 过滤出真正需要更新的段落，跳过未变化的段落。
    /// 
    /// - Parameters:
    ///   - paragraphs: 候选段落数组
    ///   - lastProcessedVersions: 上次处理的版本号字典（段落位置 -> 版本号）
    /// - Returns: 需要更新的段落数组
    /// 
    /// _Requirements: 4.5_
    public func filterParagraphsNeedingUpdate(
        _ paragraphs: [Paragraph],
        lastProcessedVersions: [Int: Int]
    ) -> [Paragraph] {
        logDebug("🔍 过滤需要更新的段落")
        
        let needsUpdate = paragraphs.filter { paragraph in
            let lastVersion = lastProcessedVersions[paragraph.range.location] ?? -1
            return shouldUpdateParagraph(paragraph, lastProcessedVersion: lastVersion)
        }
        
        let skippedCount = paragraphs.count - needsUpdate.count
        logDebug("   需要更新: \(needsUpdate.count) 个，跳过: \(skippedCount) 个")
        
        return needsUpdate
    }
    
    // MARK: - Debug Logging
    
    /// 输出调试日志
    /// - Parameter message: 日志消息
    private func logDebug(_ message: String) {
        if enableDebugLog {
            print("[IncrementalUpdateManager] \(message)")
        }
    }
}

// MARK: - Update Statistics

/// 增量更新统计信息
public struct IncrementalUpdateStatistics {
    /// 总段落数
    let totalParagraphs: Int
    
    /// 受影响的段落数
    let affectedParagraphs: Int
    
    /// 实际更新的段落数
    let updatedParagraphs: Int
    
    /// 跳过的段落数
    var skippedParagraphs: Int {
        affectedParagraphs - updatedParagraphs
    }
    
    /// 更新效率（跳过的段落占比）
    var efficiency: Double {
        guard affectedParagraphs > 0 else { return 0 }
        return Double(skippedParagraphs) / Double(affectedParagraphs)
    }
    
    /// 描述信息
    var description: String {
        """
        增量更新统计:
        - 总段落数: \(totalParagraphs)
        - 受影响段落: \(affectedParagraphs)
        - 实际更新: \(updatedParagraphs)
        - 跳过: \(skippedParagraphs)
        - 效率: \(String(format: "%.1f%%", efficiency * 100))
        """
    }
}
