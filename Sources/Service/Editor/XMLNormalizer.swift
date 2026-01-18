//
//  XMLNormalizer.swift
//  MiNoteMac
//
//  Created by Kiro on 2024.
//  Copyright © 2024 Acckion. All rights reserved.
//

import Foundation

/// XML规范化器
///
/// 用于将不同格式的XML内容规范化为统一格式，便于语义比较
///
/// **功能**：
/// - 统一图片格式（旧版 → 新版）
/// - 移除多余空格和换行
/// - 统一属性顺序
/// - 移除无意义的属性差异
@MainActor
public class XMLNormalizer {
    /// 单例
    public static let shared = XMLNormalizer()
    
    /// 私有初始化器，确保单例模式
    private init() {}
    
    // MARK: - 公共方法
    
    /// 规范化XML内容
    ///
    /// 将不同格式的XML内容规范化为统一格式，便于进行语义比较。
    /// 规范化过程包括：
    /// 1. 统一图片格式（旧版 → 新版）
    /// 2. 移除多余空格和换行
    /// 3. 统一属性顺序
    /// 4. 规范化属性值
    ///
    /// - Parameter xml: 原始XML内容
    /// - Returns: 规范化后的XML内容
    public func normalize(_ xml: String) -> String {
        // 记录规范化开始时间
        let startTime = CFAbsoluteTimeGetCurrent()
        
        print("[XMLNormalizer] 🚀 开始规范化 XML 内容")
        print("[XMLNormalizer] 📏 原始内容长度: \(xml.count) 字符")
        
        var normalized = xml
        
        // 1. 统一图片格式
        let imageFormatStart = CFAbsoluteTimeGetCurrent()
        normalized = normalizeImageFormat(normalized)
        let imageFormatTime = (CFAbsoluteTimeGetCurrent() - imageFormatStart) * 1000
        print("[XMLNormalizer] ✅ 图片格式规范化完成，耗时: \(String(format: "%.2f", imageFormatTime))ms")
        
        // 2. 移除多余空格和换行
        let whitespaceStart = CFAbsoluteTimeGetCurrent()
        normalized = removeExtraWhitespace(normalized)
        let whitespaceTime = (CFAbsoluteTimeGetCurrent() - whitespaceStart) * 1000
        print("[XMLNormalizer] ✅ 空格规范化完成，耗时: \(String(format: "%.2f", whitespaceTime))ms")
        
        // 3. 统一属性顺序
        let attributeOrderStart = CFAbsoluteTimeGetCurrent()
        normalized = normalizeAttributeOrder(normalized)
        let attributeOrderTime = (CFAbsoluteTimeGetCurrent() - attributeOrderStart) * 1000
        print("[XMLNormalizer] ✅ 属性顺序规范化完成，耗时: \(String(format: "%.2f", attributeOrderTime))ms")
        
        // 4. 规范化属性值
        let attributeValueStart = CFAbsoluteTimeGetCurrent()
        normalized = normalizeAttributeValues(normalized)
        let attributeValueTime = (CFAbsoluteTimeGetCurrent() - attributeValueStart) * 1000
        print("[XMLNormalizer] ✅ 属性值规范化完成，耗时: \(String(format: "%.2f", attributeValueTime))ms")
        
        // 记录规范化结束时间
        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("[XMLNormalizer] 📏 规范化后内容长度: \(normalized.count) 字符")
        print("[XMLNormalizer] ⏱️ 总耗时: \(String(format: "%.2f", elapsedTime))ms")
        
        // 性能监控：如果耗时超过阈值（10ms），记录警告日志
        if elapsedTime > 10 {
            print("[XMLNormalizer] ⚠️ 警告：规范化耗时超过阈值（10ms）！")
            print("[XMLNormalizer] ⚠️ 实际耗时: \(String(format: "%.2f", elapsedTime))ms")
            print("[XMLNormalizer] ⚠️ 内容长度: \(xml.count) 字符")
            print("[XMLNormalizer] ⚠️ 各步骤耗时详情：")
            print("[XMLNormalizer]    - 图片格式: \(String(format: "%.2f", imageFormatTime))ms")
            print("[XMLNormalizer]    - 空格处理: \(String(format: "%.2f", whitespaceTime))ms")
            print("[XMLNormalizer]    - 属性顺序: \(String(format: "%.2f", attributeOrderTime))ms")
            print("[XMLNormalizer]    - 属性值: \(String(format: "%.2f", attributeValueTime))ms")
        } else {
            print("[XMLNormalizer] ✅ 规范化完成，性能良好（< 10ms）")
        }
        
        return normalized
    }
    
    // MARK: - 私有方法
    
    /// 统一图片格式
    ///
    /// 将旧版图片格式转换为新版格式：
    /// - 旧版：`☺ fileId<0/><description/>` 或 `☺ fileId<imgshow/><description/>`
    /// - 新版：`<img fileid="fileId" imgshow="0" imgdes="" width="500" height="666" />`
    /// - 规范化新版：`<img fileid="fileId" imgdes="" imgshow="0" />`（移除尺寸属性，按字母顺序排列）
    ///
    /// **规范化规则**：
    /// - 保留所有有意义的属性（fileid, imgdes, imgshow）
    /// - 移除尺寸属性（width, height），因为它们不影响内容语义
    /// - 统一属性顺序：fileid → imgdes → imgshow（按字母顺序）
    /// - 保留空值属性（如 `imgdes=""`）
    ///
    /// - Parameter xml: 原始XML内容
    /// - Returns: 图片格式规范化后的XML内容
    private func normalizeImageFormat(_ xml: String) -> String {
        var result = xml
        
        // 1. 处理旧版图片格式：☺ fileId<0/><description/> 或 ☺ fileId<imgshow/><description/>
        // 正则表达式匹配旧版格式
        // 格式：☺ <空格>fileId<0/>或<imgshow/><description/>
        let oldFormatPattern = "☺\\s+([^<]+)<(0|imgshow)\\s*/><([^>]*)\\s*/>"
        
        if let regex = try? NSRegularExpression(pattern: oldFormatPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // 从后往前替换，避免索引变化
            for match in matches.reversed() {
                if match.numberOfRanges == 4 {
                    let fileIdRange = match.range(at: 1)
                    let imgshowRange = match.range(at: 2)
                    let descriptionRange = match.range(at: 3)
                    
                    let fileId = nsString.substring(with: fileIdRange)
                    let imgshowValue = nsString.substring(with: imgshowRange)
                    let description = nsString.substring(with: descriptionRange)
                    
                    // 转换 imgshow 值：<0/> -> "0", <imgshow/> -> "1"
                    let imgshow = (imgshowValue == "0") ? "0" : "1"
                    
                    // 构建规范化的新版格式（按字母顺序：fileid, imgdes, imgshow）
                    let normalized = "<img fileid=\"\(fileId)\" imgdes=\"\(description)\" imgshow=\"\(imgshow)\" />"
                    
                    // 替换
                    let matchRange = match.range
                    result = (nsString.replacingCharacters(in: matchRange, with: normalized) as NSString) as String
                }
            }
        }
        
        // 2. 处理新版图片格式：移除尺寸属性（width, height）
        // 匹配 <img ... /> 标签
        let newFormatPattern = "<img\\s+([^>]+?)\\s*/>"
        
        if let regex = try? NSRegularExpression(pattern: newFormatPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // 从后往前替换，避免索引变化
            for match in matches.reversed() {
                if match.numberOfRanges == 2 {
                    let attributesRange = match.range(at: 1)
                    let attributesString = nsString.substring(with: attributesRange)
                    
                    // 解析属性
                    var attributes: [String: String] = [:]
                    let attrPattern = "(\\w+)\\s*=\\s*\"([^\"]*)\""
                    if let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) {
                        let attrMatches = attrRegex.matches(in: attributesString, options: [], range: NSRange(location: 0, length: (attributesString as NSString).length))
                        
                        for attrMatch in attrMatches {
                            if attrMatch.numberOfRanges == 3 {
                                let key = (attributesString as NSString).substring(with: attrMatch.range(at: 1))
                                let value = (attributesString as NSString).substring(with: attrMatch.range(at: 2))
                                attributes[key] = value
                            }
                        }
                    }
                    
                    // 只保留有语义的属性：fileid, imgdes, imgshow
                    var normalizedAttrs: [(String, String)] = []
                    if let fileid = attributes["fileid"] {
                        normalizedAttrs.append(("fileid", fileid))
                    }
                    if let imgdes = attributes["imgdes"] {
                        normalizedAttrs.append(("imgdes", imgdes))
                    }
                    if let imgshow = attributes["imgshow"] {
                        normalizedAttrs.append(("imgshow", imgshow))
                    }
                    
                    // 按字母顺序排序（fileid, imgdes, imgshow 已经是字母顺序）
                    // 构建规范化的标签
                    let normalizedAttrString = normalizedAttrs.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " ")
                    let normalized = "<img \(normalizedAttrString) />"
                    
                    // 替换
                    let matchRange = match.range
                    result = (nsString.replacingCharacters(in: matchRange, with: normalized) as NSString) as String
                }
            }
        }
        
        return result
    }
    
    /// 移除多余空格和换行
    ///
    /// 规范化XML中的空白字符：
    /// - 移除标签之间的多余空格
    /// - 移除多余的换行符
    /// - 保留标签内的有意义空格
    ///
    /// **处理规则**：
    /// 1. 标签之间的空白字符（空格、制表符、换行符）规范化为单个空格
    /// 2. 标签内的文本内容保持不变（保留有意义的空格）
    /// 3. 自闭合标签（如 `<img />`, `<hr />`）前后的空白规范化
    /// 4. 移除字符串开头和结尾的空白字符
    ///
    /// **示例**：
    /// - 输入：`<text indent="1">  测试  </text>  \n  <text indent="1">文本</text>`
    /// - 输出：`<text indent="1">  测试  </text> <text indent="1">文本</text>`
    ///
    /// - Parameter xml: 原始XML内容
    /// - Returns: 空格规范化后的XML内容
    private func removeExtraWhitespace(_ xml: String) -> String {
        var result = ""
        var insideTag = false
        var insideQuotes = false
        var lastCharWasWhitespace = false
        
        for char in xml {
            // 检测是否在引号内（属性值）
            if char == "\"" && insideTag {
                insideQuotes.toggle()
                result.append(char)
                lastCharWasWhitespace = false
                continue
            }
            
            // 检测标签的开始和结束
            if char == "<" {
                insideTag = true
                result.append(char)
                lastCharWasWhitespace = false
                continue
            }
            
            if char == ">" {
                insideTag = false
                result.append(char)
                lastCharWasWhitespace = false
                continue
            }
            
            // 处理空白字符
            if char.isWhitespace {
                // 在标签内或引号内，保留空格（但规范化为单个空格）
                if insideTag || insideQuotes {
                    if !lastCharWasWhitespace {
                        result.append(" ")
                        lastCharWasWhitespace = true
                    }
                } else {
                    // 在标签之间，规范化为单个空格
                    if !lastCharWasWhitespace && !result.isEmpty {
                        result.append(" ")
                        lastCharWasWhitespace = true
                    }
                }
            } else {
                // 非空白字符，直接添加
                result.append(char)
                lastCharWasWhitespace = false
            }
        }
        
        // 移除开头和结尾的空白字符
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 统一属性顺序
    ///
    /// 将XML标签的属性按字母顺序排序，确保属性顺序不影响比较结果。
    ///
    /// 例如：
    /// - 输入：`<img width="500" fileid="123" height="666" />`
    /// - 输出：`<img fileid="123" height="666" width="500" />`
    ///
    /// - Parameter xml: 原始XML内容
    /// - Returns: 属性顺序规范化后的XML内容
    private func normalizeAttributeOrder(_ xml: String) -> String {
        var result = xml
        
        // 匹配所有XML标签（包括自闭合标签）
        let tagPattern = "<(\\w+)\\s+([^>]+?)(\\s*/?)>"
        
        guard let regex = try? NSRegularExpression(pattern: tagPattern, options: []) else {
            return result
        }
        
        let nsString = result as NSString
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
        
        // 从后往前替换，避免索引变化
        for match in matches.reversed() {
            if match.numberOfRanges == 4 {
                let tagNameRange = match.range(at: 1)
                let attributesRange = match.range(at: 2)
                let closingRange = match.range(at: 3)
                
                let tagName = nsString.substring(with: tagNameRange)
                let attributesString = nsString.substring(with: attributesRange)
                let closing = nsString.substring(with: closingRange)
                
                // 解析属性
                var attributes: [(String, String)] = []
                let attrPattern = "(\\w+)\\s*=\\s*\"([^\"]*)\""
                if let attrRegex = try? NSRegularExpression(pattern: attrPattern, options: []) {
                    let attrMatches = attrRegex.matches(in: attributesString, options: [], range: NSRange(location: 0, length: (attributesString as NSString).length))
                    
                    for attrMatch in attrMatches {
                        if attrMatch.numberOfRanges == 3 {
                            let key = (attributesString as NSString).substring(with: attrMatch.range(at: 1))
                            let value = (attributesString as NSString).substring(with: attrMatch.range(at: 2))
                            attributes.append((key, value))
                        }
                    }
                }
                
                // 按字母顺序排序属性
                attributes.sort { $0.0 < $1.0 }
                
                // 重新组装标签
                let sortedAttrString = attributes.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " ")
                let normalized = "<\(tagName) \(sortedAttrString)\(closing)>"
                
                // 替换
                let matchRange = match.range
                result = (nsString.replacingCharacters(in: matchRange, with: normalized) as NSString) as String
            }
        }
        
        return result
    }
    
    /// 规范化属性值
    ///
    /// 统一属性值的表示方式，同时移除不影响语义的属性：
    /// - 移除尺寸属性（width, height）- 因为它们可能因渲染而变化
    /// - 统一布尔值表示（"0"/"1" vs "false"/"true"）
    /// - 统一数字格式（移除前导零）
    /// - 保留所有有语义的属性（fileid, imgdes, imgshow 等）
    /// - 保留空值属性（如 `imgdes=""`）
    ///
    /// **处理规则**：
    /// 1. 移除所有标签中的 width 和 height 属性
    /// 2. 统一布尔值：将 "true"/"false" 转换为 "1"/"0"
    /// 3. 规范化数字：移除前导零（如 "01" -> "1"）
    /// 4. 保留所有其他有语义的属性
    ///
    /// - Parameter xml: 原始XML内容
    /// - Returns: 属性值规范化后的XML内容
    private func normalizeAttributeValues(_ xml: String) -> String {
        // 注意：图片标签的尺寸属性移除已经在 normalizeImageFormat 中处理
        // 这里处理所有标签的属性值规范化
        
        var result = xml
        
        // 1. 移除所有标签中的 width 和 height 属性
        // 匹配模式：width="任意值" 或 height="任意值"（包括前后可能的空格）
        let sizeAttrPattern = "\\s+(width|height)\\s*=\\s*\"[^\"]*\""
        if let regex = try? NSRegularExpression(pattern: sizeAttrPattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: (result as NSString).length),
                withTemplate: ""
            )
        }
        
        // 2. 统一布尔值表示：将 "true"/"false" 转换为 "1"/"0"
        // 小米笔记使用 "0"/"1" 表示布尔值，确保一致性
        let boolTruePattern = "(\\w+)\\s*=\\s*\"true\""
        if let regex = try? NSRegularExpression(pattern: boolTruePattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // 从后往前替换，避免索引变化
            for match in matches.reversed() {
                if match.numberOfRanges == 2 {
                    let attrNameRange = match.range(at: 1)
                    let attrName = nsString.substring(with: attrNameRange)
                    
                    // 构建规范化的属性
                    let normalized = "\(attrName)=\"1\""
                    
                    // 替换
                    let matchRange = match.range
                    result = (nsString.replacingCharacters(in: matchRange, with: normalized) as NSString) as String
                }
            }
        }
        
        let boolFalsePattern = "(\\w+)\\s*=\\s*\"false\""
        if let regex = try? NSRegularExpression(pattern: boolFalsePattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // 从后往前替换，避免索引变化
            for match in matches.reversed() {
                if match.numberOfRanges == 2 {
                    let attrNameRange = match.range(at: 1)
                    let attrName = nsString.substring(with: attrNameRange)
                    
                    // 构建规范化的属性
                    let normalized = "\(attrName)=\"0\""
                    
                    // 替换
                    let matchRange = match.range
                    result = (nsString.replacingCharacters(in: matchRange, with: normalized) as NSString) as String
                }
            }
        }
        
        // 3. 统一数字格式（移除前导零）
        // 例如：indent="01" -> indent="1"
        // 注意：保留单独的 "0" 值（如 imgshow="0"）
        let numberAttrPattern = "(\\w+)\\s*=\\s*\"0+(\\d+)\""
        if let regex = try? NSRegularExpression(pattern: numberAttrPattern, options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // 从后往前替换，避免索引变化
            for match in matches.reversed() {
                if match.numberOfRanges == 3 {
                    let attrNameRange = match.range(at: 1)
                    let numberRange = match.range(at: 2)
                    
                    let attrName = nsString.substring(with: attrNameRange)
                    let number = nsString.substring(with: numberRange)
                    
                    // 构建规范化的属性
                    let normalized = "\(attrName)=\"\(number)\""
                    
                    // 替换
                    let matchRange = match.range
                    result = (nsString.replacingCharacters(in: matchRange, with: normalized) as NSString) as String
                }
            }
        }
        
        return result
    }
}
