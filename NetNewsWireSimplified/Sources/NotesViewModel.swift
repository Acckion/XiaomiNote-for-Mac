import Foundation
import Combine

/// 简化的笔记视图模型
/// 替代NetNewsWire中的复杂业务逻辑
class NotesViewModel: ObservableObject {
    @Published var folders: [Folder] = []
    @Published var selectedFolder: Folder?
    @Published var searchText: String = ""
    @Published var filteredNotes: [Note] = []
    @Published var selectedNote: Note?
    
    @Published var isSyncing: Bool = false
    @Published var isOnline: Bool = true
    @Published var isCookieExpired: Bool = false
    @Published var pendingOperationsCount: Int = 0
    @Published var lastSyncTime: Date? = Date()
    
    init() {
        loadMockData()
    }
    
    private func loadMockData() {
        // 创建模拟文件夹
        let allNotesFolder = Folder(id: "0", name: "所有笔记", count: 25, isSystem: true, isPinned: false)
        let starredFolder = Folder(id: "starred", name: "置顶", count: 5, isSystem: true, isPinned: true)
        let uncategorizedFolder = Folder(id: "uncategorized", name: "未分类", count: 10, isSystem: false, isPinned: false)
        let folder1 = Folder(id: "1", name: "工作", count: 8, isSystem: false, isPinned: true)
        let folder2 = Folder(id: "2", name: "个人", count: 7, isSystem: false, isPinned: false)
        let folder3 = Folder(id: "3", name: "项目", count: 5, isSystem: false, isPinned: false)
        
        folders = [allNotesFolder, starredFolder, uncategorizedFolder, folder1, folder2, folder3]
        selectedFolder = allNotesFolder
        
        // 创建模拟笔记
        var notes: [Note] = []
        let titles = [
            "项目进度报告",
            "会议纪要",
            "学习计划",
            "购物清单",
            "旅行计划",
            "读书笔记",
            "代码片段",
            "设计思路",
            "问题记录",
            "灵感收集"
        ]
        
        let contents = [
            "本周项目进展顺利，完成了主要功能的开发。",
            "讨论了下一季度的产品规划，确定了优先级。",
            "需要学习SwiftUI的高级特性，特别是动画和状态管理。",
            "牛奶、鸡蛋、面包、水果、蔬菜",
            "计划去日本旅行，需要办理签证和预订机票酒店。",
            "最近在读《设计模式》，对工厂模式有了新的理解。",
            "这段代码实现了自定义的工具栏按钮。",
            "新的UI设计采用了暗色主题，更加现代化。",
            "发现了一个性能问题，需要进一步优化。",
            "突然想到一个很好的产品功能，记录下来。"
        ]
        
        for i in 0..<10 {
            let note = Note(
                id: "\(i)",
                title: titles[i],
                content: contents[i],
                folderId: i < 5 ? "1" : "2",
                isStarred: i < 3,
                createdAt: Date().addingTimeInterval(-Double(i) * 86400),
                updatedAt: Date().addingTimeInterval(-Double(i) * 3600)
            )
            notes.append(note)
        }
        
        filteredNotes = notes
    }
    
    func createNewNote() {
        let newNote = Note(
            id: UUID().uuidString,
            title: "新建笔记",
            content: "这是新创建的笔记内容",
            folderId: selectedFolder?.id ?? "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        filteredNotes.insert(newNote, at: 0)
        selectedNote = newNote
    }
    
    func toggleStar(_ note: Note) {
        if let index = filteredNotes.firstIndex(where: { $0.id == note.id }) {
            filteredNotes[index].isStarred.toggle()
            objectWillChange.send()
        }
    }
    
    func deleteNote(_ note: Note) {
        filteredNotes.removeAll { $0.id == note.id }
        if selectedNote?.id == note.id {
            selectedNote = nil
        }
    }
    
    func performFullSync() {
        isSyncing = true
        // 模拟同步过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isSyncing = false
            self.lastSyncTime = Date()
        }
    }
    
    func performIncrementalSync() {
        isSyncing = true
        // 模拟增量同步
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isSyncing = false
            self.lastSyncTime = Date()
        }
    }
    
    func resetSyncStatus() {
        lastSyncTime = nil
        pendingOperationsCount = 0
    }
    
    func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
        // 这里可以模拟根据文件夹筛选笔记
        if let folder = folder {
            filteredNotes = filteredNotes.filter { $0.folderId == folder.id || folder.id == "0" }
        }
    }
}

struct Folder: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let count: Int
    let isSystem: Bool
    let isPinned: Bool
    var createdAt: Date = Date()
    
    static func == (lhs: Folder, rhs: Folder) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct Note: Identifiable {
    let id: String
    var title: String
    var content: String
    var folderId: String
    var isStarred: Bool
    let createdAt: Date
    let updatedAt: Date
}
