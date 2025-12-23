/**
 * Constants 模块
 * 定义编辑器使用的常量
 * 依赖: logger (可选，用于日志)
 */

(function() {
    'use strict';

    // ==================== 日志模块常量 ====================
    /**
     * 日志模块名称常量
     * 用于统一标识不同的功能模块
     */
    const LOG_MODULES = {
        EDITOR: 'Editor',           // 编辑器核心
        DOM_WRITER: 'DOMWriter',   // DOM 操作
        CONVERTER: 'Converter',     // XML/HTML 转换
        CURSOR: 'Cursor',           // 光标管理
        FORMAT: 'Format',           // 格式操作
        HISTORY: 'History',         // 撤销/重做
        IMAGE: 'Image',             // 图片处理
        LIST: 'List',               // 列表操作
        SELECTION: 'Selection',     // 选择管理
        SYNC: 'Sync',               // 状态同步
        INIT: 'Init',               // 初始化
        EVENT: 'Event',             // 事件处理
        UTILS: 'Utils'              // 工具函数
    };
    
    // ==================== 操作类型枚举 ====================
    /**
     * 操作类型枚举
     * 用于分类和合并操作
     */
    const OPERATION_TYPES = {
        INPUT: 'input',           // 文本输入
        DELETE: 'delete',         // 删除操作
        FORMAT: 'format',         // 格式操作（加粗、斜体等）
        FORMAT_REMOVE: 'format_remove', // 移除格式
        HEADING: 'heading',       // 标题
        ALIGNMENT: 'alignment',   // 对齐
        LIST: 'list',             // 列表
        CHECKBOX: 'checkbox',     // 复选框
        QUOTE: 'quote',           // 引用
        IMAGE: 'image',           // 图片
        INDENT: 'indent',         // 缩进
        HR: 'hr',                 // 水平线
        BATCH: 'batch',           // 批量操作
        OTHER: 'other'            // 其他操作
    };
    
    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Constants = {
        LOG_MODULES: LOG_MODULES,
        OPERATION_TYPES: OPERATION_TYPES
    };
    
    // 向后兼容：直接暴露到全局
    window.LOG_MODULES = LOG_MODULES;
    window.OPERATION_TYPES = OPERATION_TYPES;
    
})();
