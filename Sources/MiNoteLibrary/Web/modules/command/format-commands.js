/**
 * Format Commands 模块
 * 注册格式相关的命令（加粗、斜体等）
 * 依赖: command, logger, constants
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { FORMAT: 'Format' };
    const OPERATION_TYPES = window.OPERATION_TYPES || { FORMAT: 'format' };
    const Command = window.Command;
    const CommandManager = window.CommandManager;

    /**
     * 注册格式命令
     * @param {CommandManager} cmdManager - 命令管理器
     * @param {DOMWriter} domWriter - DOM 写入器（可选，用于历史记录）
     */
    function registerFormatCommands(cmdManager, domWriter) {
        const editor = document.getElementById('editor-content');
        if (!editor) {
            log.warn(LOG_MODULES.FORMAT, '编辑器元素不存在，无法注册格式命令');
            return;
        }
        
        // 格式命令：加粗、斜体、下划线、删除线、高亮
        const formatCommands = ['bold', 'italic', 'underline', 'strikethrough', 'highlight'];
        
        formatCommands.forEach(format => {
            cmdManager.register(`format:${format}`, {
                type: OPERATION_TYPES.FORMAT,
                execute: (context) => {
                    // 使用现有的 applyFormat 方法（需要在 editor-api 中定义）
                    if (window.MiNoteWebEditor && window.MiNoteWebEditor.applyFormat) {
                        const result = window.MiNoteWebEditor.applyFormat(format);
                        
                        // 返回状态（用于撤销）
                        return {
                            format: format,
                            result: result
                        };
                    } else {
                        throw new Error('applyFormat method not available');
                    }
                },
                canExecute: (context) => {
                    // 检查是否有选择内容
                    const selection = window.getSelection();
                    return selection && selection.rangeCount > 0;
                },
                getState: (context) => {
                    // 检查当前格式状态
                    const selection = window.getSelection();
                    if (!selection || selection.rangeCount === 0) {
                        return { active: false };
                    }
                    
                    const range = selection.getRangeAt(0);
                    if (window.MiNoteWebEditor && window.MiNoteWebEditor.checkFormatState) {
                        const isActive = window.MiNoteWebEditor.checkFormatState(range, format);
                        return { active: isActive };
                    }
                    return { active: false };
                },
                metadata: {
                    format: format,
                    category: 'text-format'
                }
            });
        });
        
        log.info(LOG_MODULES.FORMAT, '格式命令注册完成', { 
            count: formatCommands.length 
        });
    }
    
    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Command = window.MiNoteEditor.Command || {};
    window.MiNoteEditor.Command.registerFormatCommands = registerFormatCommands;
    
    // 向后兼容
    window._registerFormatCommands = registerFormatCommands;
    
})();

