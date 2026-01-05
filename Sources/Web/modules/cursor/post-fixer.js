/**
 * SelectionPostFixer 类
 * 在每次DOM操作后自动修复光标位置，防止光标出现在无效位置
 * 参考 CKEditor 5 的 Selection Post-Fixer 机制
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { CURSOR: 'Cursor' };

    /**
     * SelectionPostFixer 类
     * 修复无效的选择位置
     */
    class SelectionPostFixer {
        /**
         * 构造函数
         * @param {HTMLElement} editor - 编辑器根元素
         */
        constructor(editor) {
            this.editor = editor;
            this.schema = window.CursorSchema || new window.MiNoteEditor.SchemaValidator();
            this.isFixing = false;
        }
        
        /**
         * 修复选择位置
         * @param {Selection} selection - 浏览器Selection对象
         * @returns {boolean} 是否进行了修复
         */
        fix(selection) {
            if (!selection || !selection.rangeCount || this.isFixing) {
                return false;
            }
            
            this.isFixing = true;
            let wasFixed = false;
            
            try {
                const range = selection.getRangeAt(0);
                const position = window.MiNoteEditor.Position.fromDOM(range, this.editor);
                
                if (!position) {
                    this.isFixing = false;
                    return false;
                }
                
                // 验证位置
                const validationResult = this.schema.validate(position, this.editor);
                
                if (validationResult === window.MiNoteEditor.CursorState.INVALID) {
                    // 获取最近的有效位置
                    const validPosition = this.schema.getNearestValidPosition(position, this.editor);
                    
                    // 恢复有效位置
                    if (validPosition && !validPosition.equals(position)) {
                        const validRange = validPosition.toDOMPosition(this.editor);
                        if (validRange) {
                            selection.removeAllRanges();
                            selection.addRange(validRange);
                            wasFixed = true;
                            log.debug(LOG_MODULES.CURSOR, '修复无效光标位置', { 
                                from: position, 
                                to: validPosition 
                            });
                        }
                    }
                }
                
                // 特殊处理：图片元素
                wasFixed = this._fixImageCursor(selection) || wasFixed;
                
                // 特殊处理：列表项
                wasFixed = this._fixListItemCursor(selection) || wasFixed;
                
                // 特殊处理：引用块
                wasFixed = this._fixBlockquoteCursor(selection) || wasFixed;
                
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '修复光标位置失败', { error: error.message });
            } finally {
                this.isFixing = false;
            }
            
            return wasFixed;
        }
        
        /**
         * 修复图片光标位置
         * @param {Selection} selection - 浏览器Selection对象
         * @returns {boolean} 是否进行了修复
         */
        _fixImageCursor(selection) {
            if (!selection.rangeCount) return false;
            
            const range = selection.getRangeAt(0);
            const startContainer = range.startContainer;
            
            // 如果光标在图片内部或紧邻图片，调整到合适位置
            if (startContainer.nodeName === 'IMG' || 
                (startContainer.parentNode && startContainer.parentNode.nodeName === 'IMG')) {
                return this._moveCursorBesideImage(selection, startContainer);
            }
            
            // 检查光标是否在图片的相邻位置
            const node = this._getTextNodeAtCursor(range);
            if (node && node.previousSibling && node.previousSibling.nodeName === 'IMG') {
                // 光标在图片后面，位置正常
                return false;
            }
            
            if (node && node.nextSibling && node.nextSibling.nodeName === 'IMG') {
                // 光标在图片前面，位置正常
                return false;
            }
            
            return false;
        }
        
        /**
         * 将光标移动到图片旁边
         * @param {Selection} selection - 浏览器Selection对象
         * @param {Node} imageNode - 图片节点
         * @returns {boolean} 是否移动成功
         */
        _moveCursorBesideImage(selection, imageNode) {
            try {
                // 尝试将光标移动到图片前面
                const range = document.createRange();
                const parent = imageNode.parentNode;
                
                if (!parent) return false;
                
                // 查找图片在父节点中的索引
                let imageIndex = 0;
                let sibling = imageNode;
                while (sibling.previousSibling) {
                    sibling = sibling.previousSibling;
                    imageIndex++;
                }
                
                // 尝试在图片前面插入光标
                range.setStart(parent, imageIndex);
                range.collapse(true);
                
                selection.removeAllRanges();
                selection.addRange(range);
                
                log.debug(LOG_MODULES.CURSOR, '移动光标到图片旁边', { imageNode: imageNode.nodeName });
                return true;
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '移动光标到图片旁边失败', { error: error.message });
                return false;
            }
        }
        
        /**
         * 修复列表项光标位置
         * @param {Selection} selection - 浏览器Selection对象
         * @returns {boolean} 是否进行了修复
         */
        _fixListItemCursor(selection) {
            if (!selection.rangeCount) return false;
            
            const range = selection.getRangeAt(0);
            const startContainer = range.startContainer;
            
            // 检查是否在列表项中
            let li = startContainer;
            while (li && li.nodeName !== 'LI') {
                li = li.parentNode;
            }
            
            if (li) {
                // 确保光标在列表项文本内容中，不在列表标记上
                return this._ensureCursorInListItemText(selection, li, range);
            }
            
            return false;
        }
        
        /**
         * 确保光标在列表项文本内容中
         * @param {Selection} selection - 浏览器Selection对象
         * @param {Node} li - 列表项节点
         * @param {Range} originalRange - 原始Range对象
         * @returns {boolean} 是否进行了修复
         */
        _ensureCursorInListItemText(selection, li, originalRange) {
            try {
                // 查找列表项中的第一个文本节点
                const walker = document.createTreeWalker(
                    li,
                    NodeFilter.SHOW_TEXT,
                    null
                );
                
                const firstTextNode = walker.nextNode();
                if (!firstTextNode) {
                    // 列表项中没有文本节点，在列表项末尾创建文本节点
                    const textNode = document.createTextNode('');
                    li.appendChild(textNode);
                    
                    const range = document.createRange();
                    range.setStart(textNode, 0);
                    range.collapse(true);
                    
                    selection.removeAllRanges();
                    selection.addRange(range);
                    return true;
                }
                
                // 检查光标是否已经在文本节点中
                const currentNode = originalRange.startContainer;
                if (currentNode.nodeType === Node.TEXT_NODE && li.contains(currentNode)) {
                    // 光标已经在文本节点中，位置正常
                    return false;
                }
                
                // 将光标移动到第一个文本节点的开头
                const range = document.createRange();
                range.setStart(firstTextNode, 0);
                range.collapse(true);
                
                selection.removeAllRanges();
                selection.addRange(range);
                return true;
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '修复列表项光标位置失败', { error: error.message });
                return false;
            }
        }
        
        /**
         * 修复引用块光标位置
         * @param {Selection} selection - 浏览器Selection对象
         * @returns {boolean} 是否进行了修复
         */
        _fixBlockquoteCursor(selection) {
            if (!selection.rangeCount) return false;
            
            const range = selection.getRangeAt(0);
            const startContainer = range.startContainer;
            
            // 检查是否在引用块中
            let blockquote = startContainer;
            while (blockquote && blockquote.nodeName !== 'BLOCKQUOTE') {
                blockquote = blockquote.parentNode;
            }
            
            if (blockquote) {
                // 确保光标在引用内容中
                return this._ensureCursorInBlockquoteContent(selection, blockquote, range);
            }
            
            return false;
        }
        
        /**
         * 确保光标在引用块内容中
         * @param {Selection} selection - 浏览器Selection对象
         * @param {Node} blockquote - 引用块节点
         * @param {Range} originalRange - 原始Range对象
         * @returns {boolean} 是否进行了修复
         */
        _ensureCursorInBlockquoteContent(selection, blockquote, originalRange) {
            try {
                // 查找引用块中的第一个内容元素（P或DIV）
                let contentElement = null;
                const walker = document.createTreeWalker(
                    blockquote,
                    NodeFilter.SHOW_ELEMENT,
                    {
                        acceptNode: function(node) {
                            if (node.nodeName === 'P' || node.nodeName === 'DIV') {
                                return NodeFilter.FILTER_ACCEPT;
                            }
                            return NodeFilter.FILTER_SKIP;
                        }
                    }
                );
                
                contentElement = walker.nextNode();
                
                if (!contentElement) {
                    // 引用块中没有内容元素，创建一个
                    contentElement = document.createElement('p');
                    contentElement.innerHTML = '&nbsp;'; // 添加非空内容
                    blockquote.appendChild(contentElement);
                }
                
                // 查找内容元素中的第一个文本节点
                const textWalker = document.createTreeWalker(
                    contentElement,
                    NodeFilter.SHOW_TEXT,
                    null
                );
                
                const firstTextNode = textWalker.nextNode();
                if (!firstTextNode) {
                    // 内容元素中没有文本节点，创建一个
                    const textNode = document.createTextNode('');
                    contentElement.appendChild(textNode);
                    
                    const range = document.createRange();
                    range.setStart(textNode, 0);
                    range.collapse(true);
                    
                    selection.removeAllRanges();
                    selection.addRange(range);
                    return true;
                }
                
                // 检查光标是否已经在内容元素的文本节点中
                const currentNode = originalRange.startContainer;
                if (currentNode.nodeType === Node.TEXT_NODE && contentElement.contains(currentNode)) {
                    // 光标已经在内容元素的文本节点中，位置正常
                    return false;
                }
                
                // 将光标移动到第一个文本节点的开头
                const range = document.createRange();
                range.setStart(firstTextNode, 0);
                range.collapse(true);
                
                selection.removeAllRanges();
                selection.addRange(range);
                return true;
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '修复引用块光标位置失败', { error: error.message });
                return false;
            }
        }
        
        /**
         * 获取光标位置的文本节点
         * @param {Range} range - Range对象
         * @returns {Node|null} 文本节点
         */
        _getTextNodeAtCursor(range) {
            const container = range.startContainer;
            
            if (container.nodeType === Node.TEXT_NODE) {
                return container;
            }
            
            // 如果是元素节点，尝试获取子文本节点
            if (container.nodeType === Node.ELEMENT_NODE) {
                const offset = range.startOffset;
                if (offset < container.childNodes.length) {
                    const child = container.childNodes[offset];
                    if (child.nodeType === Node.TEXT_NODE) {
                        return child;
                    }
                }
            }
            
            return null;
        }
        
        /**
         * 批量修复（在多个DOM操作后调用）
         * @param {Selection} selection - 浏览器Selection对象
         * @param {Array} operations - DOM操作列表
         * @returns {boolean} 是否进行了修复
         */
        batchFix(selection, operations) {
            if (!operations || operations.length === 0) {
                return this.fix(selection);
            }
            
            let wasFixed = false;
            
            // 对每个操作进行修复
            for (const operation of operations) {
                if (operation.type === 'insert' || operation.type === 'delete') {
                    wasFixed = this.fix(selection) || wasFixed;
                }
            }
            
            return wasFixed;
        }
        
        /**
         * 设置编辑器引用
         * @param {HTMLElement} editor - 编辑器根元素
         */
        setEditor(editor) {
            this.editor = editor;
        }
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.SelectionPostFixer = SelectionPostFixer;

})();
