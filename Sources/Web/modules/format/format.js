/**
 * Format 模块
 * 提供所有格式相关的功能（文本格式、标题、列表、对齐、缩进等）
 * 依赖: logger, constants, utils, dom-writer, editor-core
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { FORMAT: 'Format', EDITOR: 'Editor', IMAGE: 'Image' };
    const getIndentFromElement = window.getIndentFromElement || (window.MiNoteEditor && window.MiNoteEditor.Utils && window.MiNoteEditor.Utils.getIndentFromElement);
    const setIndentForElement = window.setIndentForElement || (window.MiNoteEditor && window.MiNoteEditor.Utils && window.MiNoteEditor.Utils.setIndentForElement);

    // 获取全局变量和函数
    const getDomWriter = () => window.domWriter;
    const getNotifyContentChanged = () => {
        return (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.notifyContentChanged) ||
               (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged) ||
               window.notifyContentChanged;
    };
    const getSyncFormatState = () => {
        return (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.syncFormatState) ||
               (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.syncFormatState) ||
               window.syncFormatState;
    };

    // ==================== Format 功能 ====================
    
    /**
     * Format 管理器
     * 包含所有格式相关的功能
     */
    const FormatManager = {
        /**
         * 应用文本格式（加粗、斜体、下划线、删除线、高亮）
         * @param {string} format - 格式类型
         * @returns {string} 状态信息
         */
        applyFormat: function(format) {
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选中文本';
            }

            const range = selection.getRangeAt(0);
            
            try {
                // 检查当前格式状态
                const isCurrentlyFormatted = this._checkFormatStateInternal(range, format);
                
                let tagName = '';
                let className = '';
                
                switch (format) {
                    case 'bold':
                        tagName = 'b';
                        break;
                    case 'italic':
                        tagName = 'i';
                        break;
                    case 'underline':
                        tagName = 'u';
                        break;
                    case 'strikethrough':
                        tagName = 's';
                        break;
                    case 'highlight':
                        className = 'mi-note-highlight';
                        break;
                }

                if (range.collapsed) {
                    // 光标位置：切换格式
                    if (isCurrentlyFormatted) {
                        this.clearFormatAtCursor(range, format, tagName, className);
                    } else {
                        // 应用格式
                        const domWriter = getDomWriter();
                        if (tagName) {
                            if (format === 'underline' || format === 'strikethrough') {
                                const otherFormat = format === 'underline' ? 'strikethrough' : 'underline';
                                const hasOtherFormat = this._checkFormatStateInternal(range, otherFormat);
                                
                                if (hasOtherFormat) {
                                    let container = range.commonAncestorContainer;
                                    if (container.nodeType === Node.TEXT_NODE) {
                                        container = container.parentElement;
                                    }
                                    
                                    let otherFormatElement = null;
                                    let current = container;
                                    const otherTagName = format === 'underline' ? 's' : 'u';
                                    
                                    while (current && current !== document.body) {
                                        if (current.nodeType === Node.ELEMENT_NODE) {
                                            const tag = current.tagName ? current.tagName.toLowerCase() : '';
                                            if (tag === otherTagName || 
                                                (otherTagName === 's' && (tag === 'strike' || tag === 'del'))) {
                                                otherFormatElement = current;
                                                break;
                                            }
                                        }
                                        current = current.parentElement || current.parentNode;
                                    }
                                    
                                    if (otherFormatElement) {
                                        const newFormatElement = document.createElement(tagName);
                                        newFormatElement.innerHTML = '\u200B';
                                        
                                        if (otherFormatElement.firstChild) {
                                            otherFormatElement.insertBefore(newFormatElement, otherFormatElement.firstChild);
                                        } else {
                                            otherFormatElement.appendChild(newFormatElement);
                                        }
                                        
                                        const newRange = document.createRange();
                                        newRange.setStart(newFormatElement.firstChild, 0);
                                        newRange.collapse(true);
                                        selection.removeAllRanges();
                                        selection.addRange(newRange);
                                    } else {
                                        if (domWriter) {
                                            domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                        } else {
                                            document.execCommand(format, false, null);
                                        }
                                    }
                                } else {
                                    if (domWriter) {
                                        domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                    } else {
                                        document.execCommand(format, false, null);
                                    }
                                }
                            } else {
                                if (domWriter) {
                                    domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                } else {
                                    document.execCommand(format, false, null);
                                }
                            }
                        } else if (className) {
                            const highlightSpan = document.createElement('span');
                            highlightSpan.className = className;
                            highlightSpan.style.backgroundColor = 'rgba(154, 255, 232, 0.69)';
                            highlightSpan.innerHTML = '\u200B';
                            
                            range.insertNode(highlightSpan);
                            
                            const newRange = document.createRange();
                            newRange.setStart(highlightSpan, 0);
                            newRange.collapse(true);
                            selection.removeAllRanges();
                            selection.addRange(newRange);
                        }
                    }
                } else {
                    // 有选中文本：切换格式
                    if (isCurrentlyFormatted) {
                        this.removeFormatFromSelection(range, format, tagName, className);
                    } else {
                        const domWriter = getDomWriter();
                        if (tagName) {
                            if (format === 'underline' || format === 'strikethrough') {
                                const otherFormat = format === 'underline' ? 'strikethrough' : 'underline';
                                const hasOtherFormat = this._checkFormatStateInternal(range, otherFormat);
                                
                                if (hasOtherFormat) {
                                    const selectedText = range.extractContents();
                                    const newFormatElement = document.createElement(tagName);
                                    
                                    let container = range.commonAncestorContainer;
                                    if (container.nodeType === Node.TEXT_NODE) {
                                        container = container.parentElement;
                                    }
                                    
                                    let otherFormatElement = null;
                                    let current = container;
                                    const otherTagName = format === 'underline' ? 's' : 'u';
                                    
                                    while (current && current !== document.body) {
                                        if (current.nodeType === Node.ELEMENT_NODE) {
                                            const tag = current.tagName ? current.tagName.toLowerCase() : '';
                                            if (tag === otherTagName || 
                                                (otherTagName === 's' && (tag === 'strike' || tag === 'del'))) {
                                                otherFormatElement = current;
                                                break;
                                            }
                                        }
                                        current = current.parentElement || current.parentNode;
                                    }
                                    
                                    if (otherFormatElement) {
                                        newFormatElement.appendChild(selectedText);
                                        otherFormatElement.appendChild(newFormatElement);
                                        
                                        const newRange = document.createRange();
                                        newRange.selectNodeContents(newFormatElement);
                                        selection.removeAllRanges();
                                        selection.addRange(newRange);
                                    } else {
                                        range.insertNode(selectedText);
                                        if (domWriter) {
                                            domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                        } else {
                                            document.execCommand(format, false, null);
                                        }
                                    }
                                } else {
                                    if (domWriter) {
                                        domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                    } else {
                                        document.execCommand(format, false, null);
                                    }
                                }
                            } else {
                                if (domWriter) {
                                    domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                } else {
                                    document.execCommand(format, false, null);
                                }
                            }
                        } else if (className) {
                            const selectedText = range.toString();
                            const highlightSpan = document.createElement('span');
                            highlightSpan.className = className;
                            highlightSpan.style.backgroundColor = 'rgba(154, 255, 232, 0.69)';
                            highlightSpan.textContent = selectedText;
                            range.deleteContents();
                            range.insertNode(highlightSpan);
                            
                            selection.removeAllRanges();
                            const newRange = document.createRange();
                            newRange.selectNodeContents(highlightSpan);
                            selection.addRange(newRange);
                        }
                    }
                }

                const notifyContentChanged = getNotifyContentChanged();
                const syncFormatState = getSyncFormatState();
                if (notifyContentChanged) {
                    notifyContentChanged();
                }
                requestAnimationFrame(() => {
                    if (!window.isComposing && !window.isLoadingContent) {
                        if (syncFormatState) {
                            syncFormatState();
                        }
                    }
                });
                return format + ' 格式已' + (isCurrentlyFormatted ? '清除' : '应用');
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '应用格式失败', { format, error: error.message });
                return '应用格式失败: ' + error.message;
            }
        },

        /**
         * 检查当前格式状态（供外部调用）
         * @param {Range} range - 选择范围（可选，如果不提供则使用当前选择）
         * @param {string} format - 格式类型
         * @returns {boolean} 是否已应用格式
         */
        checkFormatState: function(range, format) {
            if (!range) {
                const selection = window.getSelection();
                if (!selection.rangeCount) {
                    return false;
                }
                range = selection.getRangeAt(0);
            }
            
            return this._checkFormatStateInternal(range, format);
        },

        /**
         * 内部方法：检查当前格式状态
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @returns {boolean} 是否已应用格式
         */
        _checkFormatStateInternal: function(range, format) {
            let tagName = '';
            let className = '';
            
            switch (format) {
                case 'bold':
                    tagName = 'b';
                    break;
                case 'italic':
                    tagName = 'i';
                    break;
                case 'underline':
                    tagName = 'u';
                    break;
                case 'strikethrough':
                    tagName = 's';
                    break;
                case 'highlight':
                    className = 'mi-note-highlight';
                    break;
            }

            try {
                if (tagName) {
                    const state = document.queryCommandState(format);
                    if (state !== undefined && state !== null) {
                        return Boolean(state);
                    }
                }
            } catch (e) {
                // queryCommandState 可能不支持某些格式，继续使用 DOM 检查
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }

            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName ? current.tagName.toLowerCase() : '';
                    if (tagName) {
                        if (tag === tagName || 
                            (tag === 'strong' && tagName === 'b') || 
                            (tag === 'em' && tagName === 'i') ||
                            (tag === 'strike' && tagName === 's') ||
                            (tag === 'del' && tagName === 's')) {
                            return true;
                        }
                    }
                    if (className && current.classList && current.classList.contains(className)) {
                        return true;
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            if (!range.collapsed) {
                try {
                    const contents = range.cloneContents();
                    if (tagName) {
                        const formatElements = contents.querySelectorAll(
                            tagName + ', strong, em, strike, del, s'
                        );
                        if (formatElements.length > 0) {
                            const allTextInFormat = Array.from(formatElements).some(el => {
                                const elText = el.textContent || '';
                                const rangeText = range.toString();
                                return elText.includes(rangeText) || rangeText.includes(elText);
                            });
                            if (allTextInFormat) {
                                return true;
                            }
                        }
                    }
                    if (className) {
                        const formatElements = contents.querySelectorAll('.' + className);
                        if (formatElements.length > 0) {
                            return true;
                        }
                    }
                } catch (e) {
                    // 忽略错误
                }
            }

            return false;
        },

        /**
         * 清除光标位置的格式
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @param {string} tagName - 标签名
         * @param {string} className - 类名
         */
        clearFormatAtCursor: function(range, format, tagName, className) {
            const selection = window.getSelection();
            const domWriter = getDomWriter();
            
            if (tagName && !className) {
                try {
                    const isFormatted = document.queryCommandState(format);
                    if (isFormatted) {
                        let container = range.commonAncestorContainer;
                        let formatElement = null;
                        let isAtEnd = false;
                        
                        let current = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
                        while (current && current !== document.body) {
                            if (current.nodeType === Node.ELEMENT_NODE) {
                                const tag = current.tagName ? current.tagName.toLowerCase() : '';
                                if (tagName && (
                                    tag === tagName || 
                                    (tag === 'strong' && tagName === 'b') || 
                                    (tag === 'em' && tagName === 'i') ||
                                    (tag === 'strike' && tagName === 's') ||
                                    (tag === 'del' && tagName === 's')
                                )) {
                                    formatElement = current;
                                    if (container.nodeType === Node.TEXT_NODE) {
                                        const textNode = container;
                                        const lastTextNode = this.getLastTextNode(formatElement);
                                        if (textNode === lastTextNode && range.startOffset === textNode.textContent.length) {
                                            isAtEnd = true;
                                        }
                                    }
                                    break;
                                }
                            }
                            current = current.parentElement || current.parentNode;
                        }
                        
                        if (isAtEnd && formatElement) {
                            const parent = formatElement.parentElement;
                            if (parent) {
                                let nextTextNode = formatElement.nextSibling;
                                while (nextTextNode && nextTextNode.nodeType !== Node.TEXT_NODE) {
                                    if (nextTextNode.nodeType === Node.ELEMENT_NODE) {
                                        const walker = document.createTreeWalker(
                                            nextTextNode,
                                            NodeFilter.SHOW_TEXT,
                                            null
                                        );
                                        const firstText = walker.nextNode();
                                        if (firstText) {
                                            nextTextNode = firstText;
                                            break;
                                        }
                                    }
                                    nextTextNode = nextTextNode.nextSibling;
                                }
                                
                                if (!nextTextNode || nextTextNode.nodeType !== Node.TEXT_NODE) {
                                    nextTextNode = document.createTextNode('');
                                    if (formatElement.nextSibling) {
                                        parent.insertBefore(nextTextNode, formatElement.nextSibling);
                                    } else {
                                        parent.appendChild(nextTextNode);
                                    }
                                }
                                
                                const newRange = document.createRange();
                                newRange.setStart(nextTextNode, 0);
                                newRange.collapse(true);
                                selection.removeAllRanges();
                                selection.addRange(newRange);
                                
                                if (domWriter) {
                                    domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                } else {
                                    document.execCommand(format, false, null);
                                }
                                return;
                            }
                        }
                        
                        if (domWriter) {
                            domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                        } else {
                            document.execCommand(format, false, null);
                        }
                        
                        const stillFormatted = document.queryCommandState(format);
                        if (!stillFormatted) {
                            return;
                        }
                    }
                } catch (e) {
                    log.warn(LOG_MODULES.FORMAT, 'execCommand 清除格式失败，使用手动方法', { error: e.message });
                }
            }
            
            // 手动清除格式（当 execCommand 不可用或失败时，或自定义格式如高亮）
            let container = range.commonAncestorContainer;
            let formatElement = null;
            
            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName ? current.tagName.toLowerCase() : '';
                    if (tagName) {
                        if (tag === tagName || 
                            (tag === 'strong' && tagName === 'b') || 
                            (tag === 'em' && tagName === 'i') ||
                            (tag === 'strike' && tagName === 's') ||
                            (tag === 'del' && tagName === 's')) {
                            formatElement = current;
                            break;
                        }
                    }
                    if (className && current.classList && current.classList.contains(className)) {
                        formatElement = current;
                        break;
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            if (formatElement) {
                const parent = formatElement.parentElement;
                if (!parent) {
                    if (tagName) {
                        try {
                            if (domWriter) {
                                domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                            } else {
                                document.execCommand(format, false, null);
                            }
                        } catch (e) {
                            log.warn(LOG_MODULES.FORMAT, 'execCommand 清除格式失败', { format, error: e.message });
                        }
                    }
                    return;
                }

                let cursorIsAtEnd = false;
                if (container.nodeType === Node.TEXT_NODE) {
                    const textNode = container;
                    const lastTextNode = this.getLastTextNode(formatElement);
                    if (textNode === lastTextNode && range.startOffset === textNode.textContent.length) {
                        cursorIsAtEnd = true;
                    }
                }

                if (className) {
                    if (cursorIsAtEnd) {
                        let nextTextNode = formatElement.nextSibling;
                        while (nextTextNode && nextTextNode.nodeType !== Node.TEXT_NODE) {
                            if (nextTextNode.nodeType === Node.ELEMENT_NODE) {
                                const walker = document.createTreeWalker(
                                    nextTextNode,
                                    NodeFilter.SHOW_TEXT,
                                    null
                                );
                                const firstText = walker.nextNode();
                                if (firstText) {
                                    nextTextNode = firstText;
                                    break;
                                }
                            }
                            nextTextNode = nextTextNode.nextSibling;
                        }
                        
                        if (!nextTextNode || nextTextNode.nodeType !== Node.TEXT_NODE) {
                            nextTextNode = document.createTextNode('');
                            if (formatElement.nextSibling) {
                                parent.insertBefore(nextTextNode, formatElement.nextSibling);
                            } else {
                                parent.appendChild(nextTextNode);
                            }
                        }
                        
                        const newRange = document.createRange();
                        newRange.setStart(nextTextNode, 0);
                        newRange.collapse(true);
                        selection.removeAllRanges();
                        selection.addRange(newRange);
                        
                        const currentContainer = newRange.commonAncestorContainer;
                        let currentParent = currentContainer.nodeType === Node.TEXT_NODE ? currentContainer.parentElement : currentContainer;
                        let stillInHighlight = false;
                        while (currentParent && currentParent !== document.body) {
                            if (currentParent.classList && currentParent.classList.contains(className)) {
                                stillInHighlight = true;
                                break;
                            }
                            currentParent = currentParent.parentElement || currentParent.parentNode;
                        }
                        
                        if (stillInHighlight) {
                            const fragment = document.createDocumentFragment();
                            while (formatElement.firstChild) {
                                fragment.appendChild(formatElement.firstChild);
                            }
                            
                            if (formatElement.nextSibling) {
                                parent.insertBefore(fragment, formatElement.nextSibling);
                            } else {
                                parent.appendChild(fragment);
                            }
                            
                            parent.removeChild(formatElement);
                            
                            if (fragment.childNodes.length > 0) {
                                const lastNode = fragment.lastChild;
                                if (lastNode.nodeType === Node.TEXT_NODE) {
                                    const finalRange = document.createRange();
                                    finalRange.setStart(lastNode, lastNode.textContent.length);
                                    finalRange.collapse(true);
                                    selection.removeAllRanges();
                                    selection.addRange(finalRange);
                                } else {
                                    const lastTextNode = this.getLastTextNode(fragment);
                                    if (lastTextNode) {
                                        const finalRange = document.createRange();
                                        finalRange.setStart(lastTextNode, lastTextNode.textContent.length);
                                        finalRange.collapse(true);
                                        selection.removeAllRanges();
                                        selection.addRange(finalRange);
                                    }
                                }
                            } else {
                                const newTextNode = document.createTextNode('');
                                if (formatElement.nextSibling) {
                                    parent.insertBefore(newTextNode, formatElement.nextSibling);
                                } else {
                                    parent.appendChild(newTextNode);
                                }
                                const finalRange = document.createRange();
                                finalRange.setStart(newTextNode, 0);
                                finalRange.collapse(true);
                                selection.removeAllRanges();
                                selection.addRange(finalRange);
                            }
                        }
                        
                        return;
                    } else {
                        const fragment = document.createDocumentFragment();
                        while (formatElement.firstChild) {
                            fragment.appendChild(formatElement.firstChild);
                        }
                        
                        if (formatElement.nextSibling) {
                            parent.insertBefore(fragment, formatElement.nextSibling);
                        } else {
                            parent.appendChild(fragment);
                        }
                        
                        parent.removeChild(formatElement);
                        
                        if (fragment.childNodes.length > 0) {
                            const lastNode = fragment.lastChild;
                            if (lastNode.nodeType === Node.TEXT_NODE) {
                                const newRange = document.createRange();
                                newRange.setStart(lastNode, lastNode.textContent.length);
                                newRange.collapse(true);
                                selection.removeAllRanges();
                                selection.addRange(newRange);
                            } else {
                                const lastTextNode = this.getLastTextNode(fragment);
                                if (lastTextNode) {
                                    const newRange = document.createRange();
                                    newRange.setStart(lastTextNode, lastTextNode.textContent.length);
                                    newRange.collapse(true);
                                    selection.removeAllRanges();
                                    selection.addRange(newRange);
                                }
                            }
                        } else {
                            const newTextNode = document.createTextNode('');
                            if (formatElement.nextSibling) {
                                parent.insertBefore(newTextNode, formatElement.nextSibling);
                            } else {
                                parent.appendChild(newTextNode);
                            }
                            const newRange = document.createRange();
                            newRange.setStart(newTextNode, 0);
                            newRange.collapse(true);
                            selection.removeAllRanges();
                            selection.addRange(newRange);
                        }
                        return;
                    }
                }

                let nextTextNode = null;
                let nextSibling = formatElement.nextSibling;
                
                while (nextSibling) {
                    if (nextSibling.nodeType === Node.TEXT_NODE) {
                        nextTextNode = nextSibling;
                        break;
                    } else if (nextSibling.nodeType === Node.ELEMENT_NODE) {
                        const walker = document.createTreeWalker(
                            nextSibling,
                            NodeFilter.SHOW_TEXT,
                            null
                        );
                        const firstText = walker.nextNode();
                        if (firstText) {
                            nextTextNode = firstText;
                            break;
                        }
                    }
                    nextSibling = nextSibling.nextSibling;
                }
                
                if (nextTextNode) {
                    const newRange = document.createRange();
                    newRange.setStart(nextTextNode, 0);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                } else {
                    const newTextNode = document.createTextNode('');
                    if (formatElement.nextSibling) {
                        parent.insertBefore(newTextNode, formatElement.nextSibling);
                    } else {
                        parent.appendChild(newTextNode);
                    }
                    
                    const newRange = document.createRange();
                    newRange.setStart(newTextNode, 0);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                }
            } else {
                if (tagName) {
                    try {
                        if (domWriter) {
                            domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                        } else {
                            document.execCommand(format, false, null);
                        }
                    } catch (e) {
                        log.warn(LOG_MODULES.FORMAT, 'execCommand 清除格式失败', { format, error: e.message });
                    }
                }
            }
        },

        /**
         * 从选中文本中移除格式
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @param {string} tagName - 标签名
         * @param {string} className - 类名
         */
        removeFormatFromSelection: function(range, format, tagName, className) {
            const selection = window.getSelection();
            const domWriter = getDomWriter();
            
            if (tagName && !className) {
                try {
                    if (domWriter) {
                        domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                    } else {
                        document.execCommand(format, false, null);
                    }
                    return;
                } catch (e) {
                    log.warn(LOG_MODULES.FORMAT, 'execCommand 失败，使用手动方法', { error: e.message });
                }
            }
            
            try {
                const contents = range.extractContents();
                const walker = document.createTreeWalker(
                    contents,
                    NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT,
                    null
                );

                const fragment = document.createDocumentFragment();
                let node = walker.nextNode();
                while (node) {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        const tag = node.tagName ? node.tagName.toLowerCase() : '';
                        const nodeClassName = node.className || '';
                        if (tagName && (
                            tag === tagName || 
                            (tag === 'strong' && tagName === 'b') || 
                            (tag === 'em' && tagName === 'i') ||
                            (tag === 'strike' && tagName === 's') ||
                            (tag === 'del' && tagName === 's')
                        )) {
                            while (node.firstChild) {
                                fragment.appendChild(node.firstChild);
                            }
                        } else if (className && node.classList && node.classList.contains(className)) {
                            while (node.firstChild) {
                                fragment.appendChild(node.firstChild);
                            }
                        } else {
                            const clonedNode = node.cloneNode(false);
                            const childFragment = document.createDocumentFragment();
                            let childNode = walker.nextNode();
                            while (childNode && childNode.parentNode === node) {
                                if (childNode.nodeType === Node.TEXT_NODE) {
                                    childFragment.appendChild(childNode.cloneNode(true));
                                } else if (childNode.nodeType === Node.ELEMENT_NODE) {
                                    const childTag = childNode.tagName ? childNode.tagName.toLowerCase() : '';
                                    if (tagName && (
                                        childTag === tagName || 
                                        (childTag === 'strong' && tagName === 'b') || 
                                        (childTag === 'em' && tagName === 'i')
                                    )) {
                                        while (childNode.firstChild) {
                                            childFragment.appendChild(childNode.firstChild);
                                        }
                                    } else {
                                        childFragment.appendChild(childNode.cloneNode(true));
                                    }
                                }
                                childNode = walker.nextNode();
                            }
                            clonedNode.appendChild(childFragment);
                            fragment.appendChild(clonedNode);
                        }
                    } else {
                        fragment.appendChild(node.cloneNode(true));
                    }
                    node = walker.nextNode();
                }

                range.deleteContents();
                range.insertNode(fragment);
                
                selection.removeAllRanges();
                const newRange = document.createRange();
                newRange.setStartBefore(fragment);
                newRange.setEndAfter(fragment);
                selection.addRange(newRange);
            } catch (e) {
                log.error(LOG_MODULES.FORMAT, '手动移除格式失败', { error: e.message });
            }
        },

        /**
         * 获取元素的最后一个文本节点
         * @param {Node} element - 元素
         * @returns {Node|null} 最后一个文本节点
         */
        getLastTextNode: function(element) {
            if (!element) return null;
            
            const walker = document.createTreeWalker(
                element,
                NodeFilter.SHOW_TEXT,
                null
            );
            
            let lastTextNode = null;
            let node = walker.nextNode();
            while (node) {
                lastTextNode = node;
                node = walker.nextNode();
            }
            
            return lastTextNode;
        },

        /**
         * 确保光标不在格式元素内（应用格式前调用）
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @param {string} tagName - 标签名
         * @param {string} className - 类名
         */
        ensureCursorOutsideFormatElements: function(range, format, tagName, className) {
            if (tagName && ['bold', 'italic', 'underline', 'strikethrough'].includes(format)) {
                return;
            }
            
            const selection = window.getSelection();
            let container = range.commonAncestorContainer;
            let formatElement = null;
            
            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName ? current.tagName.toLowerCase() : '';
                    const hasClass = current.classList || false;
                    
                    const isFormatElement = 
                        tag === 'b' || tag === 'strong' ||
                        tag === 'i' || tag === 'em' ||
                        tag === 'u' ||
                        tag === 's' || tag === 'strike' || tag === 'del' ||
                        (hasClass && current.classList.contains('mi-note-highlight'));
                    
                    if (isFormatElement) {
                        formatElement = current;
                        break;
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            if (formatElement) {
                const parent = formatElement.parentElement;
                if (parent) {
                    const textNode = document.createTextNode('');
                    if (formatElement.nextSibling) {
                        parent.insertBefore(textNode, formatElement.nextSibling);
                    } else {
                        parent.appendChild(textNode);
                    }
                    
                    const newRange = document.createRange();
                    newRange.setStart(textNode, 0);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                }
            }
        },

        /**
         * 检查标题级别
         * @param {Range} range - 选择范围（可选）
         * @returns {number|null} 标题级别 (1=大标题, 2=二级标题, 3=三级标题, null=正文)
         */
        checkHeadingLevel: function(range) {
            if (!range) {
                const selection = window.getSelection();
                if (!selection.rangeCount) {
                    return null;
                }
                range = selection.getRangeAt(0);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }

            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const className = current.className || '';
                    if (className.includes('mi-note-size')) {
                        return 1;
                    } else if (className.includes('mi-note-mid-size')) {
                        return 2;
                    } else if (className.includes('mi-note-h3-size')) {
                        return 3;
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            return null;
        },

        /**
         * 检查列表类型
         * @param {Range} range - 选择范围（可选）
         * @returns {string|null} 列表类型 ('bullet'=无序列表, 'order'=有序列表, null=非列表)
         */
        checkListType: function(range) {
            if (!range) {
                const selection = window.getSelection();
                if (!selection.rangeCount) {
                    return null;
                }
                range = selection.getRangeAt(0);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }

            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const className = current.className || '';
                    if (className.includes('mi-note-bullet')) {
                        return 'bullet';
                    } else if (className.includes('mi-note-order')) {
                        return 'order';
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            return null;
        },

        /**
         * 检查文本对齐方式
         * @param {Range} range - 选择范围（可选）
         * @returns {string} 对齐方式 ('left', 'center', 'right')
         */
        checkTextAlignment: function(range) {
            if (!range) {
                const selection = window.getSelection();
                if (!selection.rangeCount) {
                    return 'left';
                }
                range = selection.getRangeAt(0);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }

            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const className = current.className || '';
                    if (className.includes('mi-note-text')) {
                        if (current.classList.contains('center')) {
                            return 'center';
                        } else if (current.classList.contains('right')) {
                            return 'right';
                        }
                        return 'left';
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            return 'left';
        },

        /**
         * 检查是否在引用块中
         * @param {Range} range - 选择范围（可选）
         * @returns {boolean} 是否在引用块中
         */
        checkQuoteState: function(range) {
            if (!range) {
                const selection = window.getSelection();
                if (!selection.rangeCount) {
                    return false;
                }
                range = selection.getRangeAt(0);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }

            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const className = current.className || '';
                    if (className.includes('mi-note-quote')) {
                        return true;
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            return false;
        },

        /**
         * 应用标题格式
         * @param {number} level - 标题级别 (0=清除, 1=大标题, 2=二级标题, 3=三级标题)
         * @returns {string} 状态信息
         */
        applyHeading: function(level) {
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选中文本或定位光标';
            }

            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const range = selection.getRangeAt(0);
            
            try {
                domWriter.beginBatch();
                
                let textElement = range.commonAncestorContainer;
                if (textElement.nodeType === Node.TEXT_NODE) {
                    textElement = textElement.parentElement;
                }

                while (textElement && !textElement.classList.contains('mi-note-text')) {
                    textElement = textElement.parentElement;
                }

                let targetNode = null;
                let targetOffset = 0;

                if (textElement && textElement.classList.contains('mi-note-text')) {
                    if (level === 0) {
                        const titleSpans = textElement.querySelectorAll('.mi-note-size, .mi-note-mid-size, .mi-note-h3-size');
                        titleSpans.forEach(span => {
                            const parent = span.parentNode;
                            while (span.firstChild) {
                                parent.insertBefore(span.firstChild, span);
                            }
                            domWriter.removeNode(span);
                        });
                        targetNode = textElement;
                        targetOffset = 0;
                    } else {
                        let className = '';
                        if (level === 1) {
                            className = 'mi-note-size';
                        } else if (level === 2) {
                            className = 'mi-note-mid-size';
                        } else if (level === 3) {
                            className = 'mi-note-h3-size';
                        }

                        if (className && !range.collapsed) {
                            const selectedText = range.toString();
                            const titleSpan = document.createElement('span');
                            titleSpan.className = className;
                            titleSpan.textContent = selectedText;
                            range.deleteContents();
                            domWriter.execute(() => {
                                range.insertNode(titleSpan);
                            }, true, { type: 'apply-heading' });
                            targetNode = titleSpan;
                            targetOffset = 0;
                        } else if (className) {
                            const titleSpan = document.createElement('span');
                            titleSpan.className = className;
                            titleSpan.innerHTML = '\u200B';
                            domWriter.insertNode(titleSpan, textElement, true);
                            targetNode = titleSpan;
                            targetOffset = 0;
                        }
                    }
                } else {
                    const editor = document.getElementById('editor-content');
                    const textDiv = document.createElement('div');
                    textDiv.className = 'mi-note-text indent-1';
                    
                    if (level > 0) {
                        let className = '';
                        if (level === 1) {
                            className = 'mi-note-size';
                        } else if (level === 2) {
                            className = 'mi-note-mid-size';
                        } else if (level === 3) {
                            className = 'mi-note-h3-size';
                        }
                        
                        if (className) {
                            const titleSpan = document.createElement('span');
                            titleSpan.className = className;
                            titleSpan.innerHTML = '\u200B';
                            textDiv.appendChild(titleSpan);
                            targetNode = titleSpan;
                            targetOffset = 0;
                        } else {
                            textDiv.innerHTML = '\u200B';
                            targetNode = textDiv;
                            targetOffset = 0;
                        }
                    } else {
                        textDiv.innerHTML = '\u200B';
                        targetNode = textDiv;
                        targetOffset = 0;
                    }

                    if (range.collapsed) {
                        domWriter.execute(() => {
                            range.insertNode(textDiv);
                        }, true, { type: 'apply-heading' });
                    } else {
                        domWriter.execute(() => {
                            range.deleteContents();
                            range.insertNode(textDiv);
                        }, true, { type: 'apply-heading' });
                    }
                }

                domWriter.endBatch({ type: 'apply-heading' });
                
                if (targetNode) {
                    requestAnimationFrame(() => {
                        const range2 = document.createRange();
                        range2.setStart(targetNode, targetOffset);
                        range2.collapse(true);
                        selection.removeAllRanges();
                        selection.addRange(range2);
                        
                        const notifyContentChanged = getNotifyContentChanged();
                        const syncFormatState = getSyncFormatState();
                        if (notifyContentChanged) {
                            notifyContentChanged();
                        }
                        if (syncFormatState) {
                            syncFormatState();
                        }
                    });
                } else {
                    const notifyContentChanged = getNotifyContentChanged();
                    const syncFormatState = getSyncFormatState();
                    if (notifyContentChanged) {
                        notifyContentChanged();
                    }
                    requestAnimationFrame(() => {
                        if (!window.isComposing && !window.isLoadingContent) {
                            if (syncFormatState) {
                                syncFormatState();
                            }
                        }
                    });
                }
                
                return '标题格式已应用';
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '应用标题格式失败', { level, error: error.message });
                return '应用标题格式失败: ' + error.message;
            }
        },

        /**
         * 应用对齐方式
         * @param {string} alignment - 对齐方式 (left, center, right)
         * @returns {string} 状态信息
         */
        applyAlignment: function(alignment) {
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '没有选中文本';
            }

            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const range = selection.getRangeAt(0);
            
            let textElement = range.commonAncestorContainer;
            if (textElement.nodeType === Node.TEXT_NODE) {
                textElement = textElement.parentElement;
            }

            while (textElement && !textElement.classList.contains('mi-note-text')) {
                textElement = textElement.parentElement;
            }

            if (!textElement || !textElement.classList.contains('mi-note-text')) {
                return '请选中文本元素';
            }

            try {
                domWriter.beginBatch();
                
                domWriter.setClass(textElement, 'center', false);
                domWriter.setClass(textElement, 'right', false);
                
                if (alignment === 'center') {
                    domWriter.setClass(textElement, 'center', true);
                } else if (alignment === 'right') {
                    domWriter.setClass(textElement, 'right', true);
                }

                domWriter.endBatch({ type: 'apply-alignment' });
                
                const notifyContentChanged = getNotifyContentChanged();
                const syncFormatState = getSyncFormatState();
                if (notifyContentChanged) {
                    notifyContentChanged();
                }
                requestAnimationFrame(() => {
                    if (!window.isComposing && !window.isLoadingContent) {
                        if (syncFormatState) {
                            syncFormatState();
                        }
                    }
                });
                return '对齐方式已应用: ' + alignment;
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '应用对齐方式失败', { alignment, error: error.message });
                return '应用对齐方式失败: ' + error.message;
            }
        },

        /**
         * 插入无序列表
         * @returns {string} 状态信息
         */
        insertBulletList: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let textElement = null;
            let hasContent = false;
            let contentHTML = '';
            
            if (container && container.classList && container.classList.contains('mi-note-text')) {
                textElement = container;
                const text = container.textContent || container.innerText || '';
                const trimmedText = text.replace(/\u200B/g, '').trim();
                hasContent = trimmedText !== '';
                if (hasContent) {
                    contentHTML = container.innerHTML;
                    contentHTML = contentHTML.replace(/\u200B/g, '');
                }
            }

            domWriter.beginBatch();
            
            const bulletDiv = document.createElement('div');
            bulletDiv.className = 'mi-note-bullet';
            bulletDiv.style.paddingLeft = '0px';
            
            if (hasContent && textElement) {
                bulletDiv.innerHTML = contentHTML || '\u200B';
                domWriter.replaceNode(textElement, bulletDiv);
            } else if (textElement) {
                bulletDiv.innerHTML = '\u200B';
                domWriter.replaceNode(textElement, bulletDiv);
            } else {
                bulletDiv.innerHTML = '\u200B';
                const referenceNode = range.startContainer.nodeType === Node.TEXT_NODE 
                    ? range.startContainer.parentElement 
                    : range.startContainer;
                if (referenceNode && referenceNode.parentNode) {
                    domWriter.insertNode(bulletDiv, referenceNode, false);
                } else {
                    domWriter.execute(() => {
                        range.insertNode(bulletDiv);
                    }, true, { type: 'insert-bullet-list' });
                }
            }

            let targetNode = null;
            let targetOffset = 0;
            
            if (hasContent && bulletDiv.lastChild) {
                if (bulletDiv.lastChild.nodeType === Node.TEXT_NODE) {
                    targetNode = bulletDiv.lastChild;
                    targetOffset = bulletDiv.lastChild.textContent.length;
                } else {
                    targetNode = bulletDiv;
                    targetOffset = bulletDiv.childNodes.length;
                }
            } else {
                if (bulletDiv.firstChild && bulletDiv.firstChild.nodeType === Node.TEXT_NODE) {
                    targetNode = bulletDiv.firstChild;
                    targetOffset = 0;
                } else {
                    const textNode = document.createTextNode('\u200B');
                    bulletDiv.appendChild(textNode);
                    targetNode = textNode;
                    targetOffset = 0;
                }
            }
            
            domWriter.endBatch({ type: 'insert-bullet-list' });
            
            requestAnimationFrame(() => {
                const selection2 = window.getSelection();
                const range2 = document.createRange();
                range2.setStart(targetNode, targetOffset);
                range2.collapse(true);
                selection2.removeAllRanges();
                selection2.addRange(range2);
                
                const notifyContentChanged = getNotifyContentChanged();
                const syncFormatState = getSyncFormatState();
                if (notifyContentChanged) {
                    notifyContentChanged();
                }
                if (syncFormatState) {
                    syncFormatState();
                }
            });

            return '无序列表已插入';
        },

        /**
         * 插入有序列表
         * @returns {string} 状态信息
         */
        insertOrderList: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let textElement = null;
            let hasContent = false;
            let contentHTML = '';
            
            if (container && container.classList && container.classList.contains('mi-note-text')) {
                textElement = container;
                const text = container.textContent || container.innerText || '';
                const trimmedText = text.replace(/\u200B/g, '').trim();
                hasContent = trimmedText !== '';
                if (hasContent) {
                    contentHTML = container.innerHTML;
                    contentHTML = contentHTML.replace(/\u200B/g, '');
                }
            }

            domWriter.beginBatch();
            
            const orderDiv = document.createElement('div');
            orderDiv.className = 'mi-note-order';
            orderDiv.setAttribute('data-number', '1');
            orderDiv.style.paddingLeft = '0px';
            
            if (hasContent && textElement) {
                orderDiv.innerHTML = contentHTML || '\u200B';
                domWriter.replaceNode(textElement, orderDiv);
            } else if (textElement) {
                orderDiv.innerHTML = '\u200B';
                domWriter.replaceNode(textElement, orderDiv);
            } else {
                orderDiv.innerHTML = '\u200B';
                const referenceNode = range.startContainer.nodeType === Node.TEXT_NODE 
                    ? range.startContainer.parentElement 
                    : range.startContainer;
                if (referenceNode && referenceNode.parentNode) {
                    domWriter.insertNode(orderDiv, referenceNode, false);
                } else {
                    domWriter.execute(() => {
                        range.insertNode(orderDiv);
                    }, true, { type: 'insert-order-list' });
                }
            }

            let targetNode = null;
            let targetOffset = 0;
            
            if (hasContent && orderDiv.lastChild) {
                if (orderDiv.lastChild.nodeType === Node.TEXT_NODE) {
                    targetNode = orderDiv.lastChild;
                    targetOffset = orderDiv.lastChild.textContent.length;
                } else {
                    targetNode = orderDiv;
                    targetOffset = orderDiv.childNodes.length;
                }
            } else {
                if (orderDiv.firstChild && orderDiv.firstChild.nodeType === Node.TEXT_NODE) {
                    targetNode = orderDiv.firstChild;
                    targetOffset = 0;
                } else {
                    const textNode = document.createTextNode('\u200B');
                    orderDiv.appendChild(textNode);
                    targetNode = textNode;
                    targetOffset = 0;
                }
            }
            
            domWriter.endBatch({ type: 'insert-order-list' });
            
            requestAnimationFrame(() => {
                const selection2 = window.getSelection();
                const range2 = document.createRange();
                range2.setStart(targetNode, targetOffset);
                range2.collapse(true);
                selection2.removeAllRanges();
                selection2.addRange(range2);
                
                const notifyContentChanged = getNotifyContentChanged();
                const syncFormatState = getSyncFormatState();
                if (notifyContentChanged) {
                    notifyContentChanged();
                }
                if (syncFormatState) {
                    syncFormatState();
                }
            });

            return '有序列表已插入';
        },

        /**
         * 插入引用块
         * @returns {string} 状态信息
         */
        insertQuote: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            const quoteDiv = document.createElement('div');
            quoteDiv.className = 'mi-note-quote';

            const textDiv = document.createElement('div');
            textDiv.className = 'mi-note-text indent-1';
            textDiv.innerHTML = '\u200B';
            quoteDiv.appendChild(textDiv);

            range.insertNode(quoteDiv);

            range.selectNodeContents(textDiv);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);

            const notifyContentChanged = getNotifyContentChanged();
            const syncFormatState = getSyncFormatState();
            if (notifyContentChanged) {
                notifyContentChanged();
            }
            requestAnimationFrame(() => {
                if (!window.isComposing && !window.isLoadingContent) {
                    if (syncFormatState) {
                        syncFormatState();
                    }
                }
            });
            return '引用块已插入';
        },

        /**
         * 插入复选框
         * @returns {string} 状态信息
         */
        insertCheckbox: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let textElement = null;
            let hasContent = false;
            let contentHTML = '';
            
            if (container && container.classList && container.classList.contains('mi-note-text')) {
                textElement = container;
                const text = container.textContent || container.innerText || '';
                const trimmedText = text.replace(/\u200B/g, '').trim();
                hasContent = trimmedText !== '';
                if (hasContent) {
                    contentHTML = container.innerHTML;
                    contentHTML = contentHTML.replace(/\u200B/g, '');
                }
            }

            domWriter.beginBatch();
            
            const checkboxDiv = document.createElement('div');
            checkboxDiv.className = 'mi-note-checkbox';
            checkboxDiv.setAttribute('data-level', '3');
            checkboxDiv.style.paddingLeft = '0px';

            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkboxDiv.appendChild(checkbox);

            const span = document.createElement('span');
            if (hasContent && textElement) {
                span.innerHTML = contentHTML || '\u200B';
            } else {
                span.innerHTML = '\u200B';
            }
            checkboxDiv.appendChild(span);

            if (textElement) {
                domWriter.replaceNode(textElement, checkboxDiv);
            } else {
                const referenceNode = range.startContainer.nodeType === Node.TEXT_NODE 
                    ? range.startContainer.parentElement 
                    : range.startContainer;
                if (referenceNode && referenceNode.parentNode) {
                    domWriter.insertNode(checkboxDiv, referenceNode, false);
                } else {
                    domWriter.execute(() => {
                        range.insertNode(checkboxDiv);
                    }, true, { type: 'insert-checkbox' });
                }
            }

            let targetNode = null;
            let targetOffset = 0;
            
            if (hasContent && span.lastChild) {
                if (span.lastChild.nodeType === Node.TEXT_NODE) {
                    targetNode = span.lastChild;
                    targetOffset = span.lastChild.textContent.length;
                } else {
                    targetNode = span;
                    targetOffset = span.childNodes.length;
                }
            } else {
                if (span.firstChild && span.firstChild.nodeType === Node.TEXT_NODE) {
                    targetNode = span.firstChild;
                    targetOffset = 0;
                } else {
                    const textNode = document.createTextNode('\u200B');
                    span.appendChild(textNode);
                    targetNode = textNode;
                    targetOffset = 0;
                }
            }
            
            domWriter.endBatch({ type: 'insert-checkbox' });
            
            requestAnimationFrame(() => {
                const selection2 = window.getSelection();
                const range2 = document.createRange();
                range2.setStart(targetNode, targetOffset);
                range2.collapse(true);
                selection2.removeAllRanges();
                selection2.addRange(range2);
                
                const notifyContentChanged = getNotifyContentChanged();
                const syncFormatState = getSyncFormatState();
                if (notifyContentChanged) {
                    notifyContentChanged();
                }
                if (syncFormatState) {
                    syncFormatState();
                }
            });

            return '复选框已插入';
        },

        /**
         * 插入分割线
         * @returns {string} 状态信息
         */
        insertHorizontalRule: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            const selection = window.getSelection();
            let range = null;
            
            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            const hr = document.createElement('hr');
            hr.className = 'mi-note-hr';

            range.insertNode(hr);

            const br = document.createElement('br');
            range.setStartAfter(hr);
            range.insertNode(br);

            range.setStartAfter(br);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            
            const notifyContentChanged = getNotifyContentChanged();
            if (notifyContentChanged) {
                notifyContentChanged();
            }
            return '分割线已插入';
        },

        /**
         * 插入图片
         * @param {string} imageUrl - 图片 URL
         * @param {string} altText - 替代文本（可选）
         * @returns {string} 状态信息
         */
        insertImage: function(imageUrl, altText) {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            if (!imageUrl) {
                return '图片 URL 不能为空';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let listItem = null;
            let currentNode = container;
            while (currentNode && currentNode !== editor) {
                if (currentNode.classList) {
                    if (currentNode.classList.contains('mi-note-bullet') ||
                        currentNode.classList.contains('mi-note-order') ||
                        currentNode.classList.contains('mi-note-checkbox')) {
                        listItem = currentNode;
                        break;
                    }
                }
                currentNode = currentNode.parentElement;
            }

            if (listItem) {
                let newRange = document.createRange();
                if (listItem.nextSibling) {
                    newRange.setStartBefore(listItem.nextSibling);
                    newRange.collapse(true);
                    range = newRange;
                } else if (listItem.parentNode) {
                    newRange.setStartAfter(listItem);
                    newRange.collapse(true);
                    range = newRange;
                }
            }

            const imageContainer = document.createElement('div');
            imageContainer.className = 'mi-note-image-container';
            imageContainer.style.margin = '8px 0';

            const img = document.createElement('img');
            img.src = imageUrl;
            img.alt = altText || '图片';
            img.className = 'mi-note-image';
            
            if (imageUrl.startsWith('data:')) {
                log.debug(LOG_MODULES.IMAGE, '插入 data URL 图片');
            } else if (imageUrl.startsWith('minote://')) {
                log.debug(LOG_MODULES.IMAGE, '插入小米笔记图片', { imageUrl });
            }

            imageContainer.appendChild(img);

            range.insertNode(imageContainer);

            const br = document.createElement('br');
            range.setStartAfter(imageContainer);
            range.insertNode(br);

            range.setStartAfter(br);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            
            const notifyContentChanged = getNotifyContentChanged();
            if (notifyContentChanged) {
                notifyContentChanged();
            }
            return '图片已插入';
        },
        
        /**
         * 插入语音录音
         * 在当前光标位置插入语音占位符
         * @param {string} fileId - 语音文件 ID
         * @param {string} digest - 文件摘要（可选）
         * @param {string} mimeType - MIME 类型（可选，默认 audio/mpeg）
         * @returns {string} 状态信息
         * Requirements: 12.1, 12.2, 12.3
         */
        insertAudio: function(fileId, digest, mimeType) {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            if (!fileId) {
                return '语音文件 ID 不能为空';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            // 检查光标是否在列表项或待办项中
            let container = range.commonAncestorContainer;
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let listItem = null;
            let currentNode = container;
            while (currentNode && currentNode !== editor) {
                if (currentNode.classList) {
                    if (currentNode.classList.contains('mi-note-bullet') ||
                        currentNode.classList.contains('mi-note-order') ||
                        currentNode.classList.contains('mi-note-checkbox')) {
                        listItem = currentNode;
                        break;
                    }
                }
                currentNode = currentNode.parentElement;
            }

            // 如果在列表项或待办项中，在其后插入
            if (listItem) {
                let newRange = document.createRange();
                if (listItem.nextSibling) {
                    newRange.setStartBefore(listItem.nextSibling);
                    newRange.collapse(true);
                    range = newRange;
                } else if (listItem.parentNode) {
                    newRange.setStartAfter(listItem);
                    newRange.collapse(true);
                    range = newRange;
                }
            }

            // 创建语音容器
            const soundContainer = document.createElement('div');
            soundContainer.className = 'mi-note-sound-container';
            soundContainer.style.margin = '8px 0';

            // 创建语音占位符元素
            const soundElement = document.createElement('div');
            soundElement.className = 'mi-note-sound';
            soundElement.setAttribute('data-fileid', fileId);
            if (digest) {
                soundElement.setAttribute('data-digest', digest);
            }
            if (mimeType) {
                soundElement.setAttribute('data-mimetype', mimeType);
            } else {
                soundElement.setAttribute('data-mimetype', 'audio/mpeg');
            }
            soundElement.setAttribute('contenteditable', 'false');

            // 创建图标
            const iconSpan = document.createElement('span');
            iconSpan.className = 'mi-note-sound-icon';
            iconSpan.textContent = '🎤';

            // 创建标签
            const labelSpan = document.createElement('span');
            labelSpan.className = 'mi-note-sound-label';
            labelSpan.textContent = '语音录音';

            soundElement.appendChild(iconSpan);
            soundElement.appendChild(labelSpan);
            soundContainer.appendChild(soundElement);

            // 插入语音容器
            range.insertNode(soundContainer);

            // 在语音后插入换行，确保可以继续输入
            const br = document.createElement('br');
            range.setStartAfter(soundContainer);
            range.insertNode(br);

            // 移动光标到语音后
            range.setStartAfter(br);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            
            log.debug(LOG_MODULES.FORMAT, '插入语音录音', { fileId, digest, mimeType });

            const notifyContentChanged = getNotifyContentChanged();
            if (notifyContentChanged) {
                notifyContentChanged();
            }
            return '语音已插入';
        },
        
        /**
         * 增加缩进
         * @returns {string} 状态信息
         */
        increaseIndent: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }
            
            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选择内容';
            }
            
            const range = selection.getRangeAt(0);
            let container = range.commonAncestorContainer;
            
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let targetElement = null;
            let currentNode = container;
            while (currentNode && currentNode !== editor) {
                if (currentNode.classList) {
                    if (currentNode.classList.contains('mi-note-text') ||
                        currentNode.classList.contains('mi-note-bullet') ||
                        currentNode.classList.contains('mi-note-order') ||
                        currentNode.classList.contains('mi-note-checkbox')) {
                        targetElement = currentNode;
                        break;
                    }
                }
                currentNode = currentNode.parentElement;
            }
            
            if (!targetElement) {
                return '无法找到可缩进的元素';
            }
            
            const currentIndent = parseInt(getIndentFromElement(targetElement), 10);
            if (currentIndent >= 5) {
                return '已达到最大缩进级别';
            }
            
            domWriter.beginBatch();
            
            setIndentForElement(targetElement, currentIndent + 1);
            
            domWriter.endBatch({ type: 'increase-indent' });
            
            const notifyContentChanged = getNotifyContentChanged();
            if (notifyContentChanged) {
                notifyContentChanged();
            }
            
            return '缩进已增加';
        },
        
        /**
         * 减少缩进
         * @returns {string} 状态信息
         */
        decreaseIndent: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }
            
            const domWriter = getDomWriter();
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选择内容';
            }
            
            const range = selection.getRangeAt(0);
            let container = range.commonAncestorContainer;
            
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            let targetElement = null;
            let currentNode = container;
            while (currentNode && currentNode !== editor) {
                if (currentNode.classList) {
                    if (currentNode.classList.contains('mi-note-text') ||
                        currentNode.classList.contains('mi-note-bullet') ||
                        currentNode.classList.contains('mi-note-order') ||
                        currentNode.classList.contains('mi-note-checkbox')) {
                        targetElement = currentNode;
                        break;
                    }
                }
                currentNode = currentNode.parentElement;
            }
            
            if (!targetElement) {
                return '无法找到可缩进的元素';
            }
            
            const currentIndent = parseInt(getIndentFromElement(targetElement), 10);
            if (currentIndent <= 1) {
                return '已达到最小缩进级别';
            }
            
            domWriter.beginBatch();
            
            setIndentForElement(targetElement, currentIndent - 1);
            
            domWriter.endBatch({ type: 'decrease-indent' });
            
            const notifyContentChanged = getNotifyContentChanged();
            if (notifyContentChanged) {
                notifyContentChanged();
            }
            
            return '缩进已减少';
        }
    };

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Format = FormatManager;
    
    // 向后兼容：也导出到全局
    window.FormatManager = FormatManager;

})();

