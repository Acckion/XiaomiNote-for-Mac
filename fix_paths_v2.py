import re

# 读取 project.pbxproj 文件
with open('MiNoteMac.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 定义文件路径映射 - 注意：路径应该是相对于父组（View目录）的
path_mapping = [
    (r'path\s*=\s*"?ContentView\.swift"?;', 'path = "SwiftUIViews/ContentView.swift";'),
    (r'path\s*=\s*"?CookieRefreshView\.swift"?;', 'path = "SwiftUIViews/CookieRefreshView.swift";'),
    (r'path\s*=\s*"?DebugSettingsView\.swift"?;', 'path = "SwiftUIViews/DebugSettingsView.swift";'),
    (r'path\s*=\s*"?LoginView\.swift"?;', 'path = "SwiftUIViews/LoginView.swift";'),
    (r'path\s*=\s*"?MoveNoteView\.swift"?;', 'path = "SwiftUIViews/MoveNoteView.swift";'),
    (r'path\s*=\s*"?NetworkLogView\.swift"?;', 'path = "SwiftUIViews/NetworkLogView.swift";'),
    (r'path\s*=\s*"?NewNoteView\.swift"?;', 'path = "SwiftUIViews/NewNoteView.swift";'),
    (r'path\s*=\s*"?NoteDetailView\.swift"?;', 'path = "SwiftUIViews/NoteDetailView.swift";'),
    (r'path\s*=\s*"?NoteDetailViewController\.swift"?;', 'path = "AppKitComponents/NoteDetailViewController.swift";'),
    (r'path\s*=\s*"?NoteDetailWindowView\.swift"?;', 'path = "SwiftUIViews/NoteDetailWindowView.swift";'),
    (r'path\s*=\s*"?NoteHistoryView\.swift"?;', 'path = "SwiftUIViews/NoteHistoryView.swift";'),
    (r'path\s*=\s*"?NotesListHostingController\.swift"?;', 'path = "Bridge/NotesListHostingController.swift";'),
    (r'path\s*=\s*"?NotesListView\.swift"?;', 'path = "SwiftUIViews/NotesListView.swift";'),
    (r'path\s*=\s*"?NotesListViewController\.swift"?;', 'path = "AppKitComponents/NotesListViewController.swift";'),
    (r'path\s*=\s*"?OfflineOperationsProgressView\.swift"?;', 'path = "SwiftUIViews/OfflineOperationsProgressView.swift";'),
    (r'path\s*=\s*"?OnlineStatusIndicator\.swift"?;', 'path = "Shared/OnlineStatusIndicator.swift";'),
    (r'path\s*=\s*"?PrivateNotesPasswordInputDialogView\.swift"?;', 'path = "SwiftUIViews/PrivateNotesPasswordInputDialogView.swift";'),
    (r'path\s*=\s*"?PrivateNotesVerificationView\.swift"?;', 'path = "SwiftUIViews/PrivateNotesVerificationView.swift";'),
    (r'path\s*=\s*"?SearchFilterMenuContent\.swift"?;', 'path = "SwiftUIViews/SearchFilterMenuContent.swift";'),
    (r'path\s*=\s*"?SearchFilterPopoverView\.swift"?;', 'path = "SwiftUIViews/SearchFilterPopoverView.swift";'),
    (r'path\s*=\s*"?SettingsView\.swift"?;', 'path = "SwiftUIViews/SettingsView.swift";'),
    (r'path\s*=\s*"?SidebarHostingController\.swift"?;', 'path = "Bridge/SidebarHostingController.swift";'),
    (r'path\s*=\s*"?SidebarView\.swift"?;', 'path = "SwiftUIViews/SidebarView.swift";'),
    (r'path\s*=\s*"?SidebarViewController\.swift"?;', 'path = "AppKitComponents/SidebarViewController.swift";'),
    (r'path\s*=\s*"?TitleEditorView\.swift"?;', 'path = "SwiftUIViews/TitleEditorView.swift";'),
    (r'path\s*=\s*"?TrashView\.swift"?;', 'path = "SwiftUIViews/TrashView.swift";'),
    (r'path\s*=\s*"?WebEditorContext\.swift"?;', 'path = "Bridge/WebEditorContext.swift";'),
    (r'path\s*=\s*"?WebEditorView\.swift"?;', 'path = "SwiftUIViews/WebEditorView.swift";'),
    (r'path\s*=\s*"?WebEditorWrapper\.swift"?;', 'path = "Bridge/WebEditorWrapper.swift";'),
    (r'path\s*=\s*"?WebFormatMenuView\.swift"?;', 'path = "Bridge/WebFormatMenuView.swift";'),
]

# 更新文件路径
for pattern, replacement in path_mapping:
    content = re.sub(pattern, replacement, content)

# 写回文件
with open('MiNoteMac.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print('project.pbxproj 文件路径已更新（版本2）')
