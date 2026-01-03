import re

# 读取 project.pbxproj 文件
with open('MiNoteMac.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 定义文件路径映射 - 注意：这里使用正则表达式来匹配有引号或没有引号的情况
path_mapping = [
    (r'path\s*=\s*"?ContentView\.swift"?;', 'path = "View/SwiftUIViews/ContentView.swift";'),
    (r'path\s*=\s*"?CookieRefreshView\.swift"?;', 'path = "View/SwiftUIViews/CookieRefreshView.swift";'),
    (r'path\s*=\s*"?DebugSettingsView\.swift"?;', 'path = "View/SwiftUIViews/DebugSettingsView.swift";'),
    (r'path\s*=\s*"?LoginView\.swift"?;', 'path = "View/SwiftUIViews/LoginView.swift";'),
    (r'path\s*=\s*"?MoveNoteView\.swift"?;', 'path = "View/SwiftUIViews/MoveNoteView.swift";'),
    (r'path\s*=\s*"?NetworkLogView\.swift"?;', 'path = "View/SwiftUIViews/NetworkLogView.swift";'),
    (r'path\s*=\s*"?NewNoteView\.swift"?;', 'path = "View/SwiftUIViews/NewNoteView.swift";'),
    (r'path\s*=\s*"?NoteDetailView\.swift"?;', 'path = "View/SwiftUIViews/NoteDetailView.swift";'),
    (r'path\s*=\s*"?NoteDetailViewController\.swift"?;', 'path = "View/AppKitComponents/NoteDetailViewController.swift";'),
    (r'path\s*=\s*"?NoteDetailWindowView\.swift"?;', 'path = "View/SwiftUIViews/NoteDetailWindowView.swift";'),
    (r'path\s*=\s*"?NoteHistoryView\.swift"?;', 'path = "View/SwiftUIViews/NoteHistoryView.swift";'),
    (r'path\s*=\s*"?NotesListHostingController\.swift"?;', 'path = "View/Bridge/NotesListHostingController.swift";'),
    (r'path\s*=\s*"?NotesListView\.swift"?;', 'path = "View/SwiftUIViews/NotesListView.swift";'),
    (r'path\s*=\s*"?NotesListViewController\.swift"?;', 'path = "View/AppKitComponents/NotesListViewController.swift";'),
    (r'path\s*=\s*"?OfflineOperationsProgressView\.swift"?;', 'path = "View/SwiftUIViews/OfflineOperationsProgressView.swift";'),
    (r'path\s*=\s*"?OnlineStatusIndicator\.swift"?;', 'path = "View/Shared/OnlineStatusIndicator.swift";'),
    (r'path\s*=\s*"?PrivateNotesPasswordInputDialogView\.swift"?;', 'path = "View/SwiftUIViews/PrivateNotesPasswordInputDialogView.swift";'),
    (r'path\s*=\s*"?PrivateNotesVerificationView\.swift"?;', 'path = "View/SwiftUIViews/PrivateNotesVerificationView.swift";'),
    (r'path\s*=\s*"?SearchFilterMenuContent\.swift"?;', 'path = "View/SwiftUIViews/SearchFilterMenuContent.swift";'),
    (r'path\s*=\s*"?SearchFilterPopoverView\.swift"?;', 'path = "View/SwiftUIViews/SearchFilterPopoverView.swift";'),
    (r'path\s*=\s*"?SettingsView\.swift"?;', 'path = "View/SwiftUIViews/SettingsView.swift";'),
    (r'path\s*=\s*"?SidebarHostingController\.swift"?;', 'path = "View/Bridge/SidebarHostingController.swift";'),
    (r'path\s*=\s*"?SidebarView\.swift"?;', 'path = "View/SwiftUIViews/SidebarView.swift";'),
    (r'path\s*=\s*"?SidebarViewController\.swift"?;', 'path = "View/AppKitComponents/SidebarViewController.swift";'),
    (r'path\s*=\s*"?TitleEditorView\.swift"?;', 'path = "View/SwiftUIViews/TitleEditorView.swift";'),
    (r'path\s*=\s*"?TrashView\.swift"?;', 'path = "View/SwiftUIViews/TrashView.swift";'),
    (r'path\s*=\s*"?WebEditorContext\.swift"?;', 'path = "View/Bridge/WebEditorContext.swift";'),
    (r'path\s*=\s*"?WebEditorView\.swift"?;', 'path = "View/SwiftUIViews/WebEditorView.swift";'),
    (r'path\s*=\s*"?WebEditorWrapper\.swift"?;', 'path = "View/Bridge/WebEditorWrapper.swift";'),
    (r'path\s*=\s*"?WebFormatMenuView\.swift"?;', 'path = "View/Bridge/WebFormatMenuView.swift";'),
]

# 更新文件路径
for pattern, replacement in path_mapping:
    content = re.sub(pattern, replacement, content)

# 写回文件
with open('MiNoteMac.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print('project.pbxproj 文件路径已更新')
