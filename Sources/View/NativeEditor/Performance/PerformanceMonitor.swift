//
//  PerformanceMonitor.swift
//  MiNoteMac
//
//  Created by Kiro on 2026-01-15.
//  性能监控器 - 用于监控编辑器的各项性能指标
//

import Foundation
import Combine

/// 性能监控器
/// 
/// 用于监控原生编辑器的性能指标，包括：
/// - 输入法状态检测
/// - 保存操作触发
/// - 视图更新频率
///
/// 使用单例模式，确保全局只有一个监控实例
@MainActor
class PerformanceMonitor: ObservableObject {
    
    // MARK: - 单例
    
    /// 共享实例
    static let shared = PerformanceMonitor()
    
    // MARK: - 输入法状态监控
    
    /// 输入法检测次数
    @Published var inputMethodDetectionCount: Int = 0
    
    /// 输入法组合状态总持续时间（秒）
    @Published var inputMethodCompositionDuration: TimeInterval = 0
    
    // MARK: - 保存触发监控
    
    /// 保存请求总次数
    @Published var saveRequestCount: Int = 0
    
    /// 实际执行保存的次数
    @Published var actualSaveCount: Int = 0
    
    /// 因输入法状态而跳过的保存次数
    @Published var skippedSaveCount_InputMethod: Int = 0
    
    /// 因内容未变化而跳过的保存次数
    @Published var skippedSaveCount_NoChange: Int = 0
    
    // MARK: - 视图更新监控
    
    /// 视图重绘次数
    @Published var viewRedrawCount: Int = 0
    
    /// 内容重新加载次数
    @Published var contentReloadCount: Int = 0
    
    /// 状态更新次数
    @Published var stateUpdateCount: Int = 0
    
    // MARK: - 私有属性
    
    /// 输入法组合开始时间（用于计算持续时间）
    private var compositionStartTime: Date?
    
    // MARK: - 初始化
    
    /// 私有初始化方法（单例模式）
    private init() {}
    
    // MARK: - 输入法状态监控方法
    
    /// 记录输入法检测
    func recordInputMethodDetection() {
        inputMethodDetectionCount += 1
    }
    
    /// 记录输入法组合开始
    func recordCompositionStart() {
        compositionStartTime = Date()
    }
    
    /// 记录输入法组合结束
    func recordCompositionEnd() {
        if let startTime = compositionStartTime {
            inputMethodCompositionDuration += Date().timeIntervalSince(startTime)
            compositionStartTime = nil
        }
    }
    
    // MARK: - 保存触发监控方法
    
    /// 记录保存请求
    func recordSaveRequest() {
        saveRequestCount += 1
    }
    
    /// 记录实际保存
    func recordActualSave() {
        actualSaveCount += 1
    }
    
    /// 记录跳过保存（输入法状态）
    func recordSkippedSave_InputMethod() {
        skippedSaveCount_InputMethod += 1
    }
    
    /// 记录跳过保存（内容未变化）
    func recordSkippedSave_NoChange() {
        skippedSaveCount_NoChange += 1
    }
    
    // MARK: - 视图更新监控方法
    
    /// 记录视图重绘
    func recordViewRedraw() {
        viewRedrawCount += 1
    }
    
    /// 记录内容重新加载
    func recordContentReload() {
        contentReloadCount += 1
    }
    
    /// 记录状态更新
    func recordStateUpdate() {
        stateUpdateCount += 1
    }
    
    // MARK: - 工具方法
    
    /// 重置所有计数器
    func reset() {
        inputMethodDetectionCount = 0
        inputMethodCompositionDuration = 0
        saveRequestCount = 0
        actualSaveCount = 0
        skippedSaveCount_InputMethod = 0
        skippedSaveCount_NoChange = 0
        viewRedrawCount = 0
        contentReloadCount = 0
        stateUpdateCount = 0
        compositionStartTime = nil
    }
    
    /// 打印性能报告
    func printReport() {
        print("=== 性能监控报告 ===")
        print("输入法检测次数: \(inputMethodDetectionCount)")
        print("输入法组合总时长: \(String(format: "%.2f", inputMethodCompositionDuration))s")
        print("保存请求次数: \(saveRequestCount)")
        print("实际保存次数: \(actualSaveCount)")
        print("跳过保存（输入法）: \(skippedSaveCount_InputMethod)")
        print("跳过保存（无变化）: \(skippedSaveCount_NoChange)")
        print("视图重绘次数: \(viewRedrawCount)")
        print("内容重新加载次数: \(contentReloadCount)")
        print("状态更新次数: \(stateUpdateCount)")
        
        // 计算保存效率
        if saveRequestCount > 0 {
            let saveEfficiency = Double(actualSaveCount) / Double(saveRequestCount) * 100
            print("保存效率: \(String(format: "%.1f", saveEfficiency))%")
        }
        
        // 计算平均组合时长
        if inputMethodDetectionCount > 0 {
            let avgCompositionDuration = inputMethodCompositionDuration / Double(inputMethodDetectionCount)
            print("平均组合时长: \(String(format: "%.3f", avgCompositionDuration))s")
        }
        
        print("==================")
    }
}
