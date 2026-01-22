import Foundation
import Combine

/// 应用协调器 - 管理所有 ViewModel 的生命周期和通信
@MainActor
final class AppCoordinator: ObservableObject {
    // MARK: - ViewModels
    let noteListViewModel: NoteListViewModel
    let noteEditorViewModel: NoteEditorViewModel
    let syncCoordinator: SyncCoordinator
    let authViewModel: AuthenticationViewModel
    let folderViewModel: FolderViewModel

    // MARK: - Dependencies
    private let container: DIContainer
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(container: DIContainer = .shared) {
        self.container = container

        // 解析依赖
        let noteStorage = container.resolve(NoteStorageProtocol.self)
        let syncService = container.resolve(SyncServiceProtocol.self)
        let authService = container.resolve(AuthenticationServiceProtocol.self)

        // 创建 ViewModels
        self.noteListViewModel = NoteListViewModel(
            noteStorage: noteStorage,
            syncService: syncService
        )

        self.noteEditorViewModel = NoteEditorViewModel(
            noteStorage: noteStorage,
            syncService: syncService
        )

        self.syncCoordinator = SyncCoordinator(
            syncService: syncService
        )

        self.authViewModel = AuthenticationViewModel(
            authService: authService
        )

        self.folderViewModel = FolderViewModel(
            noteStorage: noteStorage
        )

        setupCoordination()
    }

    // MARK: - Setup
    private func setupCoordination() {
        // 当列表中选择笔记时，加载到编辑器
        noteListViewModel.$selectedNoteId
            .compactMap { $0 }
            .sink { [weak self] noteId in
                Task {
                    await self?.noteEditorViewModel.loadNote(id: noteId)
                }
            }
            .store(in: &cancellables)

        // 当编辑器保存笔记时，刷新列表
        noteEditorViewModel.$hasUnsavedChanges
            .filter { !$0 }
            .sink { [weak self] _ in
                Task {
                    await self?.noteListViewModel.loadNotes()
                }
            }
            .store(in: &cancellables)

        // 当认证状态变化时，触发同步
        authViewModel.$isAuthenticated
            .filter { $0 }
            .sink { [weak self] _ in
                Task {
                    try? await self?.syncCoordinator.startSync()
                }
            }
            .store(in: &cancellables)
    }
}
