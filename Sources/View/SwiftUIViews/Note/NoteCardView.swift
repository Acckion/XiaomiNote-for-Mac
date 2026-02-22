//
//  NoteCardView.swift
//  MiNoteMac
//
//  笔记卡片视图 - 画廊视图中的单个笔记预览卡片
//

import AppKit
import SwiftUI

// MARK: - NoteCardView

/// 笔记卡片视图
///
/// 画廊视图中的单个笔记预览卡片，显示笔记的标题、内容预览、日期和缩略图
struct NoteCardView: View {

    // MARK: - 属性

    /// 笔记数据
    let note: Note

    /// 是否选中
    let isSelected: Bool

    /// 点击回调
    let onTap: () -> Void

    /// 视图选项管理器（用于获取排序方式）
    @ObservedObject var optionsManager: ViewOptionsManager = .shared

    // MARK: - 状态

    /// 是否悬停
    @State private var isHovering = false

    /// 缩略图图片
    @State private var thumbnailImage: NSImage?

    /// 当前显示的图片文件ID（用于跟踪变化）
    @State private var currentImageFileId: String?

    // MARK: - 视图

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnailSection
            titleSection
            contentPreviewSection
            Spacer(minLength: 0)
            dateSection
        }
        .padding(12)
        .frame(minWidth: 200, maxWidth: 300)
        .frame(height: 200)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(lockIconOverlay, alignment: .topTrailing)
        .shadow(
            color: isHovering ? Color.black.opacity(0.15) : Color.black.opacity(0.05),
            radius: isHovering ? 8 : 4
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                preloadNoteContent()
            }
        }
        .onTapGesture {
            onTap()
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: noteImageHash) { oldValue, newValue in
            if oldValue != newValue {
                loadThumbnail()
            }
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private var thumbnailSection: some View {
        if let _ = getFirstImageInfo(from: note) {
            Group {
                if let nsImage = thumbnailImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(8)
        }
    }

    private var titleSection: some View {
        Text(hasRealTitle() ? note.title : "无标题")
            .font(.headline)
            .lineLimit(2)
            .foregroundColor(hasRealTitle() ? .primary : .secondary)
    }

    private var contentPreviewSection: some View {
        Text(extractPreviewText(from: note.content))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .lineLimit(hasImageThumbnail ? 2 : 3)
    }

    private var dateSection: some View {
        Text(formatDate(displayDate))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var lockIconOverlay: some View {
        if NoteDisplayProperties.parseIsLocked(from: note) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(6)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .padding(8)
        }
    }

    // MARK: - 辅助属性

    private var displayDate: Date {
        switch optionsManager.sortOrder {
        case .createDate:
            note.createdAt
        case .editDate, .title:
            note.updatedAt
        }
    }

    private var hasImageThumbnail: Bool {
        getFirstImageInfo(from: note) != nil
    }

    private var noteImageHash: String {
        getImageInfoHash(from: note)
    }

    // MARK: - 辅助方法

    private func hasRealTitle() -> Bool {
        if note.title.isEmpty {
            return false
        }

        if note.title.hasPrefix("未命名笔记_") {
            return false
        }

        if let extraInfoJson = note.extraInfoJson,
           let extraData = extraInfoJson.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
           let realTitle = extraJson["title"] as? String,
           !realTitle.isEmpty
        {
            if realTitle == note.title {
                return true
            }
        }

        if !note.content.isEmpty {
            let textContent = note.content
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let firstLine = textContent.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !firstLine.isEmpty, note.title == firstLine {
                return false
            }
        }

        return true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return "\(year)/\(month)/\(day)"
        }
    }

    private func extractPreviewText(from xmlContent: String) -> String {
        guard !xmlContent.isEmpty else {
            return "无内容"
        }

        var text = xmlContent
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let maxLength = 100
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "..."
        }

        return text.isEmpty ? "无内容" : text
    }

    private func getFirstImageInfo(from note: Note) -> (fileId: String, fileType: String)? {
        guard let settingJson = note.settingJson,
              let jsonData = settingJson.data(using: .utf8),
              let setting = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let settingData = setting["data"] as? [[String: Any]]
        else {
            return nil
        }

        for imgData in settingData {
            if let fileId = imgData["fileId"] as? String,
               let mimeType = imgData["mimeType"] as? String,
               mimeType.hasPrefix("image/")
            {
                let fileType = String(mimeType.dropFirst("image/".count))
                return (fileId: fileId, fileType: fileType)
            }
        }

        return nil
    }

    private func getImageInfoHash(from note: Note) -> String {
        guard let settingJson = note.settingJson,
              let jsonData = settingJson.data(using: .utf8),
              let setting = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let settingData = setting["data"] as? [[String: Any]]
        else {
            return "no_images"
        }

        var imageInfos: [String] = []
        for imgData in settingData {
            if let fileId = imgData["fileId"] as? String,
               let mimeType = imgData["mimeType"] as? String,
               mimeType.hasPrefix("image/")
            {
                imageInfos.append("\(fileId):\(mimeType)")
            }
        }

        if imageInfos.isEmpty {
            return "no_images"
        }

        return imageInfos.sorted().joined(separator: "|")
    }

    private func loadThumbnail() {
        guard let imageInfo = getFirstImageInfo(from: note) else {
            thumbnailImage = nil
            currentImageFileId = nil
            return
        }

        if currentImageFileId == imageInfo.fileId, thumbnailImage != nil {
            return
        }

        currentImageFileId = imageInfo.fileId

        Task {
            if let imageData = LocalStorageService.shared.loadImage(fileId: imageInfo.fileId, fileType: imageInfo.fileType),
               let nsImage = NSImage(data: imageData)
            {
                let thumbnail = createThumbnail(from: nsImage, targetHeight: 80)

                await MainActor.run {
                    thumbnailImage = thumbnail
                }
            } else {
                await MainActor.run {
                    thumbnailImage = nil
                }
            }
        }
    }

    private func createThumbnail(from image: NSImage, targetHeight: CGFloat) -> NSImage {
        let imageSize = image.size
        let scale = targetHeight / imageSize.height
        let targetWidth = imageSize.width * scale

        let thumbnailSize = NSSize(width: max(targetWidth, 200), height: targetHeight)
        let thumbnail = NSImage(size: thumbnailSize)

        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSColor.controlBackgroundColor.setFill()
        NSRect(origin: .zero, size: thumbnailSize).fill()

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (thumbnailSize.width - scaledWidth) / 2
        let offsetY = (thumbnailSize.height - scaledHeight) / 2

        image.draw(
            in: NSRect(origin: NSPoint(x: offsetX, y: offsetY), size: NSSize(width: scaledWidth, height: scaledHeight)),
            from: NSRect(origin: .zero, size: imageSize),
            operation: .sourceOver,
            fraction: 1.0
        )

        return thumbnail
    }

    private func preloadNoteContent() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)

            if note.content.isEmpty {
                let cached = await MemoryCacheManager.shared.getNote(noteId: note.id)
                if cached == nil {
                    if let fullNote = try? LocalStorageService.shared.loadNote(noteId: note.id) {
                        await MemoryCacheManager.shared.cacheNote(fullNote)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleNote = Note(
        id: "sample-1",
        title: "示例笔记",
        content: "<new-format/><text indent=\"1\">这是一个示例笔记的内容，用于预览卡片视图的显示效果。</text>",
        folderId: "0",
        isStarred: false,
        createdAt: Date(),
        updatedAt: Date(),
        tags: []
    )

    return NoteCardView(
        note: sampleNote,
        isSelected: false,
        onTap: {}
    )
    .frame(width: 250, height: 200)
    .padding()
}
