//
//  EditorContentManager.swift
//  MiNoteMac
//
//  NativeEditorContext 的内容管理扩展
//  从 NativeEditorContext.swift 提取，负责录音模板操作、内容保护、自动保存、通知
//

import AppKit

// MARK: - 内容管理扩展

public extension NativeEditorContext {

    // MARK: - 录音模板操作

    /// 插入录音模板占位符
    ///
    /// 在原生编辑器中插入 AudioAttachment 作为录音模板占位符
    /// 占位符使用 `temp_[templateId]` 作为 fileId，并设置 `isTemporaryPlaceholder = true`
    /// 导出 XML 时会生成 `<sound fileid="temp_xxx" des="temp"/>` 格式
    ///
    /// - Parameter templateId: 模板唯一标识符
    internal func insertRecordingTemplate(templateId: String) {

        // 创建临时 fileId
        let tempFileId = "temp_\(templateId)"

        // 创建 AudioAttachment 作为占位符
        let audioAttachment = customRenderer.createAudioAttachment(
            fileId: tempFileId,
            digest: nil,
            mimeType: nil
        )
        // 标记为临时占位符
        audioAttachment.isTemporaryPlaceholder = true

        // 创建包含附件的 NSAttributedString
        let attachmentString = NSMutableAttributedString(attachment: audioAttachment)

        // 添加自定义属性标记这是录音模板（用于后续查找和替换）
        let range = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttribute(NSAttributedString.Key("RecordingTemplate"), value: templateId, range: range)

        // 将占位符插入到当前文本的光标位置
        let currentText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
        let insertionPoint = min(cursorPosition, currentText.length)
        currentText.insert(attachmentString, at: insertionPoint)

        // 更新编辑器内容
        updateNSContent(currentText)

        // 更新光标位置到插入附件之后
        updateCursorPosition(insertionPoint + 1)

        hasUnsavedChanges = true

        // 使用版本号机制追踪附件变化
        changeTracker.attachmentDidChange()
        autoSaveManager.scheduleAutoSave()

    }

    /// 更新录音模板为音频附件
    ///
    /// 将临时的录音模板占位符更新为实际的音频附件
    /// 查找带有 `RecordingTemplate` 属性的 AudioAttachment，替换为新的 AudioAttachment
    /// 新附件使用真实的 fileId，且 `isTemporaryPlaceholder = false`
    ///
    /// - Parameters:
    ///   - templateId: 模板唯一标识符
    ///   - fileId: 音频文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    internal func updateRecordingTemplate(templateId: String, fileId: String, digest: String? = nil, mimeType: String? = nil) {

        // 在当前文本中查找对应的录音模板
        let currentText = nsAttributedText.mutableCopy() as! NSMutableAttributedString
        let fullRange = NSRange(location: 0, length: currentText.length)

        var templateFound = false
        var foundRange: NSRange?

        // 遍历文本，查找带有指定 templateId 的录音模板
        currentText.enumerateAttribute(NSAttributedString.Key("RecordingTemplate"), in: fullRange, options: []) { value, range, stop in
            if let templateValue = value as? String, templateValue == templateId {
                foundRange = range
                templateFound = true
                stop.pointee = true
            }
        }

        if templateFound, let range = foundRange {
            // 创建新的 AudioAttachment（非临时）
            let audioAttachment = customRenderer.createAudioAttachment(
                fileId: fileId,
                digest: digest,
                mimeType: mimeType
            )
            // 确保不是临时占位符
            audioAttachment.isTemporaryPlaceholder = false

            // 创建包含附件的 NSAttributedString
            let attachmentString = NSAttributedString(attachment: audioAttachment)

            // 替换模板
            currentText.replaceCharacters(in: range, with: attachmentString)

            // 更新编辑器内容
            updateNSContent(currentText)
            hasUnsavedChanges = true

            // 使用版本号机制追踪附件变化
            changeTracker.attachmentDidChange()
            autoSaveManager.scheduleAutoSave()

        } else {}
    }

    /// 更新录音模板并强制保存
    ///
    /// 更新录音模板为音频附件后立即强制保存，确保内容持久化
    ///
    /// - Parameters:
    ///   - templateId: 模板唯一标识符
    ///   - fileId: 音频文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    internal func updateRecordingTemplateAndSave(templateId: String, fileId: String, digest: String? = nil, mimeType: String? = nil) async throws {

        // 1. 更新录音模板
        updateRecordingTemplate(templateId: templateId, fileId: fileId, digest: digest, mimeType: mimeType)

        // 2. 强制保存内容
        // 原生编辑器的保存通过 contentChangeSubject 触发
        // 发送内容变化信号，确保立即保存
        contentChangeSubject.send(nsAttributedText)

    }

    /// 验证内容持久化
    ///
    /// 验证保存后的内容是否包含预期的音频附件，确保持久化成功
    ///
    /// **修复说明**：
    /// - 使用 XMLNormalizer 对预期内容和当前内容进行规范化
    /// - 规范化后再进行比较，避免因格式差异导致的误判
    /// - 这样可以正确处理图片格式、空格、属性顺序等差异
    ///
    /// - Parameter expectedContent: 预期的内容（包含音频附件的XML）
    /// - Returns: 是否验证成功
    internal func verifyContentPersistence(expectedContent: String) async -> Bool {

        // 导出当前内容为XML格式
        let currentXML = exportToXML()

        // 使用 XMLNormalizer 规范化两边的内容
        let normalizedExpected = xmlNormalizer?.normalize(expectedContent) ?? expectedContent
        let normalizedCurrent = xmlNormalizer?.normalize(currentXML) ?? currentXML

        // 分析预期内容的类型（使用规范化后的内容）
        let expectedIsEmpty = normalizedExpected.isEmpty
        let expectedHasAudio = normalizedExpected.contains("<sound fileid=")
        let expectedHasTemp = normalizedExpected.contains("des=\"temp\"")

        // 分析当前内容的类型（使用规范化后的内容）
        let currentIsEmpty = normalizedCurrent.isEmpty
        let currentHasAudio = normalizedCurrent.contains("<sound fileid=")
        let currentHasTemp = normalizedCurrent.contains("des=\"temp\"")

        // 验证逻辑
        var isValid = false
        var failureReason = ""

        // 情况1：预期内容为空
        if expectedIsEmpty {
            if currentIsEmpty {
                isValid = true
            } else {
                failureReason = "预期为空内容，但当前内容不为空（规范化后长度: \(normalizedCurrent.count)）"
            }
        }
        // 情况2：预期内容包含音频
        else if expectedHasAudio {
            if !currentHasAudio {
                failureReason = "预期包含音频附件，但当前内容不包含音频"
            } else if currentHasTemp {
                failureReason = "当前内容包含临时模板（des=\"temp\"），音频附件未正确持久化"
            } else if normalizedCurrent.isEmpty {
                failureReason = "当前内容长度为0"
            } else {
                isValid = true
            }
        }
        // 情况3：预期内容为普通文本（不包含音频）
        else {
            if !normalizedCurrent.isEmpty {
                isValid = true
            } else {
                failureReason = "预期包含普通文本，但当前内容为空"
            }
        }

        // 输出验证结果摘要
        if !isValid, !failureReason.isEmpty {}

        // 如果验证失败，输出规范化后的内容预览（前200个字符）
        if !isValid {

            let expectedPreviewLength = min(200, normalizedExpected.count)
            if expectedPreviewLength > 0 {
                let expectedPreview = String(normalizedExpected.prefix(expectedPreviewLength))
            } else {}

            let currentPreviewLength = min(200, normalizedCurrent.count)
            if currentPreviewLength > 0 {
                let currentPreview = String(normalizedCurrent.prefix(currentPreviewLength))
            } else {}
        }

        return isValid
    }

    // MARK: - 内容保护方法

    /// 标记内容已保存
    ///
    /// 当内容成功保存后调用此方法，重置 hasUnsavedChanges 状态
    ///
    func markContentSaved() {
        hasUnsavedChanges = false
        // 清除备份内容和错误状态
        clearSaveErrorState()
    }

    /// 备份当前内容
    ///
    /// 在保存操作开始前调用，备份当前编辑内容
    /// 如果保存失败，可以使用备份内容进行恢复或重试
    func backupCurrentContent() {
        backupContent = nsAttributedText.copy() as? NSAttributedString
    }

    /// 标记保存失败
    ///
    /// 当保存操作失败时调用此方法，记录错误信息并保留编辑内容
    ///
    /// - Parameter error: 错误信息
    func markSaveFailed(error: String) {
        lastSaveError = error
        hasPendingRetry = true
        // 确保内容已备份
        if backupContent == nil {
            backupCurrentContent()
        }
    }

    /// 清除保存错误状态
    ///
    /// 当保存成功或用户取消重试时调用
    func clearSaveErrorState() {
        backupContent = nil
        lastSaveError = nil
        hasPendingRetry = false
    }

    /// 获取待保存的内容
    ///
    /// 优先返回备份内容（如果有），否则返回当前内容
    /// 用于重试保存操作
    ///
    /// - Returns: 待保存的 NSAttributedString
    func getContentForRetry() -> NSAttributedString {
        if let backup = backupContent {
            return backup
        }
        return nsAttributedText
    }

    /// 从备份恢复内容
    ///
    /// 如果有备份内容，将其恢复到编辑器
    ///
    /// - Returns: 是否成功恢复
    @discardableResult
    func restoreFromBackup() -> Bool {
        guard let backup = backupContent else {
            return false
        }
        nsAttributedText = backup
        hasUnsavedChanges = true
        return true
    }

    // MARK: - 自动保存方法

    /// 执行自动保存
    ///
    /// 检查是否需要保存，如果需要则导出 XML 并触发保存流程
    /// 此方法会被 AutoSaveManager 调用
    ///
    /// **实现逻辑**：
    /// 1. 检查 needsSave 状态
    /// 2. 记录保存版本号
    /// 3. 导出 XML 内容
    /// 4. 通过 contentChangeSubject 发布内容变化，触发上层保存逻辑
    /// 5. 检测并发编辑（保存期间是否有新编辑）
    internal func performAutoSave() async {
        // 1. 检查是否需要保存
        guard changeTracker.needsSave else {
            return
        }

        // 2. 记录保存的版本号
        let versionToSave = changeTracker.contentVersion
        autoSaveManager.markSaveStarted(version: versionToSave)

        // 3. 导出 XML 内容
        let xmlContent = exportToXML()

        guard !xmlContent.isEmpty else {
            autoSaveManager.markSaveCompleted()
            return
        }

        // 4. 通过 contentChangeSubject 发布内容变化
        contentChangeSubject.send(nsAttributedText)

        // 5. 检测并发编辑
        if changeTracker.hasNewEditsSince(savingVersion: versionToSave) {
            autoSaveManager.scheduleAutoSave()
        }

        // 6. 标记保存完成
        autoSaveManager.markSaveCompleted()
    }

    // MARK: - 通知方法

    /// 通知内容变化
    func notifyContentChange() {
        contentChangeSubject.send(nsAttributedText)
        hasUnsavedChanges = true
    }

    /// 通知标题变化（由 NativeEditorView.Coordinator 调用）
    func notifyTitleChange(_ title: String) {
        titleChangeSubject.send(title)
    }
}
