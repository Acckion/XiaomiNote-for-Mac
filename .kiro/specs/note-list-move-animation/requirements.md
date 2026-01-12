# Requirements Document

## Introduction

为笔记列表添加移动动画支持。当用户编辑笔记时，笔记的编辑时间会更新，导致笔记在列表中的位置发生变化（通常移动到最顶端）。此功能为这种位置变化添加平滑的移动动画，提升用户体验。

## Glossary

- **NotesListView**: 笔记列表视图组件，显示所有笔记的列表
- **NoteRow**: 单个笔记行视图组件
- **filteredNotes**: 经过筛选和排序后的笔记数组
- **Move_Animation**: 列表项位置变化时的过渡动画

## Requirements

### Requirement 1: 笔记位置变化动画

**User Story:** As a user, I want to see a smooth animation when my edited note moves to the top of the list, so that I can visually track the note's position change.

#### Acceptance Criteria

1. WHEN a note's position changes in the list due to edit time update, THE NotesListView SHALL animate the note's movement with a smooth transition
2. THE Move_Animation SHALL use easeInOut timing curve with 300ms duration
3. THE Move_Animation SHALL only apply to note position changes, not to other list updates like adding or deleting notes
4. WHEN the animation is playing, THE NotesListView SHALL maintain the current selection state without interruption
