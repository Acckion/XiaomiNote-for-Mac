# Spec 分类目录

按项目模块划分的 spec 索引，便于查找和回顾。

## 编辑器（Editor）

原生富文本编辑器相关的功能开发、格式处理、Bug 修复。

| # | 名称 | 类型 |
|---|------|------|
| 6 | checkbox-list-support | feat |
| 10 | editor-save-optimization | refactor |
| 11 | format-menu-fix | fix |
| 12 | format-menu-paragraph-style-fix | fix |
| 13 | font-size-refactor | refactor |
| 15 | empty-line-persistence-fix | fix |
| 17 | native-editor-format-display-fix | fix |
| 18 | list-line-spacing-fix | fix |
| 19 | list-indent-alignment | fix |
| 21 | list-format-enhancement | feat |
| 22 | list-behavior-optimization | refactor |
| 23 | list-backspace-merge-fix | fix |
| 25 | native-editor-toolbar-rendering | fix |
| 29 | chinese-input-composition-fix | fix |
| 30 | native-editor-toolbar-integration | feat |
| 32 | native-rich-text-editor | feat |
| 33 | native-editor-persistence | feat |
| 35 | editor-save-final-fixes | fix |
| 38 | cursor-format-sync | fix |
| 39 | chinese-input-stability | fix |
| 40 | unified-format-manager | refactor |
| 46 | unified-format-menu | refactor |
| 48 | multi-selection-support | feat |
| 49 | chinese-ime-enter-key-fix | fix |
| 50 | attachment-selection-mechanism | feat |
| 69 | paper-inspired-editor-refactor | refactor |
| 94 | line-height-consistency-fix | fix |
| 103 | editor-bridge-refactor | refactor |

## 标题与内容管理（Title & Content）

标题编辑、标题与正文分离、内容持久化相关。

| # | 名称 | 类型 |
|---|------|------|
| 52 | editor-title-scroll-integration | feat |
| 66 | title-integration-fixes | fix |
| 67 | title-region-manager | refactor |
| 68 | paragraph-management-system | refactor |
| 70 | note-content-persistence-fix | fix |
| 72 | title-content-integration-fix | fix |
| 92 | title-editing-behavior-fix | fix |
| 93 | title-body-separation | refactor |
| 95 | title-save-trigger-fix | fix |

## 编辑器滚动与布局（Editor Layout）

统一滚动视图、信息栏、全屏布局相关。

| # | 名称 | 类型 |
|---|------|------|
| 53 | unified-scroll-view | feat |
| 65 | unified-editor-scroll-view | refactor |
| 73 | unified-editor-scroll-info-bar | feat |
| 73 | unified-scroll-view-fix | fix |
| 74 | editor-floating-info-bar | feat |
| 75 | editor-fullscreen-floating-info | feat |

## 保存与时间戳（Save & Timestamp）

笔记保存行为、时间戳保持、内容导出相关。

| # | 名称 | 类型 |
|---|------|------|
| 8 | editor-save-behavior-fix | fix |
| 41 | note-selection-timestamp-fix | fix |
| 55 | note-selection-content-export-fix | fix |
| 55 | note-selection-timestamp-preservation | fix |
| 57 | note-view-timestamp-preservation | fix |
| 59 | version-based-change-tracking | refactor |
| 96 | note-save-display-fix | fix |

## 笔记列表与选择（Note List）

笔记列表视图、排序、选择、动画相关。

| # | 名称 | 类型 |
|---|------|------|
| 31 | note-list-move-animation | feat |
| 34 | note-selection-position-fix | fix |
| 42 | note-list-sorting-fix | fix |
| 43 | notes-list-view-extension | feat |
| 60 | note-switching-loop-fix | fix |
| 64 | note-preview-images | feat |
| 76 | liquid-glass-sticky-headers | feat |

## 图片处理（Image）

图片渲染、下载、旧版格式兼容相关。

| # | 名称 | 类型 |
|---|------|------|
| 14 | image-rendering-fix | fix |
| 56 | legacy-image-format-fix | fix |
| 61 | image-download-fix | fix |
| 62 | legacy-image-format-fix | fix |
| 63 | image-download-optimization | perf |

## 音频功能（Audio）

音频录制、播放、面板布局、附件同步相关。

| # | 名称 | 类型 |
|---|------|------|
| 2 | audio-file-support | feat |
| 3 | audio-panel-layout | feat |
| 4 | audio-recording-fix | fix |
| 5 | audio-recording-persistence-fix | fix |
| 83 | audio-attachment-sync-fix | fix |

## 同步与操作队列（Sync & Queue）

云端同步、操作队列、文件上传相关。

| # | 名称 | 类型 |
|---|------|------|
| 7 | checkbox-sync-fix | fix |
| 26 | unified-operation-queue | feat |
| 36 | operation-queue-refactor | refactor |
| 54 | sync-state-manager | feat |
| 91 | xml-roundtrip-consistency-check | feat |
| 104 | file-upload-operation-queue | refactor |

## 网络与认证（Network & Auth）

Cookie 刷新、PassToken 认证、API 重构相关。

| # | 名称 | 类型 |
|---|------|------|
| 24 | cookie-refresh-loop-fix | fix |
| 58 | cookie-silent-refresh-fix | fix |
| 77 | cookie-auto-refresh-fix | fix |
| 86 | passtoken-auth-refactor | refactor |
| 86 | passtoken-authentication | refactor |
| 101 | cookie-auto-refresh-refactor | refactor |
| 102 | minote-service-refactor | refactor |

## 数据库（Database）

数据库管理、优化、清理相关。

| # | 名称 | 类型 |
|---|------|------|
| 55 | database-cleanup | refactor |
| 62 | database-optimization | perf |
| 85 | database-management-refactor | refactor |

## XML 处理（XML）

XML 与 NSAttributedString 转换、调试工具相关。

| # | 名称 | 类型 |
|---|------|------|
| 16 | xml-attributedstring-converter | feat |
| 27 | xml-debug-editor | feat |

## 架构重构（Architecture）

大规模架构重构、ViewModel 重构、状态管理相关。

| # | 名称 | 类型 |
|---|------|------|
| 44 | project-structure-refactor | refactor |
| 71 | note-model-refactor | refactor |
| 71 | note-model-architecture-improvement | refactor |
| 79 | notes-viewmodel-refactor | refactor |
| 80 | new-architecture-bug-fixes | fix |
| 81 | remove-old-architecture | refactor |
| 97 | notedetailview-architecture-refactor | refactor |
| 98 | state-management-refactor | refactor |
| 99 | architecture-audit | docs |
| 100 | architecture-refactor | refactor |

## 窗口与 UI（Window & UI）

窗口管理、菜单栏、工具栏、多窗口支持相关。

| # | 名称 | 类型 |
|---|------|------|
| 1 | apple-notes-menu-bar | feat |
| 9 | dynamic-toolbar-visibility | feat |
| 20 | menu-bar-functionality | feat |
| 47 | view-state-sync | fix |
| 82 | multi-window-support | feat |
| 105 | main-window-controller-refactor | refactor |

## 启动与登录（Startup & Login）

应用启动流程、登录界面、数据加载相关。

| # | 名称 | 类型 |
|---|------|------|
| 45 | startup-data-loading | feat |
| 78 | scheduled-task-manager-startup-fix | fix |
| 84 | startup-login-view-fix | fix |
| 88 | startup-login-popup-fix | fix |

## 基础设施（Infrastructure）

日志系统、代码清理、SwiftUI 发布问题相关。

| # | 名称 | 类型 |
|---|------|------|
| 37 | code-cleanup | refactor |
| 51 | code-cleanup-refactor | refactor |
| 87 | logging-system-refactor | refactor |
| 89 | view-update-publishing-fix | fix |
| 90 | view-update-publishing-fix | fix |
