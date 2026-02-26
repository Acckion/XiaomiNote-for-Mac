//
//  SyncCommands.swift
//  MiNoteLibrary
//

#if os(macOS)

    /// 全量同步命令
    struct SyncCommand: AppCommand {
        func execute(with context: CommandContext) {
            context.coordinator.syncState.requestFullSync(mode: .normal)
        }
    }

    /// 增量同步命令
    struct IncrementalSyncCommand: AppCommand {
        func execute(with context: CommandContext) {
            context.coordinator.syncState.requestSync(mode: .incremental)
        }
    }
#endif
