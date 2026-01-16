//
//  XMLGeneratorImageFormatTests.swift
//  MiNoteMac
//
//  测试 XMLGenerator 生成新格式图片 XML
//

import Testing
@testable import MiNoteMac

@Suite("XMLGenerator 图片格式生成测试")
struct XMLGeneratorImageFormatTests {
    
    // MARK: - 新格式生成测试
    
    @Test("生成包含描述的新格式图片")
    func testGenerateNewFormat_WithDescription() async throws {
        let node = ImageNode(
            fileId: "1315204657.test",
            description: "我的照片"
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("fileid=\"1315204657.test\""))
        #expect(xml.contains("imgshow=\"0\""))
        #expect(xml.contains("imgdes=\"我的照片\""))
    }
    
    @Test("生成空描述的新格式图片")
    func testGenerateNewFormat_EmptyDescription() async throws {
        let node = ImageNode(
            fileId: "1315204657.test",
            description: ""
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("fileid=\"1315204657.test\""))
        #expect(xml.contains("imgshow=\"0\""))
        #expect(xml.contains("imgdes=\"\""))
    }
    
    @Test("生成 nil 描述的新格式图片")
    func testGenerateNewFormat_NilDescription() async throws {
        let node = ImageNode(
            fileId: "1315204657.test",
            description: nil
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("fileid=\"1315204657.test\""))
        #expect(xml.contains("imgshow=\"0\""))
        #expect(xml.contains("imgdes=\"\""))
    }
    
    @Test("生成包含特殊字符的描述")
    func testGenerateNewFormat_SpecialCharacters() async throws {
        let node = ImageNode(
            fileId: "1315204657.test",
            description: "图片 <测试> & \"引号\""
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("fileid=\"1315204657.test\""))
        #expect(xml.contains("imgshow=\"0\""))
        // 验证特殊字符被正确编码
        #expect(xml.contains("&lt;"))
        #expect(xml.contains("&gt;"))
        #expect(xml.contains("&amp;"))
        #expect(xml.contains("&quot;"))
    }
    
    @Test("验证始终包含 imgshow=\"0\"")
    func testGenerateNewFormat_AlwaysIncludesImgshow() async throws {
        let node = ImageNode(
            fileId: "1315204657.test",
            description: "测试"
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("imgshow=\"0\""))
    }
    
    // MARK: - 向后兼容性测试
    
    @Test("生成 src 格式图片（向后兼容）")
    func testGenerateOldFormat_SrcAttribute() async throws {
        let node = ImageNode(
            src: "https://example.com/image.jpg"
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("src=\"https://example.com/image.jpg\""))
        // src 格式不应该包含新格式属性
        #expect(!xml.contains("imgshow"))
        #expect(!xml.contains("imgdes"))
    }
    
    @Test("生成包含尺寸信息的图片")
    func testGenerateNewFormat_WithDimensions() async throws {
        let node = ImageNode(
            fileId: "1315204657.test",
            width: 800,
            height: 600,
            description: "测试图片"
        )
        let document = DocumentNode(blocks: [node])
        let generator = XMLGenerator()
        let xml = generator.generate(document)
        
        #expect(xml.contains("fileid=\"1315204657.test\""))
        #expect(xml.contains("imgshow=\"0\""))
        #expect(xml.contains("imgdes=\"测试图片\""))
        #expect(xml.contains("width=\"800\""))
        #expect(xml.contains("height=\"600\""))
    }
}
