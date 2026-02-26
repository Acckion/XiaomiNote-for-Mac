//
//  SyncCommands.swift
//  MiNoteLibrary
//

#if os(macOS)

    /// 全量同步命令
    struct SyncCommand: AppCommand {
        init() {}

        func execute(with context: CommandContext) {
            context.coordinator.syncState.requestFullSync(mode: .normal)
        }
    }

    /// 增量同步命令
    struct IncrementalSyncCommand: AppCommand {
        init() {}

        func execute(with context: CommandContext) {
            context.coordinator.syncState.requestSync(mode: .incremental)
        }
    }
#endif
