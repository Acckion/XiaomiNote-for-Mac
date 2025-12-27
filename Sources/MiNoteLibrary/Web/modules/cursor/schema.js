/**
 * SchemaValidator 类
 * 定义允许和不允许光标位置的规则，特殊处理图片、列表、引用块等元素
 * 参考 CKEditor 5 的 Schema 验证机制
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { CURSOR: 'Cursor' };

    /**
     * 光标状态枚举
     */
    const CursorState = {
        STABLE: 'stable',                    // 光标稳定
        NEEDS_NORMALIZATION: 'needs_normalization', // 需要规范化
        INVALID: 'invalid',                  // 无效位置
        RESTORING: 'restoring'               // 正在恢复
    };

    /**
     * SchemaValidator 类
     * 验证光标位置的有效性
     */
    class SchemaValidator {
        constructor() {
            // 允许光标出现的父节点类型
            this.allowedCursorParents = ['P', 'LI', 'BLOCKQUOTE', 'DIV', 'SPAN', 'B', 'I', 'U', 'S', 'STRONG', 'EM'];
            
            // 不允许光标出现的节点类型
            this.disallowedCursorNodes = ['IMG', 'HR', 'BR'];
            
            // 需要特殊处理的节点类型
            this.specialHandlingNodes = ['UL', 'OL', 'BLOCKQUOTE'];
            
            // 默认光标位置（文档开头）
            this.defaultPosition = {
                path: [0, 0],
                offset: 0
            };
        }
        
        /**
         * 验证位置有效性
         * @param {Position} position - 要验证的位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {string} 光标状态
         */
        validate(position, editor) {
            if (!position || !editor) {
                return CursorState.INVALID;
            }
            
            const node = position.getNode(editor);
            if (!node) {
                return CursorState.INVALID;
            }
            
            // 检查节点类型是否允许光标
            if (this.disallowedCursorNodes.includes(node.nodeName)) {
                return CursorState.INVALID;
            }
            
            // 检查父节点类型
            let parent = node.parentNode;
            while (parent && parent !== editor) {
                if (this.specialHandlingNodes.includes(parent.nodeName)) {
                    // 需要特殊处理的节点类型
                    const specialResult = this._validateSpecialNode(position, parent, editor);
                    if (specialResult !== CursorState.STABLE) {
                        return specialResult;
                    }
                }
                parent = parent.parentNode;
            }
            
            // 检查偏移量是否有效
            if (!this._validateOffset(position, node)) {
                return CursorState.NEEDS_NORMALIZATION;
            }
            
            return CursorState.STABLE;
        }
        
        /**
         * 获取最近的有效位置
         * @param {Position} position - 当前位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position} 最近的有效位置
         */
        getNearestValidPosition(position, editor) {
            const node = position.getNode(editor);
            if (!node) {
                return this._getDefaultPosition(editor);
            }
            
            // 如果节点不允许光标，查找相邻的允许节点
            if (this.disallowedCursorNodes.includes(node.nodeName)) {
                return this._findAdjacentValidPosition(node, editor);
            }
            
            // 如果位置无效但节点有效，调整偏移量
            if (!this._validateOffset(position, node)) {
                return this._adjustOffset(position, node, editor);
            }
            
            // 验证特殊节点
            const validationResult = this.validate(position, editor);
            if (validationResult === CursorState.INVALID) {
                return this._findNearestValidInSpecialNode(position, editor);
            }
            
            return position;
        }
        
        /**
         * 验证特殊节点中的位置
         * @param {Position} position - 要验证的位置
         * @param {Node} specialNode - 特殊节点
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {string} 光标状态
         */
        _validateSpecialNode(position, specialNode, editor) {
            switch (specialNode.nodeName) {
                case 'UL':
                case 'OL':
                    // 在列表中的位置必须是在LI元素内
                    return this._validateInListItem(position, specialNode, editor);
                case 'BLOCKQUOTE':
                    // 在引用块中的位置必须是在内容元素内
                    return this._validateInBlockquote(position, specialNode, editor);
                default:
                    return CursorState.STABLE;
            }
        }
        
        /**
         * 验证列表项中的位置
         * @param {Position} position - 要验证的位置
         * @param {Node} listNode - 列表节点（UL或OL）
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {string} 光标状态
         */
        _validateInListItem(position, listNode, editor) {
            const node = position.getNode(editor);
            if (!node) return CursorState.INVALID;
            
            // 检查是否在LI元素内
            let current = node;
            while (current && current !== listNode) {
                if (current.nodeName === 'LI') {
                    return CursorState.STABLE;
                }
                current = current.parentNode;
            }
            
            // 不在LI元素内，需要规范化
            return CursorState.NEEDS_NORMALIZATION;
        }
        
        /**
         * 验证引用块中的位置
         * @param {Position} position - 要验证的位置
         * @param {Node} blockquoteNode - 引用块节点
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {string} 光标状态
         */
        _validateInBlockquote(position, blockquoteNode, editor) {
            const node = position.getNode(editor);
            if (!node) return CursorState.INVALID;
            
            // 检查是否在引用块的内容元素内（通常是P或DIV）
            let current = node;
            while (current && current !== blockquoteNode) {
                if (current.nodeName === 'P' || current.nodeName === 'DIV') {
                    return CursorState.STABLE;
                }
                current = current.parentNode;
            }
            
            // 不在内容元素内，需要规范化
            return CursorState.NEEDS_NORMALIZATION;
        }
        
        /**
         * 验证偏移量是否有效
         * @param {Position} position - 要验证的位置
         * @param {Node} node - 节点
         * @returns {boolean} 偏移量是否有效
         */
        _validateOffset(position, node) {
            if (node.nodeType === Node.TEXT_NODE) {
                return position.offset >= 0 && position.offset <= node.textContent.length;
            }
            
            // 对于元素节点，偏移量表示子节点索引
            return position.offset >= 0 && position.offset <= node.childNodes.length;
        }
        
        /**
         * 调整偏移量到有效范围
         * @param {Position} position - 当前位置
         * @param {Node} node - 节点
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position} 调整后的位置
         */
        _adjustOffset(position, node, editor) {
            if (node.nodeType === Node.TEXT_NODE) {
                const maxOffset = node.textContent.length;
                const newOffset = Math.max(0, Math.min(position.offset, maxOffset));
                return new window.MiNoteEditor.Position(position.path, newOffset, position.anchorText);
            }
            
            // 对于元素节点
            const maxOffset = node.childNodes.length;
            const newOffset = Math.max(0, Math.min(position.offset, maxOffset));
            return new window.MiNoteEditor.Position(position.path, newOffset, position.anchorText);
        }
        
        /**
         * 查找相邻的有效位置
         * @param {Node} invalidNode - 无效节点
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position} 相邻的有效位置
         */
        _findAdjacentValidPosition(invalidNode, editor) {
            // 尝试在前面的兄弟节点中查找
            let sibling = invalidNode.previousSibling;
            while (sibling) {
                if (sibling.nodeType === Node.TEXT_NODE || 
                    !this.disallowedCursorNodes.includes(sibling.nodeName)) {
                    const path = window.MiNoteEditor.getNodePath(sibling, editor);
                    if (path) {
                        return new window.MiNoteEditor.Position(path, 0);
                    }
                }
                sibling = sibling.previousSibling;
            }
            
            // 尝试在后面的兄弟节点中查找
            sibling = invalidNode.nextSibling;
            while (sibling) {
                if (sibling.nodeType === Node.TEXT_NODE || 
                    !this.disallowedCursorNodes.includes(sibling.nodeName)) {
                    const path = window.MiNoteEditor.getNodePath(sibling, editor);
                    if (path) {
                        return new window.MiNoteEditor.Position(path, 0);
                    }
                }
                sibling = sibling.nextSibling;
            }
            
            // 如果找不到相邻的有效节点，返回默认位置
            return this._getDefaultPosition(editor);
        }
        
        /**
         * 在特殊节点中查找最近的有效位置
         * @param {Position} position - 当前位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position} 最近的有效位置
         */
        _findNearestValidInSpecialNode(position, editor) {
            const node = position.getNode(editor);
            if (!node) return this._getDefaultPosition(editor);
            
            // 检查是否在列表中
            let listNode = node;
            while (listNode && listNode.nodeName !== 'UL' && listNode.nodeName !== 'OL') {
                listNode = listNode.parentNode;
                if (!listNode || listNode === editor) break;
            }
            
            if (listNode && (listNode.nodeName === 'UL' || listNode.nodeName === 'OL')) {
                // 在列表中，查找最近的LI元素
                const li = this._findNearestListItem(node, listNode);
                if (li) {
                    const path = window.MiNoteEditor.getNodePath(li, editor);
                    if (path) {
                        return new window.MiNoteEditor.Position(path, 0);
                    }
                }
            }
            
            // 检查是否在引用块中
            let blockquoteNode = node;
            while (blockquoteNode && blockquoteNode.nodeName !== 'BLOCKQUOTE') {
                blockquoteNode = blockquoteNode.parentNode;
                if (!blockquoteNode || blockquoteNode === editor) break;
            }
            
            if (blockquoteNode && blockquoteNode.nodeName === 'BLOCKQUOTE') {
                // 在引用块中，查找最近的内容元素
                const contentElement = this._findNearestContentElement(node, blockquoteNode);
                if (contentElement) {
                    const path = window.MiNoteEditor.getNodePath(contentElement, editor);
                    if (path) {
                        return new window.MiNoteEditor.Position(path, 0);
                    }
                }
            }
            
            return this._getDefaultPosition(editor);
        }
        
        /**
         * 查找最近的列表项
         * @param {Node} node - 起始节点
         * @param {Node} listNode - 列表节点
         * @returns {Node|null} 最近的LI元素
         */
        _findNearestListItem(node, listNode) {
            // 向上查找
            let current = node;
            while (current && current !== listNode) {
                if (current.nodeName === 'LI') {
                    return current;
                }
                current = current.parentNode;
            }
            
            // 向下查找（在列表的第一个子元素中查找）
            if (listNode.firstChild) {
                const firstLI = this._findFirstLI(listNode);
                if (firstLI) return firstLI;
            }
            
            return null;
        }
        
        /**
         * 查找第一个LI元素
         * @param {Node} listNode - 列表节点
         * @returns {Node|null} 第一个LI元素
         */
        _findFirstLI(listNode) {
            for (let i = 0; i < listNode.childNodes.length; i++) {
                const child = listNode.childNodes[i];
                if (child.nodeName === 'LI') {
                    return child;
                }
                // 递归查找
                const li = this._findFirstLI(child);
                if (li) return li;
            }
            return null;
        }
        
        /**
         * 查找最近的内容元素
         * @param {Node} node - 起始节点
         * @param {Node} blockquoteNode - 引用块节点
         * @returns {Node|null} 最近的内容元素
         */
        _findNearestContentElement(node, blockquoteNode) {
            // 向上查找
            let current = node;
            while (current && current !== blockquoteNode) {
                if (current.nodeName === 'P' || current.nodeName === 'DIV') {
                    return current;
                }
                current = current.parentNode;
            }
            
            // 向下查找（在引用块的第一个子元素中查找）
            if (blockquoteNode.firstChild) {
                const firstContent = this._findFirstContentElement(blockquoteNode);
                if (firstContent) return firstContent;
            }
            
            return null;
        }
        
        /**
         * 查找第一个内容元素
         * @param {Node} blockquoteNode - 引用块节点
         * @returns {Node|null} 第一个内容元素
         */
        _findFirstContentElement(blockquoteNode) {
            for (let i = 0; i < blockquoteNode.childNodes.length; i++) {
                const child = blockquoteNode.childNodes[i];
                if (child.nodeName === 'P' || child.nodeName === 'DIV') {
                    return child;
                }
                // 递归查找
                const content = this._findFirstContentElement(child);
                if (content) return content;
            }
            return null;
        }
        
        /**
         * 获取默认位置（文档开头）
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position} 默认位置
         */
        _getDefaultPosition(editor) {
            // 查找编辑器的第一个文本节点
            const walker = document.createTreeWalker(
                editor,
                NodeFilter.SHOW_TEXT,
                null
            );
            
            const firstTextNode = walker.nextNode();
            if (firstTextNode) {
                const path = window.MiNoteEditor.getNodePath(firstTextNode, editor);
                if (path) {
                    return new window.MiNoteEditor.Position(path, 0);
                }
            }
            
            // 如果没有文本节点，使用编辑器本身
            const path = window.MiNoteEditor.getNodePath(editor, editor);
            return new window.MiNoteEditor.Position(path || [0], 0);
        }
        
        /**
         * 检查节点是否允许光标
         * @param {Node} node - 要检查的节点
         * @returns {boolean} 是否允许光标
         */
        isNodeAllowedForCursor(node) {
            if (!node) return false;
            
            // 文本节点总是允许光标
            if (node.nodeType === Node.TEXT_NODE) return true;
            
            // 检查节点类型
            if (this.disallowedCursorNodes.includes(node.nodeName)) {
                return false;
            }
            
            return true;
        }
        
        /**
         * 检查父节点是否允许光标
         * @param {Node} node - 要检查的节点
         * @returns {boolean} 父节点是否允许光标
         */
        isParentAllowedForCursor(node) {
            if (!node || !node.parentNode) return true;
            
            const parent = node.parentNode;
            return this.allowedCursorParents.includes(parent.nodeName);
        }
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.SchemaValidator = SchemaValidator;
    window.MiNoteEditor.CursorState = CursorState;
    window.CursorSchema = new SchemaValidator();

})();
