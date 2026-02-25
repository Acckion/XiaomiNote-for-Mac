//
//  AssemblerSmokeTests.swift
//  MiNoteLibraryTests
//
//  组合根冒烟测试
//  验证 AppCoordinatorAssembler.buildDependencies() 产出的关键服务均非 nil
//

import XCTest
@testable import MiNoteMac

final class AssemblerSmokeTests: XCTestCase {

    @MainActor
    func testBuildDependencies_allKeyServicesNonNil() {
        let deps = AppCoordinatorAssembler.buildDependencies()

        // 核心基础设施
        XCTAssertNotNil(deps.eventBus)
        XCTAssertNotNil(deps.noteStore)
        XCTAssertNotNil(deps.syncEngine)

        // State 对象
        XCTAssertNotNil(deps.noteListState)
        XCTAssertNotNil(deps.noteEditorState)
        XCTAssertNotNil(deps.folderState)
        XCTAssertNotNil(deps.syncState)
        XCTAssertNotNil(deps.authState)
        XCTAssertNotNil(deps.searchState)

        // 模块工厂
        XCTAssertNotNil(deps.networkModule)
        XCTAssertNotNil(deps.syncModule)
        XCTAssertNotNil(deps.editorModule)
        XCTAssertNotNil(deps.audioModule)

        // 辅助服务
        XCTAssertNotNil(deps.errorRecoveryService)
        XCTAssertNotNil(deps.networkRecoveryHandler)
        XCTAssertNotNil(deps.onlineStateManager)
        XCTAssertNotNil(deps.notePreviewService)
        XCTAssertNotNil(deps.memoryCacheManager)
    }

    @MainActor
    func testAppCoordinatorConvenienceInit_commandDispatcherReady() {
        let coordinator = AppCoordinator()

        XCTAssertNotNil(coordinator.commandDispatcher)
        XCTAssertNotNil(coordinator.noteStore)
        XCTAssertNotNil(coordinator.syncEngine)
        XCTAssertNotNil(coordinator.noteListState)
        XCTAssertNotNil(coordinator.noteEditorState)
        XCTAssertNotNil(coordinator.folderState)
        XCTAssertNotNil(coordinator.syncState)
        XCTAssertNotNil(coordinator.authState)
    }
}
