/**
 * Editor API 模块
 * 提供 window.MiNoteWebEditor 公开 API
 * 依赖: 所有模块（logger, converter, cursor, dom-writer, command, format, editor-core）
 * 
 * 注意：这个模块包含 window.MiNoteWebEditor 对象的所有方法
 * 由于代码量很大（约2897行），这里先创建骨架，然后逐步完善
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { EDITOR: 'Editor' };

    // 获取 Format 模块
    const FormatManager = window.MiNoteEditor && window.MiNoteEditor.Format;

    // 注意：以下全局变量和函数需要在其他模块或 editor.html 中定义
    // - domWriter
    // - commandManager
    // - window.MiNoteEditor.Cursor (光标函数)
    // - window.MiNoteEditor.Editor (核心函数)
    // - window.MiNoteEditor.Converter (转换器)
    // - window.MiNoteEditor.Utils (工具函数)
    // - window.MiNoteEditor.Format (格式管理器)

    // ==================== window.MiNoteWebEditor 接口 ====================
    // 注意：
    // 1. 光标保存和恢复函数已在 Cursor 模块中定义并导出到 window.MiNoteWebEditor
    // 2. loadContent 和 getContent 已在 Editor Core 模块中定义并导出到 window.MiNoteWebEditor
    // 这里只需要扩展 window.MiNoteWebEditor 对象，添加其他 API 方法
    
    // 确保 window.MiNoteWebEditor 对象存在（可能已被 Editor Core 模块创建）
    if (!window.MiNoteWebEditor) {
        window.MiNoteWebEditor = {};
    }
    
    // 扩展 window.MiNoteWebEditor 对象，而不是覆盖它
    // 注意：loadContent 和 getContent 已在 Editor Core 模块中定义
    // 这里只添加其他 API 方法
    Object.assign(window.MiNoteWebEditor, {
        /**
         * 强制立即保存当前内容
         * @returns {string} 状态信息
         */
        forceSaveContent: function() {
            log.debug(LOG_MODULES.EDITOR, '强制保存当前内容');
            const notifyContentChanged = window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged;
            if (notifyContentChanged) {
            notifyContentChanged();
            }
            return '内容已强制保存';
        },

        /**
         * 撤销上一个操作
         * @returns {string} 状态信息
         */
        undo: function() {
            const domWriter = window.domWriter;
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            
            if (domWriter.undo()) {
                return '已撤销';
            } else {
                return '没有可撤销的操作';
            }
        },

        /**
         * 重做上一个操作
         * @returns {string} 状态信息
         */
        redo: function() {
            const domWriter = window.domWriter;
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            
            if (domWriter.redo()) {
                return '已重做';
            } else {
                return '没有可重做的操作';
            }
        },

        /**
         * 检查是否可以撤销
         * @returns {boolean}
         */
        canUndo: function() {
            const domWriter = window.domWriter;
            return domWriter ? domWriter.canUndo() : false;
        },

        /**
         * 检查是否可以重做
         * @returns {boolean}
         */
        canRedo: function() {
            const domWriter = window.domWriter;
            return domWriter ? domWriter.canRedo() : false;
        },
        
        /**
         * 设置颜色方案（深色/浅色模式）
         * @param {string} scheme - 'light' 或 'dark'
         * @returns {string} 状态信息
         */
        setColorScheme: function(scheme) {
            log.debug(LOG_MODULES.EDITOR, '设置颜色方案', { scheme });
            
            const root = document.documentElement;
            const body = document.body;
            
            if (scheme === 'dark') {
                root.setAttribute('data-color-scheme', 'dark');
                if (body) {
                    body.setAttribute('data-color-scheme', 'dark');
                }
                log.debug(LOG_MODULES.EDITOR, '已设置为深色模式');
            } else {
                root.setAttribute('data-color-scheme', 'light');
                if (body) {
                    body.setAttribute('data-color-scheme', 'light');
                }
                log.debug(LOG_MODULES.EDITOR, '已设置为浅色模式');
            }
            
            return '颜色方案已设置为: ' + scheme;
        },
        
        /**
         * 应用编辑器显示设置（字体大小和行间距）
         * @param {Object} settings - 编辑器设置对象
         * @param {number} settings.fontSize - 字体大小（像素）
         * @param {number} settings.lineHeight - 行间距（倍数）
         * @returns {string} 状态信息
         */
        applyEditorSettings: function(settings) {
            log.debug(LOG_MODULES.EDITOR, '应用编辑器设置', settings);
            
            const root = document.documentElement;
            const editor = document.getElementById('editor-content');
            
            if (!editor) {
                log.error(LOG_MODULES.EDITOR, '无法找到编辑器元素');
                return '编辑器元素不存在';
            }
            
            // 验证设置值
            const fontSize = Math.max(12, Math.min(24, settings.fontSize || 14));
            const lineHeight = Math.max(1.0, Math.min(2.5, settings.lineHeight || 1.5));
            
            // 更新 CSS 变量
            root.style.setProperty('--editor-font-size', `${fontSize}px`);
            root.style.setProperty('--editor-line-height', lineHeight.toString());
            
            // 更新编辑器元素的样式
            editor.style.fontSize = `${fontSize}px`;
            editor.style.lineHeight = lineHeight.toString();
            
            // 更新所有文本元素的样式
            const textElements = editor.querySelectorAll('.mi-note-text, .mi-note-bullet, .mi-note-order, .mi-note-checkbox');
            textElements.forEach(element => {
                element.style.fontSize = `${fontSize}px`;
                element.style.lineHeight = lineHeight.toString();
            });
            
            // 更新标题元素的相对大小
            const titleSizeElements = editor.querySelectorAll('.mi-note-size, .mi-note-mid-size, .mi-note-h3-size');
            titleSizeElements.forEach(element => {
                if (element.classList.contains('mi-note-size')) {
                    element.style.fontSize = `calc(${fontSize}px * 1.714)`;
                } else if (element.classList.contains('mi-note-mid-size')) {
                    element.style.fontSize = `calc(${fontSize}px * 1.429)`;
                } else if (element.classList.contains('mi-note-h3-size')) {
                    element.style.fontSize = `calc(${fontSize}px * 1.286)`;
                }
            });
            
            log.debug(LOG_MODULES.EDITOR, '编辑器设置已应用', { 
                fontSize: `${fontSize}px`, 
                lineHeight: lineHeight 
            });
            
            return `编辑器设置已应用: 字体大小=${fontSize}px, 行间距=${lineHeight}`;
        },
        
        /**
         * 执行格式操作
         * @param {string} action - 操作类型
         * @param {string} value - 操作值（可选）
         * @returns {string} 状态信息
         */
        executeFormatAction: function(action, value) {
            log.debug(LOG_MODULES.FORMAT, '执行格式操作', { action, value });
            const editor = document.getElementById('editor-content');
            if (!editor) {
                log.error(LOG_MODULES.FORMAT, '无法找到编辑器元素');
                return '编辑器元素不存在';
            }

            // 确保编辑器有焦点
            editor.focus();

            try {
                switch (action) {
                    case 'bold':
                        return this.applyFormat('bold');
                    case 'italic':
                        return this.applyFormat('italic');
                    case 'underline':
                        return this.applyFormat('underline');
                    case 'strikethrough':
                        return this.applyFormat('strikethrough');
                    case 'highlight':
                        return this.applyFormat('highlight');
                    case 'heading':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.applyHeading(value ? parseInt(value, 10) : 0);
                    case 'textAlignment':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.applyAlignment(value || 'left');
                    case 'bulletList':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.insertBulletList();
                    case 'orderList':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.insertOrderList();
                    case 'quote':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.insertQuote();
                    case 'checkbox':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.insertCheckbox();
                    case 'horizontalRule':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        return FormatManager.insertHorizontalRule();
                    case 'indent':
                        if (!FormatManager) {
                            return '格式管理器未初始化';
                        }
                        if (value === 'increase') {
                            return FormatManager.increaseIndent();
                        } else if (value === 'decrease') {
                            return FormatManager.decreaseIndent();
                        }
                        return '无效的缩进操作';
                    default:
                        log.warn(LOG_MODULES.FORMAT, '未实现的操作', { action });
                        return '操作暂未实现: ' + action;
                }
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '执行失败', { 
                    action, 
                    value, 
                    error: error.message, 
                    stack: error.stack 
                });
                return '操作执行失败: ' + error.message;
            }
        },

        /**
         * 应用文本格式（加粗、斜体、下划线、删除线、高亮）
         * @param {string} format - 格式类型
         * @returns {string} 状态信息
         */
        applyFormat: function(format) {
            // 如果正在组合输入，不执行格式操作（避免打断输入）
            if (window.isComposing) {
                log.debug(LOG_MODULES.FORMAT, '正在组合输入，跳过格式操作');
                return '正在组合输入，无法应用格式';
            }
            
            if (!FormatManager) {
                log.error(LOG_MODULES.FORMAT, 'FormatManager 未初始化');
                return '格式管理器未初始化';
            }
            
            return FormatManager.applyFormat(format);
        },

        /**
         * 内部方法：检查当前格式状态（已移至 Format 模块，保留此方法以向后兼容）
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @returns {boolean} 是否已应用格式
         */
        _checkFormatStateInternal: function(range, format) {
            if (!FormatManager) {
                return false;
            }
            return FormatManager._checkFormatStateInternal(range, format);
        },

        /**
         * 检查当前格式状态（供外部调用）
         * @param {Range} range - 选择范围（可选，如果不提供则使用当前选择）
         * @param {string} format - 格式类型
         * @returns {boolean} 是否已应用格式
         */
        checkFormatState: function(range, format) {
            if (!FormatManager) {
                    return false;
                }
            return FormatManager.checkFormatState(range, format);
        },

        /**
         * 检查标题级别（参考 CKEditor 5 的 heading command value）
         * @param {Range} range - 选择范围（可选）
         * @returns {number|null} 标题级别 (1=大标题, 2=二级标题, 3=三级标题, null=正文)
         */
        checkHeadingLevel: function(range) {
            if (!FormatManager) {
                    return null;
                }
            return FormatManager.checkHeadingLevel(range);
        },

        /**
         * 检查列表类型（参考 CKEditor 5 的 list command value）
         * @param {Range} range - 选择范围（可选）
         * @returns {string|null} 列表类型 ('bullet'=无序列表, 'order'=有序列表, null=非列表)
         */
        checkListType: function(range) {
            if (!FormatManager) {
                    return null;
                }
            return FormatManager.checkListType(range);
        },

        /**
         * 检查文本对齐方式（参考 CKEditor 5 的 alignment command value）
         * @param {Range} range - 选择范围（可选）
         * @returns {string} 对齐方式 ('left', 'center', 'right')
         */
        checkTextAlignment: function(range) {
            if (!FormatManager) {
                    return 'left';
                }
            return FormatManager.checkTextAlignment(range);
        },

        /**
         * 检查是否在引用块中（参考 CKEditor 5 的 blockQuote command value）
         * @param {Range} range - 选择范围（可选）
         * @returns {boolean} 是否在引用块中
         */
        checkQuoteState: function(range) {
            if (!FormatManager) {
                    return false;
                }
            return FormatManager.checkQuoteState(range);
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

            // 方法1：优先使用 document.queryCommandState（最准确，类似 CKEditor 5 的 selection.hasAttribute）
            // 这是最接近 CKEditor 5 实现的方法
            try {
                if (tagName) {
                    const state = document.queryCommandState(format);
                    // 确保返回值是有效的布尔值
                    if (state !== undefined && state !== null) {
                        return Boolean(state);
                    }
                }
            } catch (e) {
                // queryCommandState 可能不支持某些格式，继续使用 DOM 检查
            }

            // 方法2：使用 DOM 检查格式状态（参考 CKEditor 5 的 _getValueFromFirstAllowedNode）
            // CKEditor 5 会检查选择范围内的第一个允许该属性的节点
            let container = range.commonAncestorContainer;
            
            // 如果是文本节点，检查其父元素
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }

            // 向上查找格式标签（支持所有可能的标签变体）
            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName ? current.tagName.toLowerCase() : '';
                    // 检查所有可能的格式标签变体（类似 CKEditor 5 的处理）
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

            // 方法3：对于非折叠选择，检查选中文本是否包含格式（参考 CKEditor 5 的 range.getItems）
            // CKEditor 5 会遍历选择范围内的所有节点
            if (!range.collapsed) {
                try {
                    const contents = range.cloneContents();
                    // 检查克隆内容中是否包含格式元素
                    if (tagName) {
                        // 检查所有可能的格式标签变体
                        const formatElements = contents.querySelectorAll(
                            tagName + ', strong, em, strike, del, s'
                        );
                        if (formatElements.length > 0) {
                            // 检查是否所有文本都在格式元素内
                            // 如果选中文本完全在格式元素内，返回 true
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
         * 清除光标位置的格式（优化版，参考 CKEditor 5 的 AttributeCommand 实现）
         * 
         * CKEditor 5 的核心思路：
         * - 对于折叠选择，使用 writer.removeSelectionAttribute（类似 execCommand 的 removeFormat）
         * - 自动处理光标位置，确保后续输入不继承格式
         * 
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @param {string} tagName - 标签名
         * @param {string} className - 类名
         */
        clearFormatAtCursor: function(range, format, tagName, className) {
            const selection = window.getSelection();
            
            // 方法1：优先使用 execCommand（最可靠，类似 CKEditor 5 的 writer.removeSelectionAttribute）
            // 但只对 execCommand 支持的格式（bold, italic, underline, strikethrough）使用
            // 高亮等自定义格式直接使用手动方法
            if (tagName && !className) {
                try {
                    const isFormatted = document.queryCommandState(format);
                    if (isFormatted) {
                        // 检查光标是否在格式元素末尾
                        let container = range.commonAncestorContainer;
                        let formatElement = null;
                        let isAtEnd = false;
                        
                        // 向上查找格式元素
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
                                    // 检查光标是否在格式元素末尾
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
                        
                        // 如果光标在格式元素末尾，先移出再清除格式（避免光标跳到开头）
                        if (isAtEnd && formatElement) {
                            const parent = formatElement.parentElement;
                            if (parent) {
                                // 在格式元素后查找或创建文本节点
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
                                    // 创建新文本节点
                                    nextTextNode = document.createTextNode('');
                                    if (formatElement.nextSibling) {
                                        parent.insertBefore(nextTextNode, formatElement.nextSibling);
                                    } else {
                                        parent.appendChild(nextTextNode);
                                    }
                                }
                                
                                // 移动光标到格式元素后的文本节点
                                const newRange = document.createRange();
                                newRange.setStart(nextTextNode, 0);
                                newRange.collapse(true);
                                selection.removeAllRanges();
                                selection.addRange(newRange);
                                
                                // 现在清除格式（光标已经在格式元素外）
                                if (domWriter) {
                                    domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                                } else {
                                    document.execCommand(format, false, null);
                                }
                                return;
                            }
                        }
                        
                        // 使用 execCommand 切换格式（会清除当前格式）（记录历史）
                        if (domWriter) {
                            domWriter.executeCommandWithHistory(format, false, null, 'format-' + format);
                        } else {
                            document.execCommand(format, false, null);
                        }
                        
                        // 验证格式是否已清除
                        const stillFormatted = document.queryCommandState(format);
                        if (!stillFormatted) {
                            // 格式已清除，execCommand 已经处理了光标位置
                            return;
                        }
                    }
                } catch (e) {
                    // execCommand 可能不支持，继续使用手动方法
                    log.warn(LOG_MODULES.FORMAT, 'execCommand 清除格式失败，使用手动方法', { error: e.message });
                }
            }
            
            // 方法2：手动清除（当 execCommand 不可用或失败时，或自定义格式如高亮）
            // 参考 CKEditor 5 的思路：找到格式元素，将光标移出并移除格式元素
            // 关键：如果光标在格式元素末尾，清除格式后光标应该在格式元素后（不是开头）
            let container = range.commonAncestorContainer;
            let formatElement = null;
            
            // 向上查找格式标签（支持所有变体）
            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName ? current.tagName.toLowerCase() : '';
                    // 检查是否是目标格式元素（支持所有变体）
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
                // 光标在格式元素内，需要移出并移除格式元素（参考 CKEditor 5 的光标管理）
                const parent = formatElement.parentElement;
                if (!parent) {
                    // 如果没有父元素，尝试使用 execCommand（仅对支持的格式）
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

                // 确定光标是否在格式元素的末尾
                let cursorIsAtEnd = false;
                if (container.nodeType === Node.TEXT_NODE) {
                    const textNode = container;
                    const lastTextNode = this.getLastTextNode(formatElement);
                    if (textNode === lastTextNode && range.startOffset === textNode.textContent.length) {
                        cursorIsAtEnd = true;
                    }
                }

                // 对于自定义格式（如高亮），需要特殊处理
                // 关键：如果光标在格式元素末尾，只移出光标，不展开整个元素（与加粗逻辑一致）
                // 但是，移出光标后，高亮格式已经被"清除"（因为光标不在高亮元素内了）
                // 这与加粗的逻辑一致：移出光标后，execCommand 会清除格式
                if (className) {
                    if (cursorIsAtEnd) {
                        // 光标在高亮元素末尾，只移出光标，保留高亮元素内容
                        // 在格式元素后查找或创建文本节点
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
                            // 创建新文本节点
                            nextTextNode = document.createTextNode('');
                            if (formatElement.nextSibling) {
                                parent.insertBefore(nextTextNode, formatElement.nextSibling);
                            } else {
                                parent.appendChild(nextTextNode);
                            }
                        }
                        
                        // 移动光标到格式元素后的文本节点
                        // 注意：光标移出后，高亮格式已经被"清除"（因为光标不在高亮元素内了）
                        // 这与加粗的逻辑一致：移出光标后，execCommand 会清除格式
                        const newRange = document.createRange();
                        newRange.setStart(nextTextNode, 0);
                        newRange.collapse(true);
                        selection.removeAllRanges();
                        selection.addRange(newRange);
                        
                        // 验证：确保光标不在高亮元素内
                        // 如果光标仍然在高亮元素内，需要进一步处理
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
                        
                        // 如果光标仍然在高亮元素内，说明移出失败，需要展开高亮元素
                        if (stillInHighlight) {
                            // 展开高亮元素的内容
                            const fragment = document.createDocumentFragment();
                            while (formatElement.firstChild) {
                                fragment.appendChild(formatElement.firstChild);
                            }
                            
                            // 在格式元素后插入内容
                            if (formatElement.nextSibling) {
                                parent.insertBefore(fragment, formatElement.nextSibling);
                            } else {
                                parent.appendChild(fragment);
                            }
                            
                            // 移除格式元素
                            parent.removeChild(formatElement);
                            
                            // 移动光标到展开内容后的位置
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
                        // 光标不在末尾，需要展开格式元素的内容
                        const fragment = document.createDocumentFragment();
                        while (formatElement.firstChild) {
                            fragment.appendChild(formatElement.firstChild);
                        }
                        
                        // 在格式元素后插入内容
                        if (formatElement.nextSibling) {
                            parent.insertBefore(fragment, formatElement.nextSibling);
                        } else {
                            parent.appendChild(fragment);
                        }
                        
                        // 移除格式元素
                        parent.removeChild(formatElement);
                        
                        // 移动光标到展开内容后的位置
                        if (fragment.childNodes.length > 0) {
                            const lastNode = fragment.lastChild;
                            if (lastNode.nodeType === Node.TEXT_NODE) {
                                const newRange = document.createRange();
                                newRange.setStart(lastNode, lastNode.textContent.length);
                                newRange.collapse(true);
                                selection.removeAllRanges();
                                selection.addRange(newRange);
                            } else {
                                // 如果最后一个节点不是文本节点，查找最后一个文本节点
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
                            // 如果格式元素为空，在格式元素位置创建文本节点
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

                // 对于 execCommand 支持的格式，检查格式元素后是否已有文本节点
                let nextTextNode = null;
                let nextSibling = formatElement.nextSibling;
                
                // 查找格式元素后的第一个文本节点
                while (nextSibling) {
                    if (nextSibling.nodeType === Node.TEXT_NODE) {
                        nextTextNode = nextSibling;
                        break;
                    } else if (nextSibling.nodeType === Node.ELEMENT_NODE) {
                        // 查找子元素中的第一个文本节点
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
                
                // 如果格式元素后已有文本节点，直接移动光标到那里（避免创建新节点）
                if (nextTextNode) {
                    const newRange = document.createRange();
                    newRange.setStart(nextTextNode, 0);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                } else {
                    // 如果没有文本节点，创建一个
                    const newTextNode = document.createTextNode('');
                    if (formatElement.nextSibling) {
                        parent.insertBefore(newTextNode, formatElement.nextSibling);
                    } else {
                        parent.appendChild(newTextNode);
                    }
                    
                    // 移动光标到新文本节点
                    const newRange = document.createRange();
                    newRange.setStart(newTextNode, 0);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                }
            } else {
                // 光标不在格式元素内，直接使用 execCommand 清除（仅对支持的格式）
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
         * 获取元素的最后一个文本节点
         * @param {Node} element - 元素
         * @returns {Node|null} 最后一个文本节点
         */
        getLastTextNode: function(element) {
            if (!element) return null;
            
            // 深度优先搜索最后一个文本节点
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
         * 
         * 参考 CKEditor 5 的思路：当应用格式时，如果光标在其他格式元素内，
         * 应该将光标移出，确保新应用的格式不会与其他格式冲突。
         * 
         * 注意：对于 execCommand 支持的格式（bold, italic, underline, strikethrough），
         * execCommand 会自动处理，这个方法主要用于高亮等自定义格式。
         * 
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @param {string} tagName - 标签名
         * @param {string} className - 类名
         */
        ensureCursorOutsideFormatElements: function(range, format, tagName, className) {
            // 对于 execCommand 支持的格式，不需要手动处理
            // execCommand 会自动处理光标位置和格式应用
            if (tagName && ['bold', 'italic', 'underline', 'strikethrough'].includes(format)) {
                return;
            }
            
            // 只对自定义格式（如高亮）需要手动处理
            const selection = window.getSelection();
            let container = range.commonAncestorContainer;
            let formatElement = null;
            
            // 向上查找所有可能的格式标签
            let current = container;
            while (current && current !== document.body) {
                if (current.nodeType === Node.ELEMENT_NODE) {
                    const tag = current.tagName ? current.tagName.toLowerCase() : '';
                    const hasClass = current.classList || false;
                    
                    // 检查是否是任何格式元素
                    const isFormatElement = 
                        tag === 'b' || tag === 'strong' ||  // 加粗
                        tag === 'i' || tag === 'em' ||      // 斜体
                        tag === 'u' ||                       // 下划线
                        tag === 's' || tag === 'strike' || tag === 'del' ||  // 删除线
                        (hasClass && current.classList.contains('mi-note-highlight'));  // 高亮
                    
                    if (isFormatElement) {
                        formatElement = current;
                        break;
                    }
                }
                current = current.parentElement || current.parentNode;
            }

            if (formatElement) {
                // 光标在格式元素内，需要移出
                const parent = formatElement.parentElement;
                if (parent) {
                    // 在格式元素后插入文本节点
                    const textNode = document.createTextNode('');
                    if (formatElement.nextSibling) {
                        parent.insertBefore(textNode, formatElement.nextSibling);
                    } else {
                        parent.appendChild(textNode);
                    }
                    
                    // 移动光标到文本节点
                    const newRange = document.createRange();
                    newRange.setStart(textNode, 0);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                }
            }
        },

        /**
         * 从选中文本中移除格式（参考 CKEditor 5 的 RemoveFormatCommand）
         * 
         * CKEditor 5 使用 writer.removeAttribute 在范围内移除格式属性
         * 我们使用 execCommand 实现类似效果
         * 
         * @param {Range} range - 选择范围
         * @param {string} format - 格式类型
         * @param {string} tagName - 标签名
         * @param {string} className - 类名
         */
        removeFormatFromSelection: function(range, format, tagName, className) {
            const selection = window.getSelection();
            
            // 方法1：优先使用 execCommand（最可靠，类似 CKEditor 5 的 writer.removeAttribute）
            // 但只对 execCommand 支持的格式（bold, italic, underline, strikethrough）使用
            if (tagName && !className) {
                try {
                    // execCommand 会自动处理选中文本的格式移除（记录历史）
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
            
            // 方法2：手动移除格式（当 execCommand 不可用或失败时，或自定义格式如高亮）
            // 主要用于高亮等自定义格式
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
                        // 检查是否是目标格式元素（支持所有变体）
                        if (tagName && (
                            tag === tagName || 
                            (tag === 'strong' && tagName === 'b') || 
                            (tag === 'em' && tagName === 'i') ||
                            (tag === 'strike' && tagName === 's') ||
                            (tag === 'del' && tagName === 's')
                        )) {
                            // 移除格式标签，保留内容（类似 CKEditor 5 的 unwrap）
                            while (node.firstChild) {
                                fragment.appendChild(node.firstChild);
                            }
                        } else if (className && node.classList && node.classList.contains(className)) {
                            // 移除高亮，保留内容
                            while (node.firstChild) {
                                fragment.appendChild(node.firstChild);
                            }
                        } else {
                            // 保留其他元素，但递归处理其子元素
                            const clonedNode = node.cloneNode(false);
                            const childFragment = document.createDocumentFragment();
                            let childNode = walker.nextNode();
                            while (childNode && childNode.parentNode === node) {
                                if (childNode.nodeType === Node.TEXT_NODE) {
                                    childFragment.appendChild(childNode.cloneNode(true));
                                } else if (childNode.nodeType === Node.ELEMENT_NODE) {
                                    // 递归处理子元素
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
                
                // 恢复选择（保持选中状态）
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
         * 应用标题格式（已移至 Format 模块，保留此方法以向后兼容）
         * @param {number} level - 标题级别 (0=清除, 1=大标题, 2=二级标题, 3=三级标题)
         * @returns {string} 状态信息
         */
        applyHeading: function(level) {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.applyHeading(level);
        },
        
        /**
         * 应用标题格式（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.applyHeading 代替
         */
        _applyHeadingOriginal: function(level) {
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选中文本或定位光标';
            }

            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const range = selection.getRangeAt(0);
            
            try {
                // 使用 DOMWriter 批量操作模式
                const domWriter = window.domWriter;
                if (!domWriter) {
                    return 'DOMWriter 未初始化';
                }
                domWriter.beginBatch();
                
                // 查找包含选中文本的文本元素
                let textElement = range.commonAncestorContainer;
                if (textElement.nodeType === Node.TEXT_NODE) {
                    textElement = textElement.parentElement;
                }

                // 向上查找 mi-note-text 元素
                while (textElement && !textElement.classList.contains('mi-note-text')) {
                    textElement = textElement.parentElement;
                }

                let targetNode = null;
                let targetOffset = 0;

                if (textElement && textElement.classList.contains('mi-note-text')) {
                    // 在文本元素中应用标题格式
                    if (level === 0) {
                        // 清除标题格式：移除所有标题 span
                        const titleSpans = textElement.querySelectorAll('.mi-note-size, .mi-note-mid-size, .mi-note-h3-size');
                        titleSpans.forEach(span => {
                            const parent = span.parentNode;
                            while (span.firstChild) {
                                parent.insertBefore(span.firstChild, span);
                            }
                            domWriter.removeNode(span);
                        });
                        // 光标位置：移动到文本元素开头
                        targetNode = textElement;
                        targetOffset = 0;
                    } else {
                        // 应用标题格式
                        let className = '';
                        if (level === 1) {
                            className = 'mi-note-size'; // 大标题 <size>
                        } else if (level === 2) {
                            className = 'mi-note-mid-size'; // 二级标题 <mid-size>
                        } else if (level === 3) {
                            className = 'mi-note-h3-size'; // 三级标题 <h3-size>
                        }

                        if (className && !range.collapsed) {
                            // 有选中文本，包装选中文本
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
                            // 光标位置，在文本元素开头插入标题 span
                            const titleSpan = document.createElement('span');
                            titleSpan.className = className;
                            titleSpan.innerHTML = '\u200B';
                            domWriter.insertNode(titleSpan, textElement, true);
                            targetNode = titleSpan;
                            targetOffset = 0;
                        }
                    }
                } else {
                    // 如果没有文本元素，创建新的文本元素并应用标题格式
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

                // 结束批量操作
                domWriter.endBatch({ type: 'apply-heading' });
                
                // 设置光标位置
                if (targetNode) {
                    requestAnimationFrame(() => {
                        const range2 = document.createRange();
                        range2.setStart(targetNode, targetOffset);
                        range2.collapse(true);
                        selection.removeAllRanges();
                        selection.addRange(range2);
                        
                        const notifyContentChanged = window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged;
                        const syncFormatState = window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.syncFormatState;
                        if (notifyContentChanged) {
                        notifyContentChanged();
                        }
                        if (syncFormatState) {
                        syncFormatState();
                        }
                    });
                } else {
                    notifyContentChanged();
                    requestAnimationFrame(() => {
                        if (!isComposing && !isLoadingContent) {
                            syncFormatState();
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
         * 应用对齐方式（已移至 Format 模块，保留此方法以向后兼容）
         * @param {string} alignment - 对齐方式 (left, center, right)
         * @returns {string} 状态信息
         */
        applyAlignment: function(alignment) {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.applyAlignment(alignment);
        },
        
        /**
         * 应用对齐方式（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.applyAlignment 代替
         */
        _applyAlignmentOriginal: function(alignment) {
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '没有选中文本';
            }

            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const range = selection.getRangeAt(0);
            
            // 查找包含选中文本的文本元素
            let textElement = range.commonAncestorContainer;
            if (textElement.nodeType === Node.TEXT_NODE) {
                textElement = textElement.parentElement;
            }

            // 向上查找 mi-note-text 元素
            while (textElement && !textElement.classList.contains('mi-note-text')) {
                textElement = textElement.parentElement;
            }

            if (!textElement || !textElement.classList.contains('mi-note-text')) {
                return '请选中文本元素';
            }

            try {
                // 使用 DOMWriter 批量操作模式
                const domWriter = window.domWriter;
                if (!domWriter) {
                    return 'DOMWriter 未初始化';
                }
                domWriter.beginBatch();
                
                // 移除现有的对齐类
                domWriter.setClass(textElement, 'center', false);
                domWriter.setClass(textElement, 'right', false);
                
                // 应用新的对齐方式
                if (alignment === 'center') {
                    domWriter.setClass(textElement, 'center', true);
                } else if (alignment === 'right') {
                    domWriter.setClass(textElement, 'right', true);
                }

                // 结束批量操作
                domWriter.endBatch({ type: 'apply-alignment' });
                
                const notifyContentChanged = window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged;
                const syncFormatState = window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.syncFormatState;
                if (notifyContentChanged) {
                notifyContentChanged();
                }
                // 格式操作后立即同步状态
                // 使用 requestAnimationFrame 确保状态检查在 DOM 更新后执行
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
         * 插入无序列表（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        insertBulletList: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.insertBulletList();
        },
        
        /**
         * 插入无序列表（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.insertBulletList 代替
         */
        _insertBulletListOriginal: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

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

            // 检查光标是否在文本元素中
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
                    // 提取内容（保留格式）
                    contentHTML = container.innerHTML;
                    // 清理零宽度空格
                    contentHTML = contentHTML.replace(/\u200B/g, '');
                }
            }

            // 使用 DOMWriter 批量操作模式
            const domWriter = window.domWriter;
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            domWriter.beginBatch();
            
            // 创建无序列表元素
            const bulletDiv = document.createElement('div');
            bulletDiv.className = 'mi-note-bullet';
            bulletDiv.style.paddingLeft = '0px'; // indent 1
            
            if (hasContent && textElement) {
                // 如果有内容，将内容放入列表项
                bulletDiv.innerHTML = contentHTML || '\u200B';
                // 替换文本元素
                domWriter.replaceNode(textElement, bulletDiv);
            } else if (textElement) {
                // 空文本元素，直接替换
                bulletDiv.innerHTML = '\u200B';
                domWriter.replaceNode(textElement, bulletDiv);
            } else {
                // 不在文本元素中，插入新元素
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

            // 移动光标到列表项内（如果有内容，移动到末尾；否则在开头）
            let targetNode = null;
            let targetOffset = 0;
            
            if (hasContent && bulletDiv.lastChild) {
                // 有内容，移动到末尾
                if (bulletDiv.lastChild.nodeType === Node.TEXT_NODE) {
                    targetNode = bulletDiv.lastChild;
                    targetOffset = bulletDiv.lastChild.textContent.length;
                } else {
                    targetNode = bulletDiv;
                    targetOffset = bulletDiv.childNodes.length;
                }
            } else {
                // 无内容，移动到开头
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
            
            // 结束批量操作（会自动处理光标和状态同步）
            domWriter.endBatch({ type: 'insert-bullet-list' });
            
            // 设置光标位置
            requestAnimationFrame(() => {
                const selection2 = window.getSelection();
                const range2 = document.createRange();
                range2.setStart(targetNode, targetOffset);
                range2.collapse(true);
                selection2.removeAllRanges();
                selection2.addRange(range2);
                
                notifyContentChanged();
                syncFormatState();
            });

            return '无序列表已插入';
        },

        /**
         * 插入有序列表（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        insertOrderList: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.insertOrderList();
        },
        
        /**
         * 插入有序列表（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.insertOrderList 代替
         */
        _insertOrderListOriginal: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

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

            // 检查光标是否在文本元素中
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
                    // 提取内容（保留格式）
                    contentHTML = container.innerHTML;
                    // 清理零宽度空格
                    contentHTML = contentHTML.replace(/\u200B/g, '');
                }
            }

            // 使用 DOMWriter 批量操作模式
            domWriter.beginBatch();
            
            // 创建有序列表元素
            const orderDiv = document.createElement('div');
            orderDiv.className = 'mi-note-order';
            orderDiv.setAttribute('data-number', '1');
            orderDiv.style.paddingLeft = '0px'; // indent 1
            
            if (hasContent && textElement) {
                // 如果有内容，将内容放入列表项
                orderDiv.innerHTML = contentHTML || '\u200B';
                // 替换文本元素
                domWriter.replaceNode(textElement, orderDiv);
            } else if (textElement) {
                // 空文本元素，直接替换
                orderDiv.innerHTML = '\u200B';
                domWriter.replaceNode(textElement, orderDiv);
            } else {
                // 不在文本元素中，插入新元素
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

            // 移动光标到列表项内（如果有内容，移动到末尾；否则在开头）
            let targetNode = null;
            let targetOffset = 0;
            
            if (hasContent && orderDiv.lastChild) {
                // 有内容，移动到末尾
                if (orderDiv.lastChild.nodeType === Node.TEXT_NODE) {
                    targetNode = orderDiv.lastChild;
                    targetOffset = orderDiv.lastChild.textContent.length;
                } else {
                    targetNode = orderDiv;
                    targetOffset = orderDiv.childNodes.length;
                }
            } else {
                // 无内容，移动到开头
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
            
            // 结束批量操作（会自动处理光标和状态同步）
            domWriter.endBatch({ type: 'insert-order-list' });
            
            // 设置光标位置
            requestAnimationFrame(() => {
                const selection2 = window.getSelection();
                const range2 = document.createRange();
                range2.setStart(targetNode, targetOffset);
                range2.collapse(true);
                selection2.removeAllRanges();
                selection2.addRange(range2);
                
                notifyContentChanged();
                syncFormatState();
            });

            return '有序列表已插入';
        },

        /**
         * 插入引用块（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        insertQuote: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.insertQuote();
        },
        
        /**
         * 插入引用块（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.insertQuote 代替
         */
        _insertQuoteOriginal: function() {
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

            // 创建引用块元素
            const quoteDiv = document.createElement('div');
            quoteDiv.className = 'mi-note-quote';

            // 创建引用块内的文本元素
            const textDiv = document.createElement('div');
            textDiv.className = 'mi-note-text indent-1';
            textDiv.innerHTML = '\u200B';
            quoteDiv.appendChild(textDiv);

            // 插入元素
            range.insertNode(quoteDiv);

            // 移动光标到引用块内
            range.selectNodeContents(textDiv);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);

            notifyContentChanged();
            // 格式操作后立即同步状态
            // 使用 requestAnimationFrame 确保状态检查在 DOM 更新后执行
            requestAnimationFrame(() => {
                if (!window.isComposing && !window.isLoadingContent) {
                    syncFormatState();
                }
            });
            return '引用块已插入';
        },

        /**
         * 插入复选框（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        insertCheckbox: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.insertCheckbox();
        },
        
        /**
         * 插入复选框（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.insertCheckbox 代替
         */
        _insertCheckboxOriginal: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }

            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }

            const selection = window.getSelection();
            let range = null;

            if (selection.rangeCount > 0) {
                range = selection.getRangeAt(0);
            } else {
                range = document.createRange();
                // 如果编辑器为空，直接添加到末尾
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    // 清空占位符
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            // 检查光标是否在文本元素中
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
                    // 提取内容（保留格式）
                    contentHTML = container.innerHTML;
                    // 清理零宽度空格
                    contentHTML = contentHTML.replace(/\u200B/g, '');
                }
            }

            // 使用 DOMWriter 批量操作模式
            domWriter.beginBatch();
            
            // 创建复选框元素
            const checkboxDiv = document.createElement('div');
            checkboxDiv.className = 'mi-note-checkbox';
            checkboxDiv.setAttribute('data-level', '3');
            checkboxDiv.style.paddingLeft = '0px'; // indent 1

            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkboxDiv.appendChild(checkbox);

            const span = document.createElement('span');
            if (hasContent && textElement) {
                // 如果有内容，将内容放入 span
                span.innerHTML = contentHTML || '\u200B';
            } else {
                span.innerHTML = '\u200B'; // 零宽度空格，确保光标可见
            }
            checkboxDiv.appendChild(span);

            if (textElement) {
                // 替换文本元素
                domWriter.replaceNode(textElement, checkboxDiv);
            } else {
                // 不在文本元素中，插入新元素
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

            // 移动光标到复选框的 span 内（如果有内容，移动到末尾；否则在开头）
            let targetNode = null;
            let targetOffset = 0;
            
            if (hasContent && span.lastChild) {
                // 有内容，移动到末尾
                if (span.lastChild.nodeType === Node.TEXT_NODE) {
                    targetNode = span.lastChild;
                    targetOffset = span.lastChild.textContent.length;
                } else {
                    targetNode = span;
                    targetOffset = span.childNodes.length;
                }
            } else {
                // 无内容，移动到开头
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
            
            // 结束批量操作（会自动处理光标和状态同步）
            domWriter.endBatch({ type: 'insert-checkbox' });
            
            // 设置光标位置
            requestAnimationFrame(() => {
                const selection2 = window.getSelection();
                const range2 = document.createRange();
                range2.setStart(targetNode, targetOffset);
                range2.collapse(true);
                selection2.removeAllRanges();
                selection2.addRange(range2);
                
                notifyContentChanged();
                syncFormatState();
            });

            return '复选框已插入';
        },

        /**
         * 插入分割线（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        insertHorizontalRule: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.insertHorizontalRule();
        },
        
        /**
         * 插入分割线（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.insertHorizontalRule 代替
         */
        _insertHorizontalRuleOriginal: function() {
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
                // 如果编辑器为空，直接添加到末尾
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    // 清空占位符
                    editor.innerHTML = '';
                }
                range.selectNodeContents(editor);
                range.collapse(false);
            }

            // 创建分割线元素
            const hr = document.createElement('hr');
            hr.className = 'mi-note-hr';

            // 插入元素
            range.insertNode(hr);

            // 在分割线后插入换行，确保可以继续输入
            const br = document.createElement('br');
            range.setStartAfter(hr);
            range.insertNode(br);

            // 移动光标到分割线后
            range.setStartAfter(br);
                    range.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(range);
                    
                    // 通知内容变化
                        notifyContentChanged();
            return '分割线已插入';
        },

        /**
         * 插入图片（已移至 Format 模块，保留此方法以向后兼容）
         * @param {string} imageUrl - 图片 URL
         * @param {string} altText - 替代文本（可选）
         * @returns {string} 状态信息
         */
        insertImage: function(imageUrl, altText) {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.insertImage(imageUrl, altText);
        },
        
        /**
         * 插入图片（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.insertImage 代替
         */
        _insertImageOriginal: function(imageUrl, altText) {
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
                // 如果编辑器为空，直接添加到末尾
                if (editor.childNodes.length === 0 || 
                    (editor.childNodes.length === 1 && editor.childNodes[0].classList && 
                     editor.childNodes[0].classList.contains('placeholder'))) {
                    // 清空占位符
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
            
            // 向上查找，检查是否在列表项（mi-note-bullet, mi-note-order）或待办项（mi-note-checkbox）中
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

            // 如果在列表项或待办项中，需要先退出
            if (listItem) {
                // 在列表项/待办项之后插入图片
                // 创建一个新的范围，定位到列表项之后
                let newRange = document.createRange();
                if (listItem.nextSibling) {
                    // 如果列表项后面有兄弟节点，在兄弟节点之前插入
                    newRange.setStartBefore(listItem.nextSibling);
                    newRange.collapse(true);
                    range = newRange;
                } else if (listItem.parentNode) {
                    // 如果列表项是最后一个，在父节点末尾插入
                    newRange.setStartAfter(listItem);
                    newRange.collapse(true);
                    range = newRange;
                }
                // 如果无法设置新范围（不应该发生），继续使用原来的 range
            }

            // 创建图片容器（使用 div 确保单独一行）
            const imageContainer = document.createElement('div');
            imageContainer.className = 'mi-note-image-container';
            imageContainer.style.margin = '8px 0'; // 添加上下边距，确保单独一行

            // 创建图片元素
            const img = document.createElement('img');
            img.src = imageUrl;
            img.alt = altText || '图片';
            img.className = 'mi-note-image';
            
            // 如果是 data URL，可以在这里处理
            // data URL 格式: data:image/png;base64,...
            if (imageUrl.startsWith('data:')) {
                // data URL 可以直接使用，不需要额外处理
                log.debug(LOG_MODULES.IMAGE, '插入 data URL 图片');
            } else if (imageUrl.startsWith('minote://')) {
                // 小米笔记的图片 URL 格式
                    log.debug(LOG_MODULES.IMAGE, '插入小米笔记图片', { imageUrl });
            }

            imageContainer.appendChild(img);

            // 插入图片容器
            range.insertNode(imageContainer);

            // 在图片后插入换行，确保可以继续输入
            const br = document.createElement('br');
            range.setStartAfter(imageContainer);
            range.insertNode(br);

            // 移动光标到图片后
            range.setStartAfter(br);
            range.collapse(true);
            selection.removeAllRanges();
            selection.addRange(range);
            
                // 通知内容变化
                    notifyContentChanged();
            return '图片已插入';
        },
        
        /**
         * 增加缩进（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        increaseIndent: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.increaseIndent();
        },
        
        /**
         * 增加缩进（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.increaseIndent 代替
         */
        _increaseIndentOriginal: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }
            
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选择内容';
            }
            
            const range = selection.getRangeAt(0);
            let container = range.commonAncestorContainer;
            
            // 如果是文本节点，获取父元素
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            // 向上查找，找到可缩进的元素（文本、列表、待办项）
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
            
            // 获取当前缩进级别
            const currentIndent = parseInt(getIndentFromElement(targetElement), 10);
            if (currentIndent >= 5) {
                return '已达到最大缩进级别';
            }
            
            // 使用 DOMWriter 批量操作
            domWriter.beginBatch();
            
            // 增加缩进
            setIndentForElement(targetElement, currentIndent + 1);
            
            // 结束批量操作
            domWriter.endBatch({ type: 'increase-indent' });
            
            // 通知内容变化
            notifyContentChanged();
            
            return '缩进已增加';
        },
        
        /**
         * 减少缩进（已移至 Format 模块，保留此方法以向后兼容）
         * @returns {string} 状态信息
         */
        decreaseIndent: function() {
            if (!FormatManager) {
                return '格式管理器未初始化';
            }
            return FormatManager.decreaseIndent();
        },
        
        /**
         * 减少缩进（原始实现，已移至 Format 模块）
         * @deprecated 使用 FormatManager.decreaseIndent 代替
         */
        _decreaseIndentOriginal: function() {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                return '编辑器元素不存在';
            }
            
            if (!domWriter) {
                return 'DOMWriter 未初始化';
            }
            
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return '请先选择内容';
            }
            
            const range = selection.getRangeAt(0);
            let container = range.commonAncestorContainer;
            
            // 如果是文本节点，获取父元素
            if (container.nodeType === Node.TEXT_NODE) {
                container = container.parentElement;
            }
            
            // 向上查找，找到可缩进的元素（文本、列表、待办项）
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
            
            // 获取当前缩进级别
            const currentIndent = parseInt(getIndentFromElement(targetElement), 10);
            if (currentIndent <= 1) {
                return '已达到最小缩进级别';
            }
            
            // 使用 DOMWriter 批量操作
            domWriter.beginBatch();
            
            // 减少缩进
            setIndentForElement(targetElement, currentIndent - 1);
            
            // 结束批量操作
            domWriter.endBatch({ type: 'decrease-indent' });
            
            // 通知内容变化
            notifyContentChanged();
            
            return '缩进已减少';
        }
    }); // 结束 Object.assign
    
    // 导出到全局命名空间
    // window.MiNoteWebEditor 已经在上面扩展
    
    // 同时导出到 MiNoteEditor 命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.API = window.MiNoteWebEditor;
    
})();
