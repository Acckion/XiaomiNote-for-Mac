//
//  LegacyImageFormatTests.swift
//  MiNoteMac
//
//  旧格式图片解析测试
//  验证旧格式和新格式图片的解析功能
//

import XCTest
@testable import MiNoteLibrary

/// 旧格式图片解析测试
final class LegacyImageFormatTests: XCTestCase {
    
    var parser: MiNoteXMLParser!
    
    override func setUp() {
        super.setUp()
        parser = MiNoteXMLParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    // MARK: - 旧格式解析测试
    
    /// 测试标准旧格式图片解析（带描述）
    func testParseLegacyFormat_WithDescription() throws {
        let xml = "☺ 1315204657.HNpRlTMs5W8A92Ia-FARIw<0/><[我的照片]/>"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.HNpRlTMs5W8A92Ia-FARIw", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "我的照片", "description 应该正确提取")
    }
    
    /// 测试旧格式图片解析（空描述）
    func testParseLegacyFormat_EmptyDescription() throws {
        let xml = "☺ 1315204657.HNpRlTMs5W8A92Ia-FARIw<0/><[]/>"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.HNpRlTMs5W8A92Ia-FARIw", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "", "description 应该为空字符串")
    }
    
    /// 测试旧格式图片解析（包含特殊字符的描述）
    func testParseLegacyFormat_SpecialCharacters() throws {
        let xml = "☺ 1315204657.test<0/><[图片 <测试> & \"引号\"]/>"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.test", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "图片 <测试> & \"引号\"", "特殊字符应该正确保留")
    }
    
    /// 测试旧格式图片解析（缺少描述标记）
    func testParseLegacyFormat_MissingDescriptionMarker() throws {
        let xml = "☺ 1315204657.test<0/>"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.test", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "", "缺少描述标记时 description 应该为空")
    }
    
    // MARK: - 新格式解析测试
    
    /// 测试新格式图片解析（完整属性）
    func testParseNewFormat_Complete() throws {
        let xml = "<img fileid=\"1315204657.test\" imgshow=\"0\" imgdes=\"风景照\" />"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.test", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "风景照", "description 应该正确提取")
    }
    
    /// 测试新格式图片解析（缺少 imgshow 属性）
    func testParseNewFormat_MissingImgshow() throws {
        let xml = "<img fileid=\"1315204657.test\" imgdes=\"照片\" />"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.test", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "照片", "description 应该正确提取")
    }
    
    /// 测试新格式图片解析（空描述）
    func testParseNewFormat_EmptyDescription() throws {
        let xml = "<img fileid=\"1315204657.test\" imgshow=\"0\" imgdes=\"\" />"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.test", "fileId 应该正确提取")
        XCTAssertEqual(imageNode.description, "", "description 应该为空字符串")
    }
    
    /// 测试新格式图片解析（包含未知属性）
    func testParseNewFormat_UnknownAttributes() throws {
        let xml = "<img fileid=\"1315204657.test\" imgshow=\"0\" imgdes=\"\" unknown=\"value\" />"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.fileId, "1315204657.test", "fileId 应该正确提取")
        // 未知属性应该被忽略，不影响解析
    }
    
    // MARK: - 混合格式测试
    
    /// 测试混合格式文档（旧格式 + 新格式）
    func testParseMixedFormats() throws {
        let xml = """
        <text indent="1">文本</text>
        ☺ 1315204657.old<0/><[旧格式]/>
        <img fileid="1315204657.new" imgshow="0" imgdes="新格式" />
        """
        
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 3, "应该解析出三个块级节点")
        
        // 验证第一个节点是文本块
        XCTAssertTrue(document.blocks[0] is TextBlockNode, "第一个节点应该是 TextBlockNode")
        
        // 验证第二个节点是旧格式图片
        guard let oldImage = document.blocks[1] as? ImageNode else {
            XCTFail("第二个节点应该是 ImageNode")
            return
        }
        XCTAssertEqual(oldImage.fileId, "1315204657.old", "旧格式 fileId 应该正确")
        XCTAssertEqual(oldImage.description, "旧格式", "旧格式 description 应该正确")
        
        // 验证第三个节点是新格式图片
        guard let newImage = document.blocks[2] as? ImageNode else {
            XCTFail("第三个节点应该是 ImageNode")
            return
        }
        XCTAssertEqual(newImage.fileId, "1315204657.new", "新格式 fileId 应该正确")
        XCTAssertEqual(newImage.description, "新格式", "新格式 description 应该正确")
    }
    
    // MARK: - 向后兼容性测试
    
    /// 测试现有格式（src 属性）仍然工作
    func testParseExistingFormat_SrcAttribute() throws {
        let xml = "<img src=\"https://example.com/image.jpg\" />"
        let result = try parser.parse(xml)
        let document = result.value
        
        XCTAssertEqual(document.blocks.count, 1, "应该解析出一个块级节点")
        
        guard let imageNode = document.blocks.first as? ImageNode else {
            XCTFail("应该是 ImageNode 类型")
            return
        }
        
        XCTAssertEqual(imageNode.src, "https://example.com/image.jpg", "src 应该正确提取")
        XCTAssertNil(imageNode.fileId, "fileId 应该为 nil")
    }
}
