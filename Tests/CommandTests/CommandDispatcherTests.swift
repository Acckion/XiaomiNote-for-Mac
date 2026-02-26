//
//  CommandDispatcherTests.swift
//  MiNoteLibraryTests
//
//  Command 调度链路回归测试
//  验证 CommandDispatcher 能正确调度命令，调用链不崩溃
//

import XCTest
@testable import MiNoteMac

final class CommandDispatcherTests: XCTestCase {

    // MARK: - 测试 CommandDispatcher 调度 SyncCommand 不崩溃

    @MainActor
    func testDispatchSyncCommand() throws {
        let coordinator = AppCoordinator()
        let dispatcher = try XCTUnwrap(coordinator.commandDispatcher)

        // 调度全量同步命令，验证不崩溃
        dispatcher.dispatch(SyncCommand())
    }

    // MARK: - 测试 CommandDispatcher 调度 IncrementalSyncCommand 不崩溃

    @MainActor
    func testDispatchIncrementalSyncCommand() throws {
        let coordinator = AppCoordinator()
        let dispatcher = try XCTUnwrap(coordinator.commandDispatcher)

        dispatcher.dispatch(IncrementalSyncCommand())
    }

    // MARK: - 测试 CommandDispatcher 调度 CreateNoteCommand 不崩溃

    @MainActor
    func testDispatchCreateNoteCommand() throws {
        let coordinator = AppCoordinator()
        let dispatcher = try XCTUnwrap(coordinator.commandDispatcher)

        let command = CreateNoteCommand()
        dispatcher.dispatch(command)
    }

    // MARK: - 测试 CommandDispatcher 的 coordinator 弱引用释放后不崩溃

    @MainActor
    func testDispatchAfterCoordinatorDeallocated() throws {
        var coordinator: AppCoordinator? = AppCoordinator()
        let dispatcher = try XCTUnwrap(coordinator?.commandDispatcher)

        // 释放 coordinator
        coordinator = nil

        // coordinator 已释放，dispatch 应安全跳过
        dispatcher.dispatch(SyncCommand())
    }

    // MARK: - 测试 CommandContext 正确传递 coordinator

    @MainActor
    func testCommandContextPassesCoordinator() {
        let coordinator = AppCoordinator()
        let context = CommandContext(coordinator: coordinator)

        XCTAssertTrue(context.coordinator === coordinator)
    }
}
