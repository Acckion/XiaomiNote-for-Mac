/**
 * SelectionRange 类
 * 表示编辑器中的选择范围，包含起始和结束位置
 * 参考 CKEditor 5 的 Selection 对象设计
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { CURSOR: 'Cursor' };

    /**
     * SelectionRange 类
     * 表示编辑器中的选择范围
     */
    class SelectionRange {
        /**
         * 构造函数
         * @param {Position} start - 起始位置
         * @param {Position} end - 结束位置
         */
        constructor(start, end) {
            this.start = start; // Position对象
            this.end = end;     // Position对象
            this.isCollapsed = start.equals(end);
        }
        
        /**
         * 验证选择范围是否有效
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {boolean} 是否有效
         */
        isValid(editor) {
            return this.start.isValid(editor) && this.end.isValid(editor);
        }
        
        /**
         * 转换为DOM Selection
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {boolean} 是否成功设置
         */
        toDOMSelection(editor) {
            if (!this.isValid(editor)) {
                log.warn(LOG_MODULES.CURSOR, '选择范围无效，无法转换为DOM Selection');
                return false;
            }
            
            try {
                const selection = window.getSelection();
                selection.removeAllRanges();
                
                const range = document.createRange();
                
                // 设置起始位置
                const startNode = this.start.getNode(editor);
                if (!startNode) return false;
                
                if (startNode.nodeType === Node.TEXT_NODE) {
                    const startOffset = Math.min(this.start.offset, startNode.textContent.length);
                    range.setStart(startNode, startOffset);
                } else {
                    const startChildIndex = Math.min(this.start.offset, startNode.childNodes.length);
                    range.setStart(startNode, startChildIndex);
                }
                
                // 设置结束位置
                if (!this.isCollapsed) {
                    const endNode = this.end.getNode(editor);
                    if (!endNode) return false;
                    
                    if (endNode.nodeType === Node.TEXT_NODE) {
                        const endOffset = Math.min(this.end.offset, endNode.textContent.length);
                        range.setEnd(endNode, endOffset);
                    } else {
                        const endChildIndex = Math.min(this.end.offset, endNode.childNodes.length);
                        range.setEnd(endNode, endChildIndex);
                    }
                } else {
                    range.collapse(true);
                }
                
                selection.addRange(range);
                return true;
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '转换为DOM Selection失败', { error: error.message });
                return false;
            }
        }
        
        /**
         * 规范化选择范围
         * 确保起始位置在结束位置之前
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {SelectionRange} 规范化后的选择范围
         */
        normalize(editor) {
            if (this.start.compare(this.end) <= 0) {
                return this;
            }
            
            // 交换起始和结束位置
            return new SelectionRange(this.end, this.start);
        }
        
        /**
         * 从DOM Selection创建SelectionRange对象
         * @param {Selection} selection - 浏览器Selection对象
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {SelectionRange|null} SelectionRange对象
         */
        static fromDOM(selection, editor) {
            if (!selection.rangeCount) return null;
            
            const range = selection.getRangeAt(0);
            const startPosition = window.MiNoteEditor.Position.fromDOM(range, editor);
            
            if (!startPosition) return null;
            
            // 如果是折叠的选择，起始和结束位置相同
            if (range.collapsed) {
                return new SelectionRange(startPosition, startPosition);
            }
            
            // 创建结束位置
            const endRange = range.cloneRange();
            endRange.collapse(false);
            const endPosition = window.MiNoteEditor.Position.fromDOM(endRange, editor);
            
            if (!endPosition) return null;
            
            return new SelectionRange(startPosition, endPosition);
        }
        
        /**
         * 从当前浏览器Selection创建SelectionRange对象
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {SelectionRange|null} SelectionRange对象
         */
        static fromCurrentSelection(editor) {
            const selection = window.getSelection();
            return SelectionRange.fromDOM(selection, editor);
        }
        
        /**
         * 转换为字符串表示（用于存储）
         * @returns {string} JSON字符串
         */
        toString() {
            return JSON.stringify({
                start: this.start.toString(),
                end: this.end.toString(),
                isCollapsed: this.isCollapsed
            });
        }
        
        /**
         * 从字符串创建SelectionRange对象
         * @param {string} str - JSON字符串
         * @returns {SelectionRange|null} SelectionRange对象
         */
        static fromString(str) {
            try {
                const data = JSON.parse(str);
                const start = window.MiNoteEditor.Position.fromString(data.start);
                const end = window.MiNoteEditor.Position.fromString(data.end);
                
                if (!start || !end) return null;
                
                return new SelectionRange(start, end);
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '从字符串解析SelectionRange失败', { error: error.message });
                return null;
            }
        }
        
        /**
         * 比较两个选择范围是否相等
         * @param {SelectionRange} other - 另一个SelectionRange对象
         * @returns {boolean} 是否相等
         */
        equals(other) {
            if (!other || !(other instanceof SelectionRange)) return false;
            
            return this.start.equals(other.start) && this.end.equals(other.end);
        }
        
        /**
         * 检查是否包含指定位置
         * @param {Position} position - 要检查的位置
         * @returns {boolean} 是否包含
         */
        contains(position) {
            if (!position || !(position instanceof window.MiNoteEditor.Position)) return false;
            
            const normalized = this.normalize();
            return position.compare(normalized.start) >= 0 && position.compare(normalized.end) <= 0;
        }
        
        /**
         * 获取选择范围内的文本内容
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {string} 文本内容
         */
        getTextContent(editor) {
            if (this.isCollapsed) return '';
            
            try {
                const range = document.createRange();
                const startNode = this.start.getNode(editor);
                const endNode = this.end.getNode(editor);
                
                if (!startNode || !endNode) return '';
                
                if (startNode.nodeType === Node.TEXT_NODE) {
                    const startOffset = Math.min(this.start.offset, startNode.textContent.length);
                    range.setStart(startNode, startOffset);
                } else {
                    const startChildIndex = Math.min(this.start.offset, startNode.childNodes.length);
                    range.setStart(startNode, startChildIndex);
                }
                
                if (endNode.nodeType === Node.TEXT_NODE) {
                    const endOffset = Math.min(this.end.offset, endNode.textContent.length);
                    range.setEnd(endNode, endOffset);
                } else {
                    const endChildIndex = Math.min(this.end.offset, endNode.childNodes.length);
                    range.setEnd(endNode, endChildIndex);
                }
                
                return range.toString();
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '获取选择文本内容失败', { error: error.message });
                return '';
            }
        }
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.SelectionRange = SelectionRange;

})();
