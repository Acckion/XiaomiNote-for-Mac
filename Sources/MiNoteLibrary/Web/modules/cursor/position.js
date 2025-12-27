/**
 * Position 类
 * 表示编辑器中的光标位置，使用路径和偏移量表示，不依赖DOM节点引用
 * 参考 CKEditor 5 的 Position 对象设计
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { CURSOR: 'Cursor' };

    /**
     * Position 类
     * 表示编辑器中的光标位置
     */
    class Position {
        /**
         * 构造函数
         * @param {Array} path - 节点路径数组，如[0, 1, 2]
         * @param {number} offset - 在文本节点中的偏移量
         * @param {string|null} anchorText - 锚点文本，用于恢复
         */
        constructor(path, offset, anchorText = null) {
            this.path = path;           // 节点路径数组
            this.offset = offset;       // 在文本节点中的偏移量
            this.anchorText = anchorText; // 锚点文本，用于恢复
            this.timestamp = Date.now();
            this._cachedNode = null;
        }
        
        /**
         * 获取对应的DOM节点
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Node|null} DOM节点
         */
        getNode(editor) {
            if (!this._cachedNode) {
                this._cachedNode = getNodeByPath(this.path, editor);
            }
            return this._cachedNode;
        }
        
        /**
         * 验证位置有效性
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {boolean} 是否有效
         */
        isValid(editor) {
            const node = this.getNode(editor);
            if (!node) return false;
            
            // 检查节点类型是否允许光标
            if (window.CursorSchema && window.CursorSchema.disallowedCursorNodes) {
                if (window.CursorSchema.disallowedCursorNodes.includes(node.nodeName)) {
                    return false;
                }
            }
            
            // 检查偏移量是否有效
            if (node.nodeType === Node.TEXT_NODE) {
                return this.offset >= 0 && this.offset <= node.textContent.length;
            }
            
            // 对于元素节点，偏移量表示子节点索引
            return this.offset >= 0 && this.offset <= node.childNodes.length;
        }
        
        /**
         * 转换为DOM位置（Range对象）
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Range|null} DOM Range对象
         */
        toDOMPosition(editor) {
            const node = this.getNode(editor);
            if (!node) return null;
            
            try {
                const range = document.createRange();
                
                if (node.nodeType === Node.TEXT_NODE) {
                    const offset = Math.min(this.offset, node.textContent.length);
                    range.setStart(node, offset);
                    range.collapse(true);
                } else {
                    // 对于元素节点，偏移量表示子节点索引
                    const childIndex = Math.min(this.offset, node.childNodes.length);
                    if (childIndex === node.childNodes.length) {
                        // 如果偏移量等于子节点数量，设置到元素末尾
                        range.setStart(node, childIndex);
                        range.collapse(true);
                    } else {
                        const child = node.childNodes[childIndex];
                        range.setStart(child, 0);
                        range.collapse(true);
                    }
                }
                
                return range;
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '转换为DOM位置失败', { error: error.message });
                return null;
            }
        }
        
        /**
         * 从DOM位置创建Position对象
         * @param {Range} range - DOM Range对象
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position} Position对象
         */
        static fromDOM(range, editor) {
            const startNode = range.startContainer;
            const startOffset = range.startOffset;
            
            // 获取路径
            const path = getNodePath(startNode, editor);
            
            // 获取锚点文本
            let anchorText = null;
            if (startNode.nodeType === Node.TEXT_NODE) {
                const text = startNode.textContent || '';
                const offset = startOffset;
                // 保存光标前 20 个字符和后 20 个字符作为锚点
                const beforeText = text.substring(Math.max(0, offset - 20), offset);
                const afterText = text.substring(offset, Math.min(text.length, offset + 20));
                anchorText = beforeText + '|' + afterText;
            }
            
            return new Position(path, startOffset, anchorText);
        }
        
        /**
         * 从Selection对象创建Position对象
         * @param {Selection} selection - 浏览器Selection对象
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position|null} Position对象
         */
        static fromSelection(selection, editor) {
            if (!selection.rangeCount) return null;
            
            const range = selection.getRangeAt(0);
            return Position.fromDOM(range, editor);
        }
        
        /**
         * 从当前选择创建Position对象
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position|null} Position对象
         */
        static fromCurrentSelection(editor) {
            const selection = window.getSelection();
            return Position.fromSelection(selection, editor);
        }
        
        /**
         * 转换为字符串表示（用于存储）
         * @returns {string} JSON字符串
         */
        toString() {
            return JSON.stringify({
                path: this.path,
                offset: this.offset,
                anchorText: this.anchorText,
                timestamp: this.timestamp
            });
        }
        
        /**
         * 从字符串创建Position对象
         * @param {string} str - JSON字符串
         * @returns {Position} Position对象
         */
        static fromString(str) {
            try {
                const data = JSON.parse(str);
                return new Position(data.path, data.offset, data.anchorText);
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '从字符串解析Position失败', { error: error.message });
                return null;
            }
        }
        
        /**
         * 比较两个位置是否相等
         * @param {Position} other - 另一个Position对象
         * @returns {boolean} 是否相等
         */
        equals(other) {
            if (!other || !(other instanceof Position)) return false;
            
            // 比较路径和偏移量
            if (this.path.length !== other.path.length) return false;
            for (let i = 0; i < this.path.length; i++) {
                if (this.path[i] !== other.path[i]) return false;
            }
            
            return this.offset === other.offset;
        }
        
        /**
         * 比较位置顺序
         * @param {Position} other - 另一个Position对象
         * @returns {number} -1: this < other, 0: 相等, 1: this > other
         */
        compare(other) {
            if (!other || !(other instanceof Position)) return 1;
            
            // 比较路径
            const minLength = Math.min(this.path.length, other.path.length);
            for (let i = 0; i < minLength; i++) {
                if (this.path[i] < other.path[i]) return -1;
                if (this.path[i] > other.path[i]) return 1;
            }
            
            // 路径前缀相同，比较长度
            if (this.path.length < other.path.length) return -1;
            if (this.path.length > other.path.length) return 1;
            
            // 路径完全相同，比较偏移量
            if (this.offset < other.offset) return -1;
            if (this.offset > other.offset) return 1;
            
            return 0;
        }
    }

    /**
     * 获取节点在编辑器中的路径
     * @param {Node} node - 节点
     * @param {HTMLElement} root - 根元素
     * @returns {Array|null} 节点路径
     */
    function getNodePath(node, root) {
        const path = [];
        let current = node;

        while (current && current !== root && current !== document.body) {
            // 计算当前节点在父节点中的索引
            let index = 0;
            let sibling = current;
            while (sibling.previousSibling) {
                sibling = sibling.previousSibling;
                index++;
            }
            path.unshift(index);
            current = current.parentNode;
        }

        return path.length > 0 ? path : null;
    }

    /**
     * 根据路径获取节点
     * @param {Array} path - 节点路径
     * @param {HTMLElement} root - 根元素
     * @returns {Node|null} 节点
     */
    function getNodeByPath(path, root) {
        let current = root;
        
        for (let i = 0; i < path.length; i++) {
            const index = path[i];
            
            if (!current || !current.childNodes || index >= current.childNodes.length) {
                return null;
            }
            
            current = current.childNodes[index];
        }
        
        return current;
    }

    /**
     * 查找文本节点（用于光标位置保存）
     * @param {Node} node - 起始节点
     * @param {number} offset - 偏移量
     * @returns {Node|null} 文本节点
     */
    function findTextNode(node, offset) {
        if (node.nodeType === Node.TEXT_NODE) {
            return node;
        }
        
        // 如果是元素节点，根据偏移量查找子节点
        if (node.nodeType === Node.ELEMENT_NODE && node.childNodes.length > 0) {
            if (offset < node.childNodes.length) {
                const child = node.childNodes[offset];
                if (child.nodeType === Node.TEXT_NODE) {
                    return child;
                }
                // 递归查找
                return findTextNode(child, 0);
            }
        }
        
        return null;
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Position = Position;
    window.MiNoteEditor.getNodePath = getNodePath;
    window.MiNoteEditor.getNodeByPath = getNodeByPath;
    window.MiNoteEditor.findTextNode = findTextNode;

})();
