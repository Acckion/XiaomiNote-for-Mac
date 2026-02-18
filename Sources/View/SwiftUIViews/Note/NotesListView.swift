import AppKit
import SwiftUI

// MARK: - ListAnimationConfig

/// 列表动画配置
enum ListAnimationConfig {
    /// 列表项移动动画（300ms easeInOut）
    static let moveAnimation: Animation = .easeInOut(duration: 0.3)
}

// MARK: - SectionHeaderPreferenceKey

/// 用于追踪分组头位置的 PreferenceKey
struct SectionHeaderPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - NotePositionPreferenceKey

/// 用于追踪笔记位置的 PreferenceKey
struct NotePositionPreferenceKey: PreferenceKey {
    struct NotePosition: Equatable {
        let noteId: String
        let section: String
        let yPosition: CGFloat
    }

    static let defaultValue: [NotePosition] = []

    static func reduce(value: inout [NotePosition], nextValue: () -> [NotePosition]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - NoteDisplayProperties

/// 笔记显示属性（用于 Equatable 比较）
///
/// 只包含影响 NoteRow 显示的属性，用于优化视图重建逻辑。
/// 当非显示属性（如 rawData 中的某些字段）变化时，不会触发 NoteRow 重建。
///
/// **包含的显示属性**：
/// - id: 笔记唯一标识符
/// - title: 笔记标题
/// - content: 笔记内容（用于预览文本提取）
/// - updatedAt: 更新时间（用于显示日期和排序）
/// - isStarred: 置顶状态
/// - folderId: 文件夹ID（用于显示文件夹名称）
/// - isLocked: 锁定状态（用于显示锁图标）
/// - imageInfoHash: 图片信息哈希（用于显示缩略图）
///
/// **不包含的非显示属性**：
/// - createdAt: 创建时间（不在列表中显示）
/// - tags: 标签（不在列表行中显示）
/// - rawData 中的其他字段（如 extraInfo、setting 中的非图片数据等）
///
/// _Requirements: 5.3, 5.4_
struct NoteDisplayProperties: Equatable, Hashable {
    let id: String
    let title: String
    let contentPreview: String // 预览文本，而非完整内容
    let updatedAt: Date
    let isStarred: Bool
    let folderId: String
    let isLocked: Bool
    let imageInfoHash: String

    /// 从 Note 对象创建显示属性
    /// - Parameter note: 笔记对象
    init(from note: Note) {
        id = note.id
        title = note.title
        contentPreview = NoteDisplayProperties.extractPreviewText(from: note.content)
        updatedAt = note.updatedAt
        isStarred = note.isStarred
        folderId = note.folderId
        isLocked = note.rawData?["isLocked"] as? Bool ?? false
        imageInfoHash = NoteDisplayProperties.getImageInfoHash(from: note)
    }

    /// 从 XML 内容中提取预览文本
    /// - Parameter xmlContent: XML 格式的笔记内容
    /// - Returns: 纯文本预览（最多50个字符）
    private static func extractPreviewText(from xmlContent: String) -> String {
        guard !xmlContent.isEmpty else {
            return ""
        }

        // 先移除旧版图片格式（☺ fileId<...>）
        var text = xmlContent
        let legacyImagePattern = "☺\\s*[^<]+<[^>]*>"
        text = text.replacingOccurrences(of: legacyImagePattern, with: "[图片]", options: .regularExpression)

        // 移除 XML 标签，提取纯文本
        text = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 限制长度
        let maxLength = 50
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "..."
        }

        return text
    }

    /// 获取图片信息的哈希值
    /// - Parameter note: 笔记对象
    /// - Returns: 图片信息哈希字符串
    private static func getImageInfoHash(from note: Note) -> String {
        guard let rawData = note.rawData,
              let setting = rawData["setting"] as? [String: Any],
              let settingData = setting["data"] as? [[String: Any]]
        else {
            return "no_images"
        }

        // 提取所有图片信息并生成哈希
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

        // 排序以确保一致的哈希
        return imageInfos.sorted().joined(separator: "|")
    }
}

// MARK: - PinnedNoteRowContent

/// 固定分组标题列表中的笔记行内容视图
///
/// 这是一个独立的子视图，用于正确追踪 `selectedNote` 的变化。
/// 通过将选择状态逻辑封装在独立视图中，确保 SwiftUI 能正确检测依赖变化并更新 UI。
///
/// **问题背景**：
/// 在 `LazyVStack` 中，闭包捕获的值可能不会随着 `@Published` 属性的变化而更新，
/// 导致选择状态（高亮）显示不正确。
///
/// **解决方案**：
/// 使用独立的 `@ObservedObject` 视图来观察 `viewModel`，确保当 `selectedNote` 变化时，
/// 视图能正确重新计算 `isSelected` 并更新高亮状态。
///
/// _Requirements: 2.1, 2.2, 2.3_
struct PinnedNoteRowContent<ContextMenu: View>: View {
    let note: Note
    let showDivider: Bool
    @ObservedObject var viewModel: NotesViewModel
    @ObservedObject var windowState: WindowState
    @Binding var isSelectingNote: Bool
    let contextMenuBuilder: () -> ContextMenu

    /// 计算当前笔记是否被选中
    /// 每次视图重新评估时都会重新计算
    private var isSelected: Bool {
        windowState.selectedNote?.id == note.id
    }

    var body: some View {
        NoteRow(note: note, showDivider: showDivider, viewModel: viewModel)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.65)
                        : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap()
            }
            .contextMenu {
                contextMenuBuilder()
            }
            // 使用 note.id 作为视图标识，确保视图稳定性
            // 选择状态通过 @ObservedObject 自动更新，不需要在 id 中包含 isSelected
            .id(note.id)
    }

    /// 处理点击事件
    private func handleTap() {
        let currentSelectedId = windowState.selectedNote?.id
        Swift
            .print(
                "[PinnedNoteRowContent] 点击笔记 - ID: \(note.id.prefix(8))..., 当前选中: \(currentSelectedId?.prefix(8) ?? "nil"), isSelected: \(isSelected)"
            )

        // 如果点击的是已选中的笔记，不需要做任何事情
        // _Requirements: 2.3_
        if currentSelectedId == note.id {
            Swift.print("[PinnedNoteRowContent] 点击已选中的笔记，无需操作")
            return
        }

        // 设置选择标志，禁用选择期间的动画
        // _Requirements: 2.1, 2.2, 2.3_
        isSelectingNote = true
        windowState.selectNote(note)
        Swift.print("[PinnedNoteRowContent] 设置 selectedNote 为 \(note.id.prefix(8))...")

        // 延迟重置选择标志，确保动画禁用生效
        // 延长到 1.5 秒以覆盖 ensureNoteHasFullContent 等异步操作
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isSelectingNote = false
        }
    }
}

// MARK: - NotesListView

struct NotesListView: View {
    /// 应用协调器（共享数据层）
    let coordinator: AppCoordinator

    /// 窗口状态（窗口独立状态）
    @ObservedObject var windowState: WindowState

    /// 笔记视图模型（通过 coordinator 访问）
    /// 使用 @ObservedObject 确保 SwiftUI 能够追踪 filteredNotes 的变化
    @ObservedObject private var viewModel: NotesViewModel

    /// 初始化方法
    /// - Parameters:
    ///   - coordinator: 应用协调器
    ///   - windowState: 窗口状态
    ///   - optionsManager: 视图选项管理器（可选）
    init(
        coordinator: AppCoordinator,
        windowState: WindowState,
        optionsManager: ViewOptionsManager = .shared
    ) {
        self.coordinator = coordinator
        self.windowState = windowState
        _viewModel = ObservedObject(wrappedValue: coordinator.notesViewModel)
        _optionsManager = ObservedObject(wrappedValue: optionsManager)
    }

    /// 视图选项管理器，用于控制日期分组开关
    /// _Requirements: 3.3, 3.4_
    @ObservedObject var optionsManager: ViewOptionsManager = .shared
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?
    @State private var showingMoveNoteSheet = false
    @State private var noteToMove: Note?
    /// 列表标识符，用于在文件夹切换时强制重建列表（避免动画）
    @State private var listId = UUID()
    /// 是否正在进行选择操作，用于禁用选择期间的动画
    /// _Requirements: 2.1, 2.2, 2.3_
    @State private var isSelectingNote = false
    /// 当前可见的分组标题（用于粘性分组头显示）
    @State private var currentVisibleSection: String?

    var body: some View {
        Group {
            // 检查是否是私密笔记文件夹且未解锁
            if let folder = viewModel.selectedFolder, folder.id == "2", !viewModel.isPrivateNotesUnlocked {
                // 私密笔记未解锁，显示锁定状态
                List {
                    ContentUnavailableView(
                        "此笔记已锁定",
                        systemImage: "lock.fill",
                        description: Text("使用触控 ID 或输入密码查看此笔记")
                    )
                }
                .listStyle(.sidebar)
            } else if viewModel.filteredNotes.isEmpty {
                List {
                    emptyNotesView
                }
                .listStyle(.sidebar)
            } else if optionsManager.isDateGroupingEnabled {
                // 分组模式：使用 ScrollView + LazyVStack 实现固定分组标题
                // _Requirements: 3.3, 固定分组标题_
                pinnedHeadersListContent
            } else {
                // 平铺模式：使用标准 List
                standardListContent
            }
        }
        .scrollContentBackground(.hidden) // 隐藏默认的滚动内容背景
        .background(Color(NSColor.windowBackgroundColor)) // 设置不透明背景色
        // 使用 id 修饰符，在文件夹切换时强制重建列表（避免动画）
        .id(listId)
        // 监听 filteredNotes 变化，触发列表移动动画
        // 只有在非选择操作时才触发动画，避免选择笔记时的错误移动
        // _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3_
        .animation(isSelectingNote ? nil : ListAnimationConfig.moveAnimation, value: viewModel.filteredNotes.map(\.id))
        // 监听日期分组状态变化，触发过渡动画
        // _Requirements: 3.7_
        .animation(.easeInOut(duration: 0.3), value: optionsManager.isDateGroupingEnabled)
        // 监听文件夹切换，更新 listId 强制重建列表
        .onChange(of: viewModel.selectedFolder?.id) { _, _ in
            // 文件夹切换时，更新 listId 强制重建列表，避免动画
            listId = UUID()
            // 重置当前可见分组
            currentVisibleSection = nil
        }
        .alert("删除笔记", isPresented: $showingDeleteAlert, presenting: noteToDelete) { note in
            deleteAlertButtons(for: note)
        } message: { note in
            deleteAlertMessage(for: note)
        }
        .sheet(isPresented: $showingMoveNoteSheet) {
            if let note = noteToMove {
                moveNoteSheetView(for: note)
            }
        }
        // 监听笔记选择变化，通过 coordinator 进行状态管理
        // - 1.1: 编辑笔记内容时保持选中状态不变
        // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
        .onChange(of: windowState.selectedNote) { oldValue, newValue in
            // 添加日志追踪选择状态变化
            let oldId = oldValue?.id.prefix(8) ?? "nil"
            let newId = newValue?.id.prefix(8) ?? "nil"
            Swift.print("[NotesListView] 📊 selectedNote 变化: \(oldId) -> \(newId)")

            // 只有当选择真正变化时才通知 coordinator
            if oldValue?.id != newValue?.id {
                Swift.print("[NotesListView] 🔄 选择 ID 变化，通知 coordinator")
                Task {
                    await viewModel.stateCoordinator.selectNote(newValue)
                }
            } else {
                Swift.print("[NotesListView] ⏭️ 选择 ID 未变化，跳过 coordinator 通知")
            }
        }
    }

    // MARK: - 固定分组标题的列表内容

    /// 使用 ScrollView + safeAreaInset 实现固定分组标题
    /// 当开启日期分组时使用此视图，分组标题会固定在顶部
    private var pinnedHeadersListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let groupedNotes = groupNotesByDate(viewModel.filteredNotes)

                // 定义分组显示顺序
                let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]

                // 确定第一个实际存在的分组（用于隐藏）
                let allSections = sectionOrder.filter {
                    guard let notes = groupedNotes[$0] else { return false }
                    return !notes.isEmpty
                }
                let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
                let firstSection = allSections.first ?? yearGroups.keys.sorted(by: >).first

                // 先显示固定顺序的分组
                ForEach(sectionOrder, id: \.self) { sectionKey in
                    if let notes = groupedNotes[sectionKey], !notes.isEmpty {
                        // 分组头（非粘性，随内容滚动）
                        // 使用 GeometryReader 追踪分组头的位置
                        // 第一个分组头需要隐藏，避免与粘性头重复显示
                        GeometryReader { geometry in
                            LiquidGlassSectionHeader(title: sectionKey)
                                .opacity(sectionKey == firstSection ? 0 : 1) // 隐藏第一个分组头
                                .preference(
                                    key: SectionHeaderPreferenceKey.self,
                                    value: [sectionKey: geometry.frame(in: .global).minY]
                                )
                        }
                        .frame(height: sectionKey == firstSection ? 1 : 44) // 第一个分组头高度为1（避免空白），其他为44

                        // 笔记列表
                        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                            GeometryReader { geometry in
                                pinnedNoteRow(note: note, showDivider: index < notes.count - 1)
                                    .preference(
                                        key: NotePositionPreferenceKey.self,
                                        value: [NotePositionPreferenceKey.NotePosition(
                                            noteId: note.id,
                                            section: sectionKey,
                                            yPosition: geometry.frame(in: .global).minY
                                        )]
                                    )
                            }
                            .frame(height: 70) // 笔记行的固定高度（根据实际情况调整）
                        }
                    }
                }

                // 然后按年份分组其他笔记（降序排列）
                ForEach(yearGroups.keys.sorted(by: >), id: \.self) { year in
                    if let notes = yearGroups[year], !notes.isEmpty {
                        // 分组头（非粘性，随内容滚动）
                        // 使用 GeometryReader 追踪分组头的位置
                        // 第一个分组头需要隐藏，避免与粘性头重复显示
                        GeometryReader { geometry in
                            LiquidGlassSectionHeader(title: year)
                                .opacity(year == firstSection ? 0 : 1) // 隐藏第一个分组头
                                .preference(
                                    key: SectionHeaderPreferenceKey.self,
                                    value: [year: geometry.frame(in: .global).minY]
                                )
                        }
                        .frame(height: year == firstSection ? 1 : 44) // 第一个分组头高度为1（避免空白），其他为44

                        // 笔记列表
                        ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                            GeometryReader { geometry in
                                pinnedNoteRow(note: note, showDivider: index < notes.count - 1)
                                    .preference(
                                        key: NotePositionPreferenceKey.self,
                                        value: [NotePositionPreferenceKey.NotePosition(
                                            noteId: note.id,
                                            section: year,
                                            yPosition: geometry.frame(in: .global).minY
                                        )]
                                    )
                            }
                            .frame(height: 70) // 笔记行的固定高度（根据实际情况调整）
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onPreferenceChange(SectionHeaderPreferenceKey.self) { _ in
            // 不再使用这个回调，改为使用笔记位置来判断
        }
        .onPreferenceChange(NotePositionPreferenceKey.self) { notePositions in
            // 根据笔记位置更新当前可见的分组
            updateCurrentVisibleSection(notePositions: notePositions)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // 粘性分组头（固定在顶部）
            // 始终显示，用于覆盖第一个分组头，避免重复显示
            if let currentSection = currentVisibleSection {
                LiquidGlassSectionHeader(title: currentSection)
            }
        }
        .onAppear {
            // 初始化时设置第一个分组为当前可见分组
            let groupedNotes = groupNotesByDate(viewModel.filteredNotes)
            let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]
            let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
            let allSections = sectionOrder.filter {
                guard let notes = groupedNotes[$0] else { return false }
                return !notes.isEmpty
            } + yearGroups.keys.sorted(by: >)

            if let firstSection = allSections.first {
                currentVisibleSection = firstSection
            }
        }
    }

    /// 根据笔记位置更新当前可见的分组
    /// - Parameter notePositions: 各笔记的位置信息
    private func updateCurrentVisibleSection(notePositions: [NotePositionPreferenceKey.NotePosition]) {

        // 定义分组显示顺序
        let groupedNotes = groupNotesByDate(viewModel.filteredNotes)
        let sectionOrder = ["置顶", "今天", "昨天", "本周", "本月", "本年"]
        let yearGroups = groupedNotes.filter { !sectionOrder.contains($0.key) }
        let allSections = sectionOrder.filter {
            guard let notes = groupedNotes[$0] else { return false }
            return !notes.isEmpty
        } + yearGroups.keys.sorted(by: >)

        // 找到第一个在工具栏下方可见的笔记（Y >= 0）
        let visibleNotes = notePositions
            .filter { $0.yPosition >= 0 }
            .sorted { $0.yPosition < $1.yPosition } // 按 Y 坐标升序排列

        if let firstVisibleNote = visibleNotes.first {
            // 找到第一个可见笔记所属的分组
            let targetSection = firstVisibleNote.section

            // 更新粘性头显示该分组
            if currentVisibleSection != targetSection {
                currentVisibleSection = targetSection
            }
        } else {
            // 没有可见的笔记，说明所有笔记都滚动过去了
            // 显示最后一个分组
            if let lastSection = allSections.last {
                if currentVisibleSection != lastSection {
                    currentVisibleSection = lastSection
                }
            } else {
                // 没有任何分组，显示第一个分组（边界情况）
                if let firstSection = allSections.first {
                    if currentVisibleSection != firstSection {
                        currentVisibleSection = firstSection
                    }
                }
            }
        }
    }

    // 固定分组标题的笔记行

    private func pinnedNoteRow(note: Note, showDivider: Bool) -> some View {
        // 使用独立的子视图来处理选择状态，确保 SwiftUI 能正确追踪依赖
        PinnedNoteRowContent(
            note: note,
            showDivider: showDivider,
            viewModel: viewModel,
            windowState: windowState,
            isSelectingNote: $isSelectingNote,
            contextMenuBuilder: { noteContextMenu(for: note) }
        )
    }

    // MARK: - 标准列表内容（平铺模式）

    /// 标准 List 视图，用于平铺模式（不分组）
    private var standardListContent: some View {
        List(selection: Binding(
            get: { windowState.selectedNote },
            set: { newValue in
                // 设置选择标志，禁用选择期间的动画
                isSelectingNote = true
                if let note = newValue {
                    windowState.selectNote(note)
                }
                // 延迟重置选择标志，确保动画禁用生效
                // 延长到 1.5 秒以覆盖 ensureNoteHasFullContent 等异步操作
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isSelectingNote = false
                }
            }
        )) {
            flatNotesContent
        }
        .listStyle(.sidebar)
    }

    private var emptyNotesView: some View {
        ContentUnavailableView(
            "没有笔记",
            systemImage: "note.text",
            description: Text(viewModel.searchText.isEmpty ? "点击 + 创建新笔记" : "尝试其他搜索词")
        )
    }

    /// 平铺显示的笔记内容（不带分组头）
    /// _Requirements: 3.4_
    private var flatNotesContent: some View {
        ForEach(Array(viewModel.filteredNotes.enumerated()), id: \.element.id) { index, note in
            NoteRow(note: note, showDivider: index < viewModel.filteredNotes.count - 1, viewModel: viewModel)
                .tag(note)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActions(for: note)
                }
                .contextMenu {
                    noteContextMenu(for: note)
                }
        }
    }

    private func groupNotesByDate(_ notes: [Note]) -> [String: [Note]] {
        var grouped: [String: [Note]] = [:]
        let calendar = Calendar.current
        let now = Date()

        // 根据排序方式决定使用哪个日期字段
        let useCreateDate = optionsManager.sortOrder == .createDate

        // 先分离置顶笔记
        let pinnedNotes = notes.filter(\.isStarred)
        let unpinnedNotes = notes.filter { !$0.isStarred }

        // 处理置顶笔记
        if !pinnedNotes.isEmpty {
            // 置顶笔记也按选定的日期字段排序（使用稳定排序）
            grouped["置顶"] = pinnedNotes.sorted {
                let date1 = useCreateDate ? $0.createdAt : $0.updatedAt
                let date2 = useCreateDate ? $1.createdAt : $1.updatedAt
                if date1 == date2 {
                    return $0.id > $1.id // 降序排列时，id 也降序
                }
                return date1 > date2
            }
        }

        // 处理非置顶笔记
        for note in unpinnedNotes {
            // 根据排序方式选择日期字段
            let date = useCreateDate ? note.createdAt : note.updatedAt
            let key: String

            if calendar.isDateInToday(date) {
                key = "今天"
            } else if calendar.isDateInYesterday(date) {
                key = "昨天"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                // 本周（但不包括今天和昨天）
                key = "本周"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                // 本月（但不包括本周）
                key = "本月"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                // 本年（但不包括本月）
                key = "本年"
            } else {
                // 其他年份
                let year = calendar.component(.year, from: date)
                key = "\(year)年"
            }

            if grouped[key] == nil {
                grouped[key] = []
            }
            grouped[key]?.append(note)
        }

        // 对每个分组内的笔记按选定的日期字段降序排序（使用稳定排序）
        for key in grouped.keys {
            grouped[key] = grouped[key]?.sorted {
                let date1 = useCreateDate ? $0.createdAt : $0.updatedAt
                let date2 = useCreateDate ? $1.createdAt : $1.updatedAt
                if date1 == date2 {
                    return $0.id > $1.id // 降序排列时，id 也降序
                }
                return date1 > date2
            }
        }

        return grouped
    }

    private func swipeActions(for note: Note) -> some View {
        Group {
            Button(role: .destructive) {
                noteToDelete = note
                showingDeleteAlert = true
            } label: {
                Label("删除", systemImage: "trash")
            }

            Button {
                viewModel.toggleStar(note)
            } label: {
                Label(
                    note.isStarred ? "取消置顶" : "置顶笔记",
                    systemImage: note.isStarred ? "pin.slash" : "pin"
                )
            }
        }
    }

    private func deleteAlertButtons(for note: Note) -> some View {
        Group {
            Button("取消", role: .cancel) {
                noteToDelete = nil
            }
            Button("删除", role: .destructive) {
                viewModel.deleteNote(note)
                noteToDelete = nil
            }
        }
    }

    private func deleteAlertMessage(for note: Note) -> Text {
        Text("确定要删除 \"\(note.title)\" 吗？此操作无法撤销。")
    }

    private var loadingOverlay: some View {
        ProgressView()
            .scaleEffect(1.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.1))
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func noteContextMenu(for note: Note) -> some View {
        // 在新窗口打开笔记
        Button {
            openNoteInNewWindow(note)
        } label: {
            Label("在新窗口打开笔记", systemImage: "square.on.square")
        }

        Divider()

        // 置顶笔记
        Button {
            viewModel.toggleStar(note)
        } label: {
            Label(
                note.isStarred ? "取消置顶笔记" : "置顶笔记",
                systemImage: note.isStarred ? "pin.slash" : "pin"
            )
        }

        // 移动笔记（使用菜单）
        Menu("移到") {
            // 未分类文件夹（folderId为"0"）
            Button {
                NoteMoveHelper.moveToUncategorized(note, using: viewModel) { result in
                    switch result {
                    case .success:
                        print("[NotesListView] 笔记移动到未分类成功: \(note.id)")
                    case let .failure(error):
                        print("[NotesListView] 移动到未分类失败: \(error.localizedDescription)")
                    }
                }
            } label: {
                Label("未分类", systemImage: "folder.badge.questionmark")
            }

            // 其他可用文件夹
            let availableFolders = NoteMoveHelper.getAvailableFolders(for: viewModel)

            if !availableFolders.isEmpty {
                Divider()

                ForEach(availableFolders, id: \.id) { folder in
                    Button {
                        moveNoteToFolder(note: note, folder: folder)
                    } label: {
                        Label(folder.name, systemImage: folder.isPinned ? "pin.fill" : "folder")
                    }
                }
            }
        }

        Divider()

        // 删除笔记
        Button(role: .destructive) {
            noteToDelete = note
            showingDeleteAlert = true
        } label: {
            Label("删除笔记", systemImage: "trash")
        }

        // 复制笔记
        Button {
            copyNote(note)
        } label: {
            Label("复制笔记", systemImage: "doc.on.doc")
        }

        // 新建笔记
        Button {
            viewModel.createNewNote()
        } label: {
            Label("新建笔记", systemImage: "square.and.pencil")
        }

        Divider()

        // 共享笔记
        Button {
            shareNote(note)
        } label: {
            Label("共享笔记", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: - 菜单操作

    private func openNoteInNewWindow(_: Note) {
        // 在新窗口打开笔记
        // TODO: 实现多窗口支持后启用
        // 当前由于模块依赖问题暂时禁用
        print("[NotesListView] 在新窗口打开笔记功能暂时禁用")

        // 未来实现：通过 coordinator 的回调来创建新窗口
        // coordinator.createNewWindow?(withNote: note)
    }

    private func copyNote(_ note: Note) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // 复制标题和内容
        let content = note.title.isEmpty ? note.content : "\(note.title)\n\n\(note.content)"
        pasteboard.setString(content, forType: .string)
    }

    private func shareNote(_ note: Note) {
        let sharingService = NSSharingServicePicker(items: [
            note.title,
            note.content,
        ])

        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView
        {
            sharingService.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    // MARK: - 移动笔记功能

    private func moveNoteToFolder(note: Note, folder: Folder) {
        NoteMoveHelper.moveNote(note, to: folder, using: viewModel) { result in
            switch result {
            case .success:
                print("[NotesListView] 笔记移动成功: \(note.id) -> \(folder.name)")
            case let .failure(error):
                print("[NotesListView] 移动笔记失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 移动笔记 Sheet

    private func moveNoteSheetView(for note: Note) -> some View {
        MoveNoteSheetView(note: note, viewModel: viewModel)
    }
}

struct NoteRow: View {
    let note: Note
    let showDivider: Bool
    @ObservedObject var viewModel: NotesViewModel
    @ObservedObject var optionsManager: ViewOptionsManager = .shared

    /// 用于比较的显示属性
    /// 只有当这些属性变化时，才会触发视图重建
    /// _Requirements: 5.3, 5.4_
    private var displayProperties: NoteDisplayProperties {
        NoteDisplayProperties(from: note)
    }

    /// 根据排序方式获取要显示的日期
    /// _Requirements: 1.1, 1.2, 1.3_
    private var displayDate: Date {
        switch optionsManager.sortOrder {
        case .createDate:
            note.createdAt
        case .editDate, .title:
            note.updatedAt
        }
    }

    init(note: Note, showDivider: Bool = false, viewModel: NotesViewModel) {
        self.note = note
        self.showDivider = showDivider
        self.viewModel = viewModel
    }

    // MARK: - 同步状态

    /// 笔记是否有待处理上传
    /// _需求: 6.2_
    private var hasPendingUpload: Bool {
        viewModel.hasPendingUpload(for: note.id)
    }

    /// 笔记是否使用临时 ID（离线创建）
    /// _需求: 6.2_
    private var isTemporaryIdNote: Bool {
        viewModel.isTemporaryIdNote(note.id)
    }

    /// 同步状态指示器
    /// 显示"未同步"图标或"离线创建"标记
    /// _需求: 6.2_
    @ViewBuilder
    private var syncStatusIndicator: some View {
        if isTemporaryIdNote {
            // 临时 ID 笔记显示"离线创建"标记
            HStack(spacing: 2) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 10))
                Text("离线")
                    .font(.system(size: 9))
            }
            .foregroundColor(.purple)
            .help("离线创建的笔记，等待上传")
        } else if hasPendingUpload {
            // 有待处理上传显示"未同步"图标
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .help("笔记未同步，等待上传")
        }
    }

    /// 是否应该显示文件夹信息
    ///
    /// 显示场景：
    /// 1. 选中"所有笔记"文件夹（id = "0"）
    /// 2. 选中"置顶"文件夹（id = "starred"）
    /// 3. 有搜索文本或任意搜索筛选条件（搜索结果视图）
    ///
    /// 不显示场景：
    /// - 选中"未分类"文件夹（id = "uncategorized"）
    /// - 选中其他用户文件夹
    private var shouldShowFolderInfo: Bool {
        // 如果选中"未分类"文件夹，不显示文件夹信息
        if let folderId = viewModel.selectedFolder?.id, folderId == "uncategorized" {
            return false
        }

        // 如果选中用户文件夹（非系统文件夹），不显示文件夹信息
        if let folder = viewModel.selectedFolder, !folder.isSystem {
            return false
        }

        // 有搜索文本
        if !viewModel.searchText.isEmpty {
            return true
        }

        // 有任意搜索筛选条件
        if viewModel.searchFilterHasTags ||
            viewModel.searchFilterHasChecklist ||
            viewModel.searchFilterHasImages ||
            viewModel.searchFilterHasAudio ||
            viewModel.searchFilterIsPrivate
        {
            return true
        }

        // 根据当前选中文件夹判断
        guard let folderId = viewModel.selectedFolder?.id else { return false }
        return folderId == "0" || folderId == "starred"
    }

    /// 获取文件夹名称
    private func getFolderName(for folderId: String) -> String {

        // 系统文件夹名称
        if folderId == "0" {
            return "未分类"
        } else if folderId == "starred" {
            return "置顶"
        } else if folderId == "2" {
            return "私密笔记"
        }

        // 用户自定义文件夹
        if let folder = viewModel.folders.first(where: { $0.id == folderId }) {
            return folder.name
        }

        // 找不到时，回退显示 ID（理论上很少出现）
        return folderId
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // 标题（支持搜索高亮）- 加粗显示
                    highlightText(hasRealTitle() ? note.title : "无标题", searchText: viewModel.searchText)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(hasRealTitle() ? .primary : .secondary)

                    HStack(spacing: 4) {
                        // 时间 - 加粗，与标题同色，根据排序方式显示创建时间或修改时间
                        // _Requirements: 1.1, 1.2, 1.3, 1.4_
                        Text(formatDate(displayDate))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)

                        // 预览文本（支持搜索高亮）
                        highlightText(extractPreviewText(from: note.content), searchText: viewModel.searchText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // 文件夹信息（在特定条件下显示）- 调整大小与时间、正文预览一致，行距与其他行保持一致
                    // 始终保留这一行的空间，确保卡片高度一致
                    HStack(spacing: 4) {
                        if shouldShowFolderInfo {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(getFolderName(for: note.folderId))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            // 录音指示器
                            if note.hasAudio {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // 占位符：保持行高一致，但不显示内容
                            Text(" ")
                                .font(.system(size: 11))
                                .foregroundColor(.clear)
                        }
                    }
                    .frame(height: 15) // 固定行高，确保所有卡片高度一致
                }

                Spacer()

                // 图片预览（如果有图片）
                if let attachment = note.imageAttachments.first {
                    NotePreviewImageView(
                        fileId: attachment.fileId,
                        fileType: attachment.fileType,
                        size: 50
                    )
                }

                // 锁图标（如果有）
                if note.rawData?["isLocked"] as? Bool == true {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // 同步状态标记
                // _需求: 6.2_
                syncStatusIndicator
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            // 分割线：放在卡片内容之后，在卡片下方
            if showDivider {
                GeometryReader { geometry in
                    let leadingPadding: CGFloat = 8 // 左侧padding，与文字左对齐
                    let trailingPadding: CGFloat = 8 // 右侧padding，可以调整这个值来控制右侧空白
                    let lineWidth = geometry.size.width - leadingPadding - trailingPadding

                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(height: 0.5)
                        .frame(width: lineWidth, alignment: .leading)
                        .padding(.leading, leadingPadding)
                        // #region agent log
                        .onAppear {
                            let logPath = "/Users/acckion/Desktop/SwiftUI-MiNote-for-Mac/.cursor/debug.log"
                            let logEntry = "{\"location\":\"NotesListView.swift:divider\",\"message\":\"分割线GeometryReader渲染\",\"data\":{\"noteId\":\"\(note.id.prefix(8))\",\"showDivider\":\(showDivider),\"method\":\"geometry_calculated_width\",\"totalWidth\":\(geometry.size.width),\"lineWidth\":\(lineWidth),\"leadingPadding\":\(leadingPadding),\"trailingPadding\":\(trailingPadding),\"hypothesisId\":\"H\"},\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000)),\"sessionId\":\"debug-session\",\"runId\":\"post-fix\"}\n"
                            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                defer { try? fileHandle.close() }
                                try? fileHandle.seekToEnd()
                                try? fileHandle.write(contentsOf: logEntry.data(using: .utf8)!)
                            } else {
                                try? logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
                            }
                        }
                    // #endregion
                }
                .frame(height: 0.5) // GeometryReader 需要明确的高度
            }
        }
        .onHover { hovering in
            if hovering {
                // 延迟100ms后预加载笔记
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    // 如果笔记内容为空，预加载完整内容
                    if note.content.isEmpty {
                        if let fullNote = try? LocalStorageService.shared.loadNote(noteId: note.id) {
                            await MemoryCacheManager.shared.cacheNote(fullNote)
                            Swift.print("[预加载] 悬停预加载完成 - ID: \(note.id.prefix(8))...")
                        }
                    } else {
                        await MemoryCacheManager.shared.cacheNote(note)
                    }
                }
            }
        }
        // 使用笔记 ID 作为视图标识符（而非 displayProperties）
        // 这样编辑笔记内容时不会改变视图标识，选择状态能够保持
        // displayProperties 的变化通过 onChange 监听器处理，不影响视图标识
        // _Requirements: 1.1, 1.2, 5.2_
        // - 1.1: 编辑笔记内容时保持选中状态不变
        // - 1.2: 笔记内容保存触发 notes 数组更新时不重置 selectedNote
        .id(note.id)
        // #region agent log
        .onAppear {
            let logPath = "/Users/acckion/Desktop/SwiftUI-MiNote-for-Mac/.cursor/debug.log"
            let logEntry = "{\"location\":\"NotesListView.swift:body\",\"message\":\"NoteRow渲染\",\"data\":{\"noteId\":\"\(note.id.prefix(8))\",\"showDivider\":\(showDivider),\"verticalPadding\":6,\"layoutMethod\":\"overlay\",\"hypothesisId\":\"B\"},\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000)),\"sessionId\":\"debug-session\",\"runId\":\"initial\"}\n"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                defer { try? fileHandle.close() }
                try? fileHandle.seekToEnd()
                try? fileHandle.write(contentsOf: logEntry.data(using: .utf8)!)
            } else {
                try? logEntry.write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
        // #endregion
    }

    /// 检查笔记是否有真正的标题（不是从内容中提取的）
    /// 判断逻辑：
    /// 1. 如果标题为空，返回 false
    /// 2. 如果标题是"未命名笔记_xxx"格式，返回 false
    /// 3. 检查 rawData 中的 extraInfo 是否有真正的标题
    /// 4. 如果标题与内容的第一行匹配（去除XML标签后），返回 false（处理旧数据）
    /// 5. 否则返回 true（有真正的标题）
    private func hasRealTitle() -> Bool {
        // 如果标题为空，没有真正的标题
        if note.title.isEmpty {
            return false
        }

        // 如果标题是"未命名笔记_xxx"格式，没有真正的标题
        if note.title.hasPrefix("未命名笔记_") {
            return false
        }

        // 检查 rawData 中的 extraInfo 是否有真正的标题
        if let rawData = note.rawData,
           let extraInfo = rawData["extraInfo"] as? String,
           let extraData = extraInfo.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
           let realTitle = extraJson["title"] as? String,
           !realTitle.isEmpty
        {
            // 如果 extraInfo 中有标题，且与当前标题匹配，说明有真正的标题
            if realTitle == note.title {
                return true
            }
        }

        // 检查标题是否与内容的第一行匹配（去除XML标签后）
        // 如果匹配，说明标题可能是从内容中提取的（处理旧数据），没有真正的标题
        if !note.content.isEmpty {
            // 移除XML标签，提取纯文本
            let textContent = note.content
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // 获取第一行
            let firstLine = textContent.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // 如果标题与第一行匹配，说明可能是从内容中提取的（处理旧数据）
            if !firstLine.isEmpty, note.title == firstLine {
                return false
            }
        }

        // 默认情况下，如果标题不为空且不是"未命名笔记_xxx"，认为有真正的标题
        return true
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return "\(year)/\(month)/\(day)"
        }
    }

    /// 高亮显示文本中的搜索关键词
    /// - Parameters:
    ///   - text: 要显示的文本
    ///   - searchText: 搜索关键词
    /// - Returns: 高亮后的 Text 视图
    @ViewBuilder
    private func highlightText(_ text: String, searchText: String) -> some View {
        // 如果搜索文本为空，直接返回普通文本（确保退出搜索时清除高亮）
        if searchText.isEmpty || text.isEmpty {
            Text(text)
        } else {
            // 只有当有搜索文本时才应用高亮
            let attributedString = buildHighlightedAttributedString(text: text, searchText: searchText)
            Text(attributedString)
        }
    }

    /// 构建高亮的 AttributedString
    private func buildHighlightedAttributedString(text: String, searchText: String) -> AttributedString {
        // 使用 NSMutableAttributedString 更可靠
        let nsAttributedString = NSMutableAttributedString(string: text)
        let searchTextLower = searchText.lowercased()
        let textLower = text.lowercased()

        // 使用 NSString 来确保正确的 NSRange 计算（支持多字节字符）
        let nsText = textLower as NSString
        let nsSearchText = searchTextLower as NSString

        var searchLocation = 0

        // 查找所有匹配并应用高亮
        while searchLocation < nsText.length {
            let searchRange = NSRange(location: searchLocation, length: nsText.length - searchLocation)
            let foundRange = nsText.range(of: nsSearchText as String, options: [], range: searchRange)

            if foundRange.location != NSNotFound {
                // 计算在原始字符串中的对应范围（使用原始文本的 NSString）
                let originalNSText = text as NSString
                let originalRange = NSRange(location: foundRange.location, length: foundRange.length)

                // 确保范围有效
                if originalRange.location + originalRange.length <= originalNSText.length {
                    // 应用高亮样式
                    nsAttributedString.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.4), range: originalRange)
                }

                // 继续搜索下一个匹配
                searchLocation = foundRange.location + foundRange.length
            } else {
                break
            }
        }

        // 转换为 AttributedString
        return AttributedString(nsAttributedString)
    }

    /// 将文本分割为高亮和非高亮部分
    private func splitTextWithHighlight(text: String, searchText: String) -> [(text: String, isHighlighted: Bool)] {
        guard !searchText.isEmpty, !text.isEmpty else {
            return [(text: text, isHighlighted: false)]
        }

        var parts: [(text: String, isHighlighted: Bool)] = []
        let searchTextLower = searchText.lowercased()
        let textLower = text.lowercased()

        var currentIndex = text.startIndex

        while let range = textLower.range(of: searchTextLower, range: currentIndex ..< text.endIndex) {
            // 添加高亮前的文本
            if currentIndex < range.lowerBound {
                let beforeText = String(text[currentIndex ..< range.lowerBound])
                parts.append((text: beforeText, isHighlighted: false))
            }

            // 添加高亮的文本（使用原始文本以保持大小写）
            let highlightedText = String(text[range])
            parts.append((text: highlightedText, isHighlighted: true))

            currentIndex = range.upperBound
        }

        // 添加剩余的文本
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex ..< text.endIndex])
            parts.append((text: remainingText, isHighlighted: false))
        }

        return parts.isEmpty ? [(text: text, isHighlighted: false)] : parts
    }

    /// 从 XML 内容中提取预览文本（去除 XML 标签，返回纯文本开头部分）
    private func extractPreviewText(from xmlContent: String) -> String {
        guard !xmlContent.isEmpty else {
            return ""
        }

        // 先移除旧版图片格式（☺ fileId<...>）
        var text = xmlContent
        let legacyImagePattern = "☺\\s*[^<]+<[^>]*>"
        text = text.replacingOccurrences(of: legacyImagePattern, with: "[图片]", options: .regularExpression)

        // 移除 XML 标签，提取纯文本
        text = text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) // 移除所有 XML 标签
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 限制长度（比如前 50 个字符）
        let maxLength = 50
        if text.count > maxLength {
            text = String(text.prefix(maxLength)) + "..."
        }

        return text.isEmpty ? "无内容" : text
    }
}

#Preview {
    // 创建预览用的 AppCoordinator 和 WindowState
    let coordinator = AppCoordinator()
    let windowState = WindowState(coordinator: coordinator)

    return NotesListView(
        coordinator: coordinator,
        windowState: windowState
    )
}
