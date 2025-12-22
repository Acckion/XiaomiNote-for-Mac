import Foundation

/// XML转换可逆性测试
/// 
/// 用于验证小米笔记XML格式与NSAttributedString之间的转换是否完全可逆
/// 这是确保数据完整性的关键测试
class XMLReversibilityTest {
    
    // MARK: - 测试用例
    
    /// 运行所有可逆性测试
    static func runAllTests() {
        print("🧪 [XMLReversibilityTest] ========== 开始可逆性测试 ==========")
        
        var passedTests = 0
        var failedTests = 0
        
        // 测试1: 简单文本
        if testSimpleText() {
            passedTests += 1
            print("✅ 测试1通过: 简单文本")
        } else {
            failedTests += 1
            print("❌ 测试1失败: 简单文本")
        }
        
        // 测试2: 格式化文本（加粗、斜体）
        if testFormattedText() {
            passedTests += 1
            print("✅ 测试2通过: 格式化文本")
        } else {
            failedTests += 1
            print("❌ 测试2失败: 格式化文本")
        }
        
        // 测试3: 标题
        if testHeadings() {
            passedTests += 1
            print("✅ 测试3通过: 标题")
        } else {
            failedTests += 1
            print("❌ 测试3失败: 标题")
        }
        
        // 测试4: 段落和对齐
        if testParagraphsAndAlignment() {
            passedTests += 1
            print("✅ 测试4通过: 段落和对齐")
        } else {
            failedTests += 1
            print("❌ 测试4失败: 段落和对齐")
        }
        
        // 测试5: 复杂格式组合
        if testComplexFormatting() {
            passedTests += 1
            print("✅ 测试5通过: 复杂格式组合")
        } else {
            failedTests += 1
            print("❌ 测试5失败: 复杂格式组合")
        }
        
        // 测试6: 分割线
        if testHorizontalRule() {
            passedTests += 1
            print("✅ 测试6通过: 分割线")
        } else {
            failedTests += 1
            print("❌ 测试6失败: 分割线")
        }
        
        // 测试7: 列表
        if testLists() {
            passedTests += 1
            print("✅ 测试7通过: 列表")
        } else {
            failedTests += 1
            print("❌ 测试7失败: 列表")
        }
        
        // 测试8: 背景色
        if testBackgroundColor() {
            passedTests += 1
            print("✅ 测试8通过: 背景色")
        } else {
            failedTests += 1
            print("❌ 测试8失败: 背景色")
        }
        
        // 测试9: 混合内容
        if testMixedContent() {
            passedTests += 1
            print("✅ 测试9通过: 混合内容")
        } else {
            failedTests += 1
            print("❌ 测试9失败: 混合内容")
        }
        
        // 测试10: 空内容
        if testEmptyContent() {
            passedTests += 1
            print("✅ 测试10通过: 空内容")
        } else {
            failedTests += 1
            print("❌ 测试10失败: 空内容")
        }
        
        print("🧪 [XMLReversibilityTest] ========== 测试完成 ==========")
        print("🧪 [XMLReversibilityTest] 通过: \(passedTests), 失败: \(failedTests)")
        
        if failedTests == 0 {
            print("🎉 [XMLReversibilityTest] 所有测试通过！XML转换完全可逆。")
        } else {
            print("⚠️ [XMLReversibilityTest] 有 \(failedTests) 个测试失败，需要修复转换逻辑。")
        }
    }
    
    // MARK: - 单个测试方法
    
    /// 测试1: 简单文本
    private static func testSimpleText() -> Bool {
        let xml = "<new-format/><text indent=\"1\">这是简单文本</text>"
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试2: 格式化文本（加粗、斜体）
    private static func testFormattedText() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1">这是<b>加粗</b>文本</text>
        <text indent="1">这是<i>斜体</i>文本</text>
        <text indent="1">这是<b><i>加粗斜体</i></b>文本</text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试3: 标题
    private static func testHeadings() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1"><size>一级标题</size></text>
        <text indent="1"><mid-size>二级标题</mid-size></text>
        <text indent="1"><h3-size>三级标题</h3-size></text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试4: 段落和对齐
    private static func testParagraphsAndAlignment() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1">左对齐段落</text>
        <text indent="1"><center>居中段落</center></text>
        <text indent="1"><right>右对齐段落</right></text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试5: 复杂格式组合
    private static func testComplexFormatting() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1"><size><b><i>加粗斜体标题</i></b></size></text>
        <text indent="1"><b>加粗</b>和<i>斜体</i>和<u>下划线</u>和<delete>删除线</delete></text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试6: 分割线
    private static func testHorizontalRule() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1">段落1</text>
        <hr />
        <text indent="1">段落2</text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试7: 列表
    private static func testLists() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1"><bullet indent="1" />无序列表项1</text>
        <text indent="1"><bullet indent="1" />无序列表项2</text>
        <text indent="1"><order indent="1" inputNumber="0" />有序列表项1</text>
        <text indent="1"><order indent="1" inputNumber="1" />有序列表项2</text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试8: 背景色
    private static func testBackgroundColor() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1"><background color="#9affe8af">高亮文本</background></text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试9: 混合内容
    private static func testMixedContent() -> Bool {
        let xml = """
        <new-format/>
        <text indent="1"><size>标题</size></text>
        <text indent="1">普通段落，包含<b>加粗</b>和<i>斜体</i>文本。</text>
        <text indent="1"><center>居中段落</center></text>
        <hr />
        <text indent="1"><bullet indent="1" />列表项</text>
        """
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    /// 测试10: 空内容
    private static func testEmptyContent() -> Bool {
        let xml = "<new-format/><text indent=\"1\"></text>"
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        return result.success
    }
    
    // MARK: - 辅助方法
    
    /// 验证往返转换
    /// 
    /// 执行XML -> AttributedString -> XML的转换，并验证结果
    private static func verifyRoundTrip(_ xml: String) -> Bool {
        let result = XMLConversionTester.testRoundTripConversion(originalXML: xml)
        if !result.success {
            print("❌ 往返转换失败:")
            print("   原始XML: \(xml.prefix(100))")
            print("   转换后XML: \(result.convertedXML.prefix(100))")
            for diff in result.differences {
                print("   差异: \(diff)")
            }
        }
        return result.success
    }
}




