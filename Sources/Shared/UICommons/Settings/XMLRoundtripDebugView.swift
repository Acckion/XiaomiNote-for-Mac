//
//  XMLRoundtripDebugView.swift
//  MiNoteMac
//
//  XML 往返一致性检测调试视图

import AppKit
import SwiftUI

@MainActor
struct XMLRoundtripDebugView: View {
    @StateObject private var checker = XMLRoundtripChecker()
    @State private var result: RoundtripCheckResult?
    @State private var isRunning = false
    @State private var expandedNoteId: String?
    @State private var exportMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // 操作栏
            HStack {
                Button(isRunning ? "检测中..." : "开始检测") {
                    startCheck()
                }
                .disabled(isRunning)

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                    Text("\(checker.progress.current) / \(checker.progress.total)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Spacer()
            }
            .padding()

            Divider()

            if let result {
                // 汇总卡片
                summaryView(result)
                    .padding()

                Divider()

                // 失败笔记列表
                if result.failedNotes.isEmpty {
                    Spacer()
                    Text("所有笔记转换一致")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    failedNotesList(result.failedNotes)
                }
            } else if !isRunning {
                Spacer()
                Text("点击「开始检测」对所有笔记执行 XML 往返一致性检测")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .navigationTitle("XML 往返一致性检测")
        .overlay(alignment: .bottom) {
            if let exportMessage {
                Text(exportMessage)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(6)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        // 3 秒后自动消失
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { self.exportMessage = nil }
                        }
                    }
            }
        }
    }

    private func startCheck() {
        isRunning = true
        result = nil
        Task {
            let checkResult = await checker.runCheck()
            result = checkResult
            isRunning = false
        }
    }

    private func summaryView(_ result: RoundtripCheckResult) -> some View {
        HStack(spacing: 16) {
            summaryItem("总计", count: result.totalCount, color: .primary)
            summaryItem("通过", count: result.passedCount, color: .green)
            summaryItem("失败", count: result.failedCount, color: .red)
            summaryItem("跳过", count: result.skippedCount, color: .secondary)
            summaryItem("异常", count: result.errorCount, color: .orange)

            Spacer()

            if !result.failedNotes.isEmpty {
                Button("导出报告") {
                    exportToDesktop(result)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(String(format: "%.2fs", result.duration))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// 直接导出到桌面，避免文件对话框在设置窗口中卡住
    private func exportToDesktop(_ result: RoundtripCheckResult) {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let fileURL = desktopURL.appendingPathComponent("xml-roundtrip-report-\(timestamp).txt")

        var report = "XML 往返一致性检测报告\n"
        report += "========================\n\n"
        report += "总计: \(result.totalCount)  通过: \(result.passedCount)  "
        report += "失败: \(result.failedCount)  跳过: \(result.skippedCount)  "
        report += "异常: \(result.errorCount)\n"
        report += "耗时: \(String(format: "%.2f", result.duration))s\n\n"

        for note in result.failedNotes {
            report += "----------------------------------------\n"
            report += "笔记: \(note.title.isEmpty ? "无标题" : note.title)\n"
            report += "ID: \(note.id)\n"
            report += "状态: \(note.status == .error ? "异常" : "失败")\n"

            if let errorMessage = note.errorMessage {
                report += "错误: \(errorMessage)\n"
            }
            if let original = note.originalXML {
                report += "\n--- 原始 XML ---\n\(original)\n"
            }
            if let roundtrip = note.roundtripXML {
                report += "\n--- 往返 XML ---\n\(roundtrip)\n"
            }
            report += "\n"
        }

        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            // 在 Finder 中显示导出的文件
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            withAnimation { exportMessage = "报告已导出到桌面" }
            LogService.shared.info(.editor, "往返检测报告已导出: \(fileURL.path)")
        } catch {
            withAnimation { exportMessage = "导出失败: \(error.localizedDescription)" }
            LogService.shared.error(.editor, "往返检测报告导出失败: \(error.localizedDescription)")
        }
    }

    private func summaryItem(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func failedNotesList(_ notes: [NoteRoundtripResult]) -> some View {
        List {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 8) {
                    // 标题行
                    HStack {
                        Image(systemName: note.status == .error ? "exclamationmark.triangle" : "xmark.circle")
                            .foregroundColor(note.status == .error ? .orange : .red)

                        VStack(alignment: .leading) {
                            Text(note.title.isEmpty ? "无标题" : note.title)
                                .fontWeight(.medium)
                            Text("ID: \(note.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(expandedNoteId == note.id ? "收起" : "详情") {
                            withAnimation {
                                expandedNoteId = expandedNoteId == note.id ? nil : note.id
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    // 展开详情
                    if expandedNoteId == note.id {
                        if let errorMessage = note.errorMessage {
                            Text("错误: \(errorMessage)")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }

                        if let original = note.originalXML, let roundtrip = note.roundtripXML {
                            xmlComparisonView(original: original, roundtrip: roundtrip)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }

    private func xmlComparisonView(original: String, roundtrip: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原始 XML (规范化后)")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal) {
                Text(original)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 150)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)

            Text("往返 XML (规范化后)")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal) {
                Text(roundtrip)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 150)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
    }
}
