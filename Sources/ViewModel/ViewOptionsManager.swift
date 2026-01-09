//
//  ViewOptionsManager.swift
//  MiNoteMac
//
//  视图选项管理器
//

import Foundation
import SwiftUI
import Combine

// MARK: - 视图选项管理器

/// 视图选项管理器
/// 
/// 负责管理和持久化视图选项状态，包括排序方式、排序方向、日期分组和视图模式
/// 使用单例模式确保全局状态一致性
/// _Requirements: 2.9, 3.6, 4.7_
@MainActor
public class ViewOptionsManager: ObservableObject {
    
    // MARK: - 单例
    
    /// 单例实例
    public static let shared = ViewOptionsManager()
    
    // MARK: - 发布属性
    
    /// 当前视图选项状态
    @Published public private(set) var state: ViewOptionsState
    
    // MARK: - 私有属性
    
    /// 持久化键
    private let persistenceKey = "ViewOptionsState"
    
    /// UserDefaults 实例
    private let defaults: UserDefaults
    
    // MARK: - 初始化
    
    /// 初始化方法
    /// - Parameter defaults: UserDefaults 实例，默认为 standard
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.state = Self.loadState(from: defaults) ?? .default
    }
    
    // MARK: - 公开方法
    
    /// 更新排序方式
    /// _Requirements: 2.3_
    /// - Parameter order: 新的排序方式
    public func setSortOrder(_ order: NoteSortOrder) {
        guard state.sortOrder != order else { return }
        state.sortOrder = order
        saveState()
    }
    
    /// 更新排序方向
    /// _Requirements: 2.7_
    /// - Parameter direction: 新的排序方向
    public func setSortDirection(_ direction: SortDirection) {
        guard state.sortDirection != direction else { return }
        state.sortDirection = direction
        saveState()
    }
    
    /// 切换日期分组
    /// _Requirements: 3.3, 3.4_
    public func toggleDateGrouping() {
        state.isDateGroupingEnabled.toggle()
        saveState()
    }
    
    /// 设置日期分组状态
    /// _Requirements: 3.3, 3.4_
    /// - Parameter enabled: 是否启用日期分组
    public func setDateGrouping(_ enabled: Bool) {
        guard state.isDateGroupingEnabled != enabled else { return }
        state.isDateGroupingEnabled = enabled
        saveState()
    }
    
    /// 设置视图模式
    /// _Requirements: 4.3_
    /// - Parameter mode: 新的视图模式
    public func setViewMode(_ mode: ViewMode) {
        guard state.viewMode != mode else { return }
        state.viewMode = mode
        saveState()
    }
    
    /// 重置为默认设置
    public func resetToDefault() {
        state = .default
        saveState()
    }
    
    /// 更新完整状态
    /// - Parameter newState: 新的视图选项状态
    public func updateState(_ newState: ViewOptionsState) {
        guard state != newState else { return }
        state = newState
        saveState()
    }
    
    // MARK: - 私有方法
    
    /// 保存状态到 UserDefaults
    private func saveState() {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: persistenceKey)
        } catch {
            print("[ViewOptionsManager] 保存状态失败: \(error.localizedDescription)")
        }
    }
    
    /// 从 UserDefaults 加载状态
    /// - Parameter defaults: UserDefaults 实例
    /// - Returns: 加载的视图选项状态，如果加载失败则返回 nil
    private static func loadState(from defaults: UserDefaults) -> ViewOptionsState? {
        guard let data = defaults.data(forKey: "ViewOptionsState") else {
            return nil
        }
        
        do {
            let state = try JSONDecoder().decode(ViewOptionsState.self, from: data)
            return state
        } catch {
            print("[ViewOptionsManager] 加载状态失败: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - 便捷访问扩展

extension ViewOptionsManager {
    /// 当前排序方式
    public var sortOrder: NoteSortOrder {
        state.sortOrder
    }
    
    /// 当前排序方向
    public var sortDirection: SortDirection {
        state.sortDirection
    }
    
    /// 是否启用日期分组
    public var isDateGroupingEnabled: Bool {
        state.isDateGroupingEnabled
    }
    
    /// 当前视图模式
    public var viewMode: ViewMode {
        state.viewMode
    }
    
    /// 是否为列表视图
    public var isListView: Bool {
        state.viewMode == .list
    }
    
    /// 是否为画廊视图
    public var isGalleryView: Bool {
        state.viewMode == .gallery
    }
}
