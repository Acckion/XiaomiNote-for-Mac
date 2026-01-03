import re

# 读取 project.pbxproj 文件
with open('MiNoteMac.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 定义文件路径映射
path_mapping = [
    ('path = \"ContentView.swift\";', 'path = \"View/SwiftUIViews/ContentView.swift\";'),
    ('path = \"CookieRefreshView.swift\";', 'path = \"View/SwiftUIViews/CookieRefreshView.swift\";'),
    ('path = \"DebugSettingsView.swift\";', 'path = \"View/SwiftUIViews/DebugSettingsView.swift\";'),
    ('path = \"LoginView.swift\";', 'path = \"View/SwiftUIViews/LoginView.swift\";'),
    ('path = \"MoveNoteView.swift\";', 'path = \"View/SwiftUIViews/MoveNoteView.swift\";'),
    ('path = \"NetworkLogView.swift\";', 'path = \"View/SwiftUIViews/NetworkLogView.swift\";'),
    ('path = \"NewNoteView.swift\";', 'path = \"View/SwiftUIViews/NewNoteView.swift\";'),
    ('path = \"NoteDetailView.swift\";', 'path = \"View/SwiftUIViews/NoteDetailView.swift\";'),
    ('path = \"NoteDetailViewController.swift\";', 'path = \"View/AppKitComponents/NoteDetailViewController.swift\";'),
    ('path = \"NoteDetailWindowView.swift\";', 'path = \"View/SwiftUIViews/NoteDetailWindowView.swift\";'),
    ('path = \"NoteHistoryView.swift\";', 'path = \"View/SwiftUIViews/NoteHistoryView.swift\";'),
    ('path = \"NotesListHostingController.swift\";', 'path = \"View/Bridge/NotesListHostingController.swift\";'),
    ('path = \"NotesListView.swift\";', 'path = \"View/SwiftUIViews/NotesListView.swift\";'),
    ('path = \"NotesListViewController.swift\";', 'path = \"View/AppKitComponents/NotesListViewController.swift\";'),
    ('path = \"OfflineOperationsProgressView.swift\";', 'path = \"View/SwiftUIViews/OfflineOperationsProgressView.swift\";'),
    ('path = \"OnlineStatusIndicator.swift\";', 'path = \"View/Shared/OnlineStatusIndicator.swift\";'),
    ('path = \"PrivateNotesPasswordInputDialogView.swift\";', 'path = \"View/SwiftUIViews/PrivateNotesPasswordInputDialogView.swift\";'),
    ('path = \"PrivateNotesVerificationView.swift\";', 'path = \"View/SwiftUIViews/PrivateNotesVerificationView.swift\";'),
    ('path = \"SearchFilterMenuContent.swift\";', 'path = \"View/SwiftUIViews/SearchFilterMenuContent.swift\";'),
    ('path = \"SearchFilterPopoverView.swift\";', 'path = \"View/SwiftUIViews/SearchFilterPopoverView.swift\";'),
    ('path = \"SettingsView.swift\";', 'path = \"View/SwiftUIViews/SettingsView.swift\";'),
    ('path = \"SidebarHostingController.swift\";', 'path = \"View/Bridge/SidebarHostingController.swift\";'),
    ('path = \"SidebarView.swift\";', 'path = \"View/SwiftUIViews/SidebarView.swift\";'),
    ('path = \"SidebarViewController.swift\";', 'path = \"View/AppKitComponents/SidebarViewController.swift\";'),
    ('path = \"TitleEditorView.swift\";', 'path = \"View/SwiftUIViews/TitleEditorView.swift\";'),
    ('path = \"TrashView.swift\";', 'path = \"View/SwiftUIViews/TrashView.swift\";'),
    ('path = \"WebEditorContext.swift\";', 'path = \"View/Bridge/WebEditorContext.swift\";'),
    ('path = \"WebEditorView.swift\";', 'path = \"View/SwiftUIViews/WebEditorView.swift\";'),
    ('path = \"WebEditorWrapper.swift\";', 'path = \"View/Bridge/WebEditorWrapper.swift\";'),
    ('path = \"WebFormatMenuView.swift\";', 'path = \"View/Bridge/WebFormatMenuView.swift\";'),
]

# 更新文件路径
for old_path, new_path in path_mapping:
    content = content.replace(old_path, new_path)

# 写回文件
with open('MiNoteMac.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print('project.pbxproj 文件已更新')
"