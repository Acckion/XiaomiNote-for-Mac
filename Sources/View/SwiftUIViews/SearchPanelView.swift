//
//  SearchPanelView.swift
//  MiNoteLibrary
//
//  Created by Acckion on 2026/1/7.
//  Copyright © 2026 Acckion. All rights reserved.
//

import SwiftUI

/// 查找面板视图模型
class SearchPanelViewModel: ObservableObject {
    @Published var searchText: String
    @Published var replaceText: String
    @Published var isCaseSensitive: Bool
    @Published var isWholeWord: Bool
    @Published var isRegex: Bool

    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    init(
        searchText: String,
        replaceText: String,
        isCaseSensitive: Bool,
        isWholeWord: Bool,
        isRegex: Bool,
        onFindNext: @escaping () -> Void,
        onFindPrevious: @escaping () -> Void,
        onReplace: @escaping () -> Void,
        onReplaceAll: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.searchText = searchText
        self.replaceText = replaceText
        self.isCaseSensitive = isCaseSensitive
        self.isWholeWord = isWholeWord
        self.isRegex = isRegex
        self.onFindNext = onFindNext
        self.onFindPrevious = onFindPrevious
        self.onReplace = onReplace
        self.onReplaceAll = onReplaceAll
        self.onClose = onClose
    }
}

/// 查找面板视图
struct SearchPanelView: View {
    @ObservedObject var viewModel: SearchPanelViewModel

    var body: some View {
        VStack(spacing: 8) {
            // 标题栏
            HStack {
                Text("查找和替换")
                    .font(.headline)
                Spacer()
                Button(action: viewModel.onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // 搜索框
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("查找", text: $viewModel.searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .onSubmit(viewModel.onFindNext)
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)

                // 替换框
                HStack {
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    TextField("替换为", text: $viewModel.replaceText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
            }
            .padding(.horizontal, 12)

            // 选项
            VStack(alignment: .leading, spacing: 4) {
                Toggle("区分大小写", isOn: $viewModel.isCaseSensitive)
                Toggle("全字匹配", isOn: $viewModel.isWholeWord)
                Toggle("正则表达式", isOn: $viewModel.isRegex)
            }
            .padding(.horizontal, 12)
            .font(.system(size: 12))

            Divider()

            // 按钮行
            HStack(spacing: 8) {
                Button("查找上一个", action: viewModel.onFindPrevious)
                    .disabled(viewModel.searchText.isEmpty)

                Button("查找下一个", action: viewModel.onFindNext)
                    .disabled(viewModel.searchText.isEmpty)
                    .keyboardShortcut("g", modifiers: [.command])

                Spacer()

                Button("替换", action: viewModel.onReplace)
                    .disabled(viewModel.searchText.isEmpty)

                Button("全部替换", action: viewModel.onReplaceAll)
                    .disabled(viewModel.searchText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 320)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

#Preview {
    let viewModel = SearchPanelViewModel(
        searchText: "搜索文本",
        replaceText: "替换文本",
        isCaseSensitive: false,
        isWholeWord: false,
        isRegex: false,
        onFindNext: {},
        onFindPrevious: {},
        onReplace: {},
        onReplaceAll: {},
        onClose: {}
    )

    SearchPanelView(viewModel: viewModel)
        .padding()
}
