//
//  OnlineStatusIndicator.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/2.
//  Copyright © 2026 Acckion. All rights reserved.
//

#if os(macOS)
    import SwiftUI

    /// 在线状态指示器视图
    /// 用于在工具栏中显示当前网络连接状态
    struct OnlineStatusIndicator: View {
        @ObservedObject var viewModel: NotesViewModel

        var body: some View {
            HStack(spacing: 4) {
                // 状态指示器
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                // 状态文本
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }
            .frame(height: 24)
            .help(statusHelpText)
        }

        /// 状态颜色
        private var statusColor: Color {
            if viewModel.isOnline {
                .green
            } else if viewModel.isCookieExpired {
                .red
            } else {
                .yellow
            }
        }

        /// 状态文本
        private var statusText: String {
            if viewModel.isOnline {
                "在线"
            } else if viewModel.isCookieExpired {
                "Cookie失效"
            } else {
                "离线"
            }
        }

        /// 状态提示文本
        private var statusHelpText: String {
            if viewModel.isOnline {
                "已连接到小米笔记服务器"
            } else if viewModel.isCookieExpired {
                "Cookie已失效，请刷新Cookie或重新登录"
            } else {
                "离线模式：更改将在网络恢复后同步"
            }
        }
    }
#endif
