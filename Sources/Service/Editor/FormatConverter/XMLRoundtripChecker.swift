//
//  XMLRoundtripChecker.swift
//  MiNoteMac
//
//  XML 往返一致性检测器 - 对笔记执行 XML -> NSAttributedString -> XML 往返转换并比较结果

import AppKit
import Foundation

/// 单条笔记的检测结果
struct NoteRoundtripResult: Identifiable {
    let id: String
    let title: String
    let status: ResultStatus
    let originalXML: String?
    let roundtripXML: String?
    let errorMessage: String?

    enum ResultStatus {
        case passed
        case failed
        case error
        case skipped
    }
}

/// 整体检测结果
struct RoundtripCheckResult {
    let totalCount: Int
    let passedCount: Int
    let failedCount: Int
    let skippedCount: Int
    let errorCount: Int
    let failedNotes: [NoteRoundtripResult]
    let duration: TimeInterval
}

/// XML 往返一致性检测器
@MainActor
class XMLRoundtripChecker: ObservableObject {

    @Published var progress: (current: Int, total: Int) = (0, 0)

    private let formatConverter: XiaoMiFormatConverter
    private let xmlNormalizer: XMLNormalizer

    init(formatConverter: XiaoMiFormatConverter, xmlNormalizer: XMLNormalizer) {
        self.formatConverter = formatConverter
        self.xmlNormalizer = xmlNormalizer
    }

    /// 调试用便利构造器，创建独立的转换器实例
    convenience init() {
        let normalizer = XMLNormalizer()
        let converter = XiaoMiFormatConverter(xmlNormalizer: normalizer)
        self.init(formatConverter: converter, xmlNormalizer: normalizer)
    }

    /// 执行往返检测
    func runCheck() async -> RoundtripCheckResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        let notes: [Note]
        do {
            notes = try DatabaseService.shared.getAllNotes()
        } catch {
            LogService.shared.error(.editor, "往返检测：加载笔记失败 - \(error.localizedDescription)")
            return RoundtripCheckResult(
                totalCount: 0, passedCount: 0, failedCount: 0,
                skippedCount: 0, errorCount: 0, failedNotes: [],
                duration: CFAbsoluteTimeGetCurrent() - startTime
            )
        }

        progress = (0, notes.count)
        LogService.shared.info(.editor, "往返检测：开始检测 \(notes.count) 条笔记")

        var passedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var errorCount = 0
        var failedNotes: [NoteRoundtripResult] = []

        let converter = formatConverter
        let normalizer = xmlNormalizer

        for (index, note) in notes.enumerated() {
            progress = (index + 1, notes.count)

            // 空内容跳过
            guard !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                skippedCount += 1
                continue
            }

            do {
                // XML -> NSAttributedString
                let nsAttrStr = try converter.xmlToNSAttributedString(note.content, folderId: note.folderId)

                // NSAttributedString -> XML
                let roundtripXML = try converter.nsAttributedStringToXML(nsAttrStr)

                // 规范化后比较
                let normalizedOriginal = normalizer.normalize(note.content)
                let normalizedRoundtrip = normalizer.normalize(roundtripXML)

                if normalizedOriginal == normalizedRoundtrip {
                    passedCount += 1
                } else {
                    failedCount += 1
                    failedNotes.append(NoteRoundtripResult(
                        id: note.id, title: note.title, status: .failed,
                        originalXML: normalizedOriginal, roundtripXML: normalizedRoundtrip,
                        errorMessage: nil
                    ))
                    LogService.shared.warning(.editor, "往返检测：笔记 \(note.id) 不一致")
                }
            } catch {
                errorCount += 1
                failedNotes.append(NoteRoundtripResult(
                    id: note.id, title: note.title, status: .error,
                    originalXML: nil, roundtripXML: nil,
                    errorMessage: error.localizedDescription
                ))
                LogService.shared.error(.editor, "往返检测：笔记 \(note.id) 转换异常 - \(error.localizedDescription)")
            }

            // 让出主线程，避免阻塞 UI
            if index % 10 == 0 {
                await Task.yield()
            }
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let result = RoundtripCheckResult(
            totalCount: notes.count, passedCount: passedCount,
            failedCount: failedCount, skippedCount: skippedCount,
            errorCount: errorCount, failedNotes: failedNotes,
            duration: duration
        )

        LogService.shared.info(
            .editor,
            "往返检测完成：总计 \(notes.count)，通过 \(passedCount)，失败 \(failedCount)，跳过 \(skippedCount)，异常 \(errorCount)，耗时 \(String(format: "%.2f", duration))s"
        )

        return result
    }
}
