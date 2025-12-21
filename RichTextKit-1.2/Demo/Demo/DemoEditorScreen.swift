//
//  DemoEditorScreen.swift
//  Demo
//
//  Created by Daniel Saidi on 2024-03-04.
//  Copyright © 2024 Kankoda Sweden AB. All rights reserved.
//

import RichTextKit
import SwiftUI

struct DemoEditorScreen: View {

    @Binding var document: DemoDocument

    @State private var isInspectorPresented = false
    @State private var showAttachmentDemo = false

    @StateObject var context = RichTextContext()

    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // 自定义工具栏，添加新功能按钮
            HStack(spacing: 12) {
                RichTextFormat.Toolbar(context: context)
                
                Divider()
                    .frame(height: 20)
                
                // 新增功能按钮
                Button {
                    context.insertCheckbox(isChecked: false, withSpace: true)
                } label: {
                    Image(systemName: "checklist")
                }
                .help("插入待办复选框")
                
                Button {
                    context.insertHorizontalRule(withNewlines: true)
                } label: {
                    Image(systemName: "minus")
                }
                .help("插入分割线")
                
                Button {
                    context.insertBlockQuote(withSpace: true)
                    context.applyBlockQuoteStyling()
                } label: {
                    Image(systemName: "quote.bubble")
                }
                .help("插入引用块")
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            
            RichTextEditor(
                text: $document.text,
                context: context
            ) {
                $0.textContentInset = CGSize(width: 30, height: 30)
            }
            // Use this to just view the text:
            // RichTextViewer(document.text)
            #if os(iOS)
            RichTextKeyboardToolbar(
                context: context,
                leadingButtons: { $0 },
                trailingButtons: { $0 },
                formatSheet: { $0 }
            )
            #endif
        }
        .sheet(isPresented: $showAttachmentDemo) {
            AttachmentFeaturesDemo()
        }
        .inspector(isPresented: $isInspectorPresented) {
            RichTextFormat.Sidebar(context: context)
                #if os(macOS)
                .inspectorColumnWidth(min: 200, ideal: 200, max: 315)
                #endif
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $isInspectorPresented) {
                    Image.richTextFormatBrush
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                Button {
                    showAttachmentDemo = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .help("测试新增功能")
            }
            #endif
        }
        .frame(minWidth: 500)
        .focusedValue(\.richTextContext, context)
        .toolbarRole(.automatic)
        .richTextFormatSheetConfig(.init(colorPickers: colorPickers))
        .richTextFormatSidebarConfig(
            .init(
                colorPickers: colorPickers,
                fontPicker: isMac
            )
        )
        .richTextFormatToolbarConfig(.init(colorPickers: []))
        .viewDebug()
    }
}

private extension DemoEditorScreen {

    var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var colorPickers: [RichTextColor] {
        [.foreground, .background]
    }

    var formatToolbarEdge: VerticalEdge {
        isMac ? .top : .bottom
    }
}

#Preview {
    DemoEditorScreen(
        document: .constant(DemoDocument()),
        context: .init()
    )
}
