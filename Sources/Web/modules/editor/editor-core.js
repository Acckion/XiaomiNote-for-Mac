/**
 * Editor Core 模块
 * 提供编辑器核心功能：内容加载、获取、状态同步
 * 依赖: logger, converter, cursor, dom-writer, command
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { 
        EDITOR: 'Editor', 
        CONVERTER: 'Converter', 
        CURSOR: 'Cursor',
        DOM_WRITER: 'DOMWriter',
        SYNC: 'Sync'
    };

    // 注意：以下全局变量需要在 editor.html 中定义
    // - currentContent
    // - isInitialized
    // - isLoadingContent
    // - isComposing
    // - domWriter
    // - commandManager
    // - xmlToHtmlConverter (或使用 window.MiNoteEditor.Converter)
    // - htmlToXmlConverter (或使用 window.MiNoteEditor.Converter)

    /**
     * 加载 XML 内容到编辑器
     * @param {string} xmlContent - 小米笔记 XML 格式内容
     * @returns {string} 状态信息
     */
    function loadContent(xmlContent) {
        const editor = document.getElementById('editor-content');
        if (!editor) {
            log.error(LOG_MODULES.EDITOR, '无法找到编辑器元素');
            return '编辑器元素不存在';
        }

        // 获取全局变量（这些变量在 editor.html 中定义）
        const isComposing = window.isComposing || false;
        const isLoadingContent = window.isLoadingContent || false;
        const currentContent = window.currentContent || '';
        const domWriter = window.domWriter;
        const xmlToHtmlConverter = window.xmlToHtmlConverter || 
            (window.MiNoteEditor && window.MiNoteEditor.Converter && window.MiNoteEditor.Converter.getXmlToHtmlConverter());

        // 如果正在组合输入，延迟加载（避免打断输入）
        if (isComposing) {
            log.debug(LOG_MODULES.EDITOR, '正在组合输入，延迟加载');
            // 延迟到组合输入结束后再加载
            setTimeout(() => {
                if (!window.isComposing) {
                    loadContent(xmlContent);
                }
            }, 100);
            return '延迟加载（组合输入中）';
        }

        log.debug(LOG_MODULES.EDITOR, '开始加载内容', { xmlLength: xmlContent ? xmlContent.length : 0 });

        // 如果内容没有实际变化，不需要重新加载（避免光标位置丢失）
        if (currentContent === xmlContent) {
            log.debug(LOG_MODULES.EDITOR, '内容未变化，跳过加载');
            return '内容未变化';
        }

        // 检查当前编辑器内容是否与要加载的内容相同（避免不必要的重新加载）
        const currentHtml = editor.innerHTML;
        // 排除占位符
        if (currentHtml && !currentHtml.includes('开始输入...') && !currentHtml.includes('placeholder')) {
            try {
                // 先比较 XML 内容（更快）
                if (currentContent === xmlContent) {
                    log.debug(LOG_MODULES.EDITOR, 'XML 内容相同，跳过加载');
                    // 清除待恢复的光标位置（因为不需要重新加载）
                    window._pendingCursorPosition = null;
                    window._hasPendingCursorPosition = false;
                    return '内容已是最新';
                }
                
                // 如果 XML 不同，再比较转换后的 HTML（更准确但更慢）
                const htmlToXmlConverter = window.htmlToXmlConverter || 
                    (window.MiNoteEditor && window.MiNoteEditor.Converter && window.MiNoteEditor.Converter.getHtmlToXmlConverter());
                if (htmlToXmlConverter) {
                    // 注意：在比较前，先保存当前光标位置，因为转换可能会影响 DOM
                    const savedPositionBeforeCompare = window.MiNoteWebEditor._saveCursorPosition();
                    const currentXml = htmlToXmlConverter.convert(currentHtml);
                    
                    // 规范化比较：去除末尾的空行差异（可能是转换导致的微小差异）
                    const normalizedCurrentXml = currentXml.replace(/\n+$/, '');
                    const normalizedXmlContent = xmlContent.replace(/\n+$/, '');
                    
                    if (normalizedCurrentXml === normalizedXmlContent) {
                        log.debug(LOG_MODULES.EDITOR, '编辑器内容与要加载的内容相同（规范化比较），跳过加载');
                        window.currentContent = xmlContent; // 更新 currentContent，但不重新加载
                        // 清除待恢复的光标位置（因为不需要重新加载）
                        window._pendingCursorPosition = null;
                        window._hasPendingCursorPosition = false;
                        
                        // 如果之前保存了光标位置，恢复它（因为转换可能影响了 DOM）
                        if (savedPositionBeforeCompare) {
                            requestAnimationFrame(() => {
                                window.MiNoteWebEditor._restoreCursorPosition(savedPositionBeforeCompare);
                            });
                        }
                        
                        return '内容已是最新';
                    }
                }
            } catch (e) {
                // 转换失败，继续加载
                log.warn(LOG_MODULES.CONVERTER, '检查内容是否相同时转换失败', { error: e.message });
            }
        }

        // 保存当前光标位置（在重新加载前）
        // 优先使用全局保存的位置（来自 notifyContentChanged），如果没有则保存当前位置
        const savedPosition = window._pendingCursorPosition || window.MiNoteWebEditor._saveCursorPosition();
        // 清除全局保存的位置，避免重复使用
        window._pendingCursorPosition = null;

        // 设置加载标志
        window.isLoadingContent = true;
        window.currentContent = xmlContent;
        
        // 清空操作历史（因为这是外部加载，不是用户操作）
        if (domWriter) {
            domWriter.clearHistory();
        }

        // 如果内容为空，显示占位符
        if (!xmlContent || xmlContent.trim() === '') {
            editor.innerHTML = '<div class="placeholder">开始输入...</div>';
            window.isLoadingContent = false;
            window.isInitialized = true;
            return '内容已加载（空内容）';
        }

        // 转换为 HTML
        try {
            // 错误边界检查：确保转换器已初始化
            if (!xmlToHtmlConverter) {
                throw new Error('XML 到 HTML 转换器未初始化');
            }
            
            const html = xmlToHtmlConverter.convert(xmlContent);
            
            // 错误边界检查：验证转换结果
            if (typeof html !== 'string') {
                throw new Error('转换结果不是字符串类型');
            }
            
            if (!html || html.trim() === '') {
                editor.innerHTML = '<div class="placeholder">开始输入...</div>';
            } else {
                // 尝试增量更新（减少 DOM 重新加载）
                const currentHtml = editor.innerHTML;
                try {
                    if (domWriter && currentHtml && !currentHtml.includes('开始输入...') && !currentHtml.includes('placeholder')) {
                        // 使用增量更新
                        const updated = domWriter.incrementalUpdate(html, currentHtml);
                        if (updated) {
                            log.debug(LOG_MODULES.DOM_WRITER, '使用增量更新', { htmlLength: html.length });
                        } else {
                            log.debug(LOG_MODULES.DOM_WRITER, '内容未变化（增量更新检查）', { htmlLength: html.length });
                        }
                    } else {
                        // 完全重新加载
                        editor.innerHTML = html;
                        log.debug(LOG_MODULES.EDITOR, '完全重新加载', { htmlLength: html.length });
                    }
                } catch (updateError) {
                    // 增量更新失败，回退到完全重新加载
                    log.warn(LOG_MODULES.DOM_WRITER, '增量更新失败，回退到完全重新加载', { error: updateError.message });
                    try {
                        editor.innerHTML = html;
                        log.debug(LOG_MODULES.EDITOR, '回退：完全重新加载', { htmlLength: html.length });
                    } catch (fallbackError) {
                        // 如果完全重新加载也失败，显示错误信息
                        log.error(LOG_MODULES.EDITOR, '完全重新加载也失败', { error: fallbackError.message });
                        editor.innerHTML = '<div class="placeholder">内容加载失败，请重试</div>';
                        window.isLoadingContent = false;
                        return '内容加载失败: ' + fallbackError.message;
                    }
                }
            }
            window.isInitialized = true;
            
            // 恢复光标位置（在 DOM 更新后）
            // 改进：使用双重 requestAnimationFrame 确保 DOM 完全渲染
            if (savedPosition) {
                try {
                    // 第一帧：等待 DOM 更新完成
                    requestAnimationFrame(() => {
                        try {
                            // 第二帧：确保浏览器完成渲染后再恢复光标
                            requestAnimationFrame(() => {
                                try {
                                    window.MiNoteWebEditor._restoreCursorPosition(savedPosition);
                                    // 恢复后清除标志
                                    window._hasPendingCursorPosition = false;
                                } catch (restoreError) {
                                    log.warn(LOG_MODULES.CURSOR, '恢复光标位置失败', { error: restoreError.message });
                                    // 最后的回退：将光标放到文档末尾
                                    try {
                                        const selection = window.getSelection();
                                        const range = document.createRange();
                                        range.selectNodeContents(editor);
                                        range.collapse(false);
                                        selection.removeAllRanges();
                                        selection.addRange(range);
                                    } catch (finalError) {
                                        log.error(LOG_MODULES.CURSOR, '回退光标位置也失败', { error: finalError.message });
                                    }
                                }
                            });
                        } catch (frameError) {
                            log.error(LOG_MODULES.CURSOR, 'requestAnimationFrame 失败', { error: frameError.message });
                        }
                    });
                } catch (scheduleError) {
                    log.error(LOG_MODULES.CURSOR, '调度光标恢复失败', { error: scheduleError.message });
                }
            } else {
                // 如果没有待恢复的位置，清除标志
                window._hasPendingCursorPosition = false;
            }
        } catch (error) {
            log.error(LOG_MODULES.CONVERTER, '转换失败', { 
                error: error.message, 
                stack: error.stack 
            });
            
            // 错误恢复：尝试显示原始内容或错误提示
            try {
                // 如果可能，尝试保留当前内容
                const currentHtml = editor.innerHTML;
                if (currentHtml && !currentHtml.includes('开始输入...') && !currentHtml.includes('placeholder')) {
                    log.info(LOG_MODULES.EDITOR, '转换失败，保留当前内容');
                    // 保留当前内容，但标记为未初始化
                    window.isInitialized = false;
                } else {
                    editor.innerHTML = '<div class="placeholder">内容加载失败，请重试</div>';
                }
            } catch (recoveryError) {
                log.error(LOG_MODULES.EDITOR, '错误恢复也失败', { error: recoveryError.message });
                editor.innerHTML = '<div class="placeholder">内容加载失败，请重试</div>';
            }
        } finally {
            window.isLoadingContent = false;
        }

        // 如果存在搜索文本，应用高亮
        if (window._currentSearchText && window.MiNoteWebEditor && window.MiNoteWebEditor.highlightSearchText) {
            // 延迟一点时间确保 DOM 完全渲染
            requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                    window.MiNoteWebEditor.highlightSearchText(window._currentSearchText);
                });
            });
        }

        return '内容已加载';
    }

    /**
     * 获取当前编辑器的内容并转换为 XML
     * @returns {string} 小米笔记 XML 格式内容
     */
    function getContent() {
        try {
            const editor = document.getElementById('editor-content');
            if (!editor) {
                log.error(LOG_MODULES.EDITOR, '无法找到编辑器元素');
                return '';
            }

            const htmlContent = editor.innerHTML;
            
            // 检查是否是占位符或空内容
            if (!htmlContent || 
                htmlContent.trim() === '' || 
                htmlContent.includes('开始输入...') ||
                htmlContent.trim() === '<div class="placeholder">开始输入...</div>') {
                return '';
            }

            // 错误边界检查：确保转换器已初始化
            const htmlToXmlConverter = window.htmlToXmlConverter || 
                (window.MiNoteEditor && window.MiNoteEditor.Converter && window.MiNoteEditor.Converter.getHtmlToXmlConverter());
            if (!htmlToXmlConverter) {
                log.error(LOG_MODULES.CONVERTER, 'HTML 到 XML 转换器未初始化');
                return '';
            }

            try {
                const xmlContent = htmlToXmlConverter.convert(htmlContent);
                
                // 错误边界检查：验证转换结果
                if (typeof xmlContent !== 'string') {
                    log.error(LOG_MODULES.CONVERTER, '转换结果不是字符串类型');
                    return '';
                }
                
                log.debug(LOG_MODULES.CONVERTER, '转换完成', { xmlLength: xmlContent.length });
                return xmlContent;
            } catch (error) {
                log.error(LOG_MODULES.CONVERTER, '转换失败', { 
                    error: error.message, 
                    stack: error.stack 
                });
                
                // 错误恢复：尝试返回一个基本的 XML 结构
                try {
                    // 如果转换失败，尝试提取纯文本并返回基本的 XML
                    const textContent = editor.textContent || editor.innerText || '';
                    if (textContent.trim()) {
                        log.warn(LOG_MODULES.CONVERTER, '转换失败，返回纯文本 XML');
                        return `<text>${textContent.trim()}</text>`;
                    }
                } catch (recoveryError) {
                    log.error(LOG_MODULES.CONVERTER, '错误恢复也失败', { error: recoveryError.message });
                }
                
                return '';
            }
        } catch (error) {
            log.error(LOG_MODULES.EDITOR, '获取内容失败', { 
                error: error.message, 
                stack: error.stack 
            });
            return '';
        }
    }

    /**
     * 修复光标位置（使用新的光标管理模块）
     * 确保光标位置始终有效，避免光标在不可编辑的元素内
     */
    function normalizeCursorPosition() {
        const editor = document.getElementById('editor-content');
        if (!editor) {
            return;
        }

        // 使用新的光标管理模块
        if (window.MiNoteEditor && window.MiNoteEditor.CursorModule) {
            return window.MiNoteEditor.CursorModule.normalizePosition(editor);
        }
        
        // 回退到原有的 Post-Fixer
        if (window.MiNoteEditor && window.MiNoteEditor.SelectionPostFixer) {
            const selection = window.getSelection();
            if (!selection || !selection.rangeCount) {
                return;
            }
            
            const postFixer = new window.MiNoteEditor.SelectionPostFixer(editor);
            return postFixer.fix(selection);
        }
        
        // 如果新模块不可用，使用原有的实现（保持向后兼容）
        const selection = window.getSelection();
        if (!selection.rangeCount) {
            return;
        }

        const range = selection.getRangeAt(0);
        if (!editor.contains(range.commonAncestorContainer)) {
            return;
        }

        try {
            // 对于折叠选择，找到最近的有效文本位置（类似 CKEditor 5 的 getNearestSelectionRange）
            if (range.collapsed) {
                let container = range.commonAncestorContainer;
                let needsFix = false;
                let fixedNode = null;
                let fixedOffset = 0;

                // 检查光标是否在不可编辑的元素内（如 checkbox、hr、image 等）
                let current = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
                while (current && current !== editor) {
                    const className = current.className || '';
                    const tagName = current.tagName ? current.tagName.toLowerCase() : '';
                    
                    // 如果光标在特殊元素内，需要移出
                    if (className.includes('mi-note-checkbox') || 
                        className.includes('mi-note-hr') ||
                        className.includes('mi-note-image') ||
                        tagName === 'hr' ||
                        tagName === 'img') {
                        needsFix = true;
                        // 在元素后查找或创建文本节点
                        const parent = current.parentElement;
                        if (parent) {
                            // 查找元素后的第一个文本节点
                            let nextNode = current.nextSibling;
                            while (nextNode) {
                                if (nextNode.nodeType === Node.TEXT_NODE) {
                                    fixedNode = nextNode;
                                    fixedOffset = 0;
                                    break;
                                } else if (nextNode.nodeType === Node.ELEMENT_NODE) {
                                    // 查找子元素中的第一个文本节点
                                    const walker = document.createTreeWalker(
                                        nextNode,
                                        NodeFilter.SHOW_TEXT,
                                        null
                                    );
                                    const firstText = walker.nextNode();
                                    if (firstText) {
                                        fixedNode = firstText;
                                        fixedOffset = 0;
                                        break;
                                    }
                                }
                                nextNode = nextNode.nextSibling;
                            }
                            
                            // 如果没找到文本节点，创建一个
                            if (!fixedNode) {
                                const textNode = document.createTextNode('');
                                if (current.nextSibling) {
                                    parent.insertBefore(textNode, current.nextSibling);
                                } else {
                                    parent.appendChild(textNode);
                                }
                                fixedNode = textNode;
                                fixedOffset = 0;
                            }
                        }
                        break;
                    }
                    current = current.parentElement;
                }

                // 如果光标在空文本节点中（只有零宽度空格），尝试移动到最近的文本节点
                if (!needsFix && container.nodeType === Node.TEXT_NODE) {
                    const textNode = container;
                    if (textNode.textContent === '\u200B' || 
                        (textNode.textContent.trim() === '' && textNode.textContent.length > 0)) {
                        // 尝试移动到相邻的非空文本节点
                        let nextNode = textNode.nextSibling;
                        let prevNode = textNode.previousSibling;
                        
                        // 优先移动到下一个文本节点
                        while (nextNode) {
                            if (nextNode.nodeType === Node.TEXT_NODE && nextNode.textContent.trim() !== '') {
                                fixedNode = nextNode;
                                fixedOffset = 0;
                                needsFix = true;
                                break;
                            } else if (nextNode.nodeType === Node.ELEMENT_NODE) {
                                // 查找子元素中的第一个文本节点
                                const walker = document.createTreeWalker(
                                    nextNode,
                                    NodeFilter.SHOW_TEXT,
                                    null
                                );
                                let node = walker.nextNode();
                                while (node) {
                                    if (node.textContent.trim() !== '') {
                                        fixedNode = node;
                                        fixedOffset = 0;
                                        needsFix = true;
                                        break;
                                    }
                                    node = walker.nextNode();
                                }
                                if (needsFix) break;
                            }
                            nextNode = nextNode.nextSibling;
                        }
                        
                        // 如果下一个节点没找到，尝试上一个节点
                        if (!needsFix) {
                            while (prevNode) {
                                if (prevNode.nodeType === Node.TEXT_NODE && prevNode.textContent.trim() !== '') {
                                    fixedNode = prevNode;
                                    fixedOffset = prevNode.textContent.length;
                                    needsFix = true;
                                    break;
                                } else if (prevNode.nodeType === Node.ELEMENT_NODE) {
                                    // 查找子元素中的最后一个文本节点
                                    const walker = document.createTreeWalker(
                                        prevNode,
                                        NodeFilter.SHOW_TEXT,
                                        null
                                    );
                                    let lastText = null;
                                    let node = walker.nextNode();
                                    while (node) {
                                        if (node.textContent.trim() !== '') {
                                            lastText = node;
                                        }
                                        node = walker.nextNode();
                                    }
                                    if (lastText) {
                                        fixedNode = lastText;
                                        fixedOffset = lastText.textContent.length;
                                        needsFix = true;
                                        break;
                                    }
                                }
                                prevNode = prevNode.previousSibling;
                            }
                        }
                        
                        // 如果都没找到，尝试移动到父元素的下一个文本节点
                        if (!needsFix && textNode.parentElement) {
                            const parent = textNode.parentElement;
                            let sibling = parent.nextSibling;
                            while (sibling) {
                                if (sibling.nodeType === Node.TEXT_NODE && sibling.textContent.trim() !== '') {
                                    fixedNode = sibling;
                                    fixedOffset = 0;
                                    needsFix = true;
                                    break;
                                }
                                sibling = sibling.nextSibling;
                            }
                        }
                    }
                }

                // 如果需要修复，更新选择
                if (needsFix && fixedNode) {
                    const newRange = document.createRange();
                    newRange.setStart(fixedNode, fixedOffset);
                    newRange.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(newRange);
                }
            }
        } catch (e) {
            // 忽略修复过程中的错误，避免影响正常编辑
            log.warn(LOG_MODULES.CURSOR, '修复光标位置失败', { error: e.message });
        }
    }

    /**
     * 同步格式状态到 Swift（用于更新格式菜单）
     * 参考 CKEditor 5 的实现：统一检查所有格式状态，包括文本格式、标题、列表、对齐方式
     * 改进：使用命令系统获取状态，支持状态缓存
     * 注意：在组合输入期间不触发，避免打断输入
     */
    function syncFormatState() {
        const isComposing = window.isComposing || false;
        if (isComposing) {
            return;
        }
        
        const selection = window.getSelection();
        if (!selection.rangeCount) {
            return;
        }

        const range = selection.getRangeAt(0);
        const commandManager = window.commandManager;
        
        // 如果命令管理器可用，优先使用命令系统获取状态
        let formatState = {};
        
        if (commandManager && window.MiNoteWebEditor) {
            // 使用命令系统批量获取格式状态
            const formatCommandNames = [
                'format:bold',
                'format:italic',
                'format:underline',
                'format:strikethrough',
                'format:highlight'
            ];
            
            const commandStates = commandManager.getStates(formatCommandNames, { range });
            
            formatState = {
                isBold: commandStates['format:bold']?.active || false,
                isItalic: commandStates['format:italic']?.active || false,
                isUnderline: commandStates['format:underline']?.active || false,
                isStrikethrough: commandStates['format:strikethrough']?.active || false,
                isHighlighted: commandStates['format:highlight']?.active || false
            };
            
            // 检查其他状态（标题、列表、对齐、引用）
            formatState.headingLevel = window.MiNoteWebEditor.checkHeadingLevel(range);
            formatState.listType = window.MiNoteWebEditor.checkListType(range);
            formatState.textAlignment = window.MiNoteWebEditor.checkTextAlignment(range);
            formatState.isInQuote = window.MiNoteWebEditor.checkQuoteState(range);
            
            // 如果命令管理器可用，检查命令可执行性
            const canExecuteStates = commandManager.canExecuteBatch(formatCommandNames, { range });
            formatState.canExecute = canExecuteStates;
        } else {
            // 回退到原有方法
            if (window.MiNoteWebEditor) {
                formatState = {
                    isBold: window.MiNoteWebEditor.checkFormatState(range, 'bold'),
                    isItalic: window.MiNoteWebEditor.checkFormatState(range, 'italic'),
                    isUnderline: window.MiNoteWebEditor.checkFormatState(range, 'underline'),
                    isStrikethrough: window.MiNoteWebEditor.checkFormatState(range, 'strikethrough'),
                    isHighlighted: window.MiNoteWebEditor.checkFormatState(range, 'highlight'),
                    headingLevel: window.MiNoteWebEditor.checkHeadingLevel(range),
                    listType: window.MiNoteWebEditor.checkListType(range),
                    textAlignment: window.MiNoteWebEditor.checkTextAlignment(range),
                    isInQuote: window.MiNoteWebEditor.checkQuoteState(range)
                };
            }
        }

        // 通知 Swift 更新格式状态
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorBridge) {
            window.webkit.messageHandlers.editorBridge.postMessage({
                type: 'formatStateChanged',
                formatState: formatState
            });
        }
    }

    /**
     * 通知内容已变化
     * 注意：在组合输入期间不触发，避免打断输入
     */
    function notifyContentChanged() {
        const isLoadingContent = window.isLoadingContent || false;
        const isInitialized = window.isInitialized || false;
        const isComposing = window.isComposing || false;
        const currentContent = window.currentContent || '';

        if (isLoadingContent || !isInitialized || isComposing) {
            return;
        }

        // 在获取内容前保存光标位置（防止后续重新加载时丢失）
        // 这很重要，因为 Swift 端可能会在保存后重新加载内容
        const savedPosition = window.MiNoteWebEditor._saveCursorPosition();
        
        const xmlContent = window.MiNoteWebEditor.getContent();
        
        // 更新当前内容
        if (currentContent !== xmlContent) {
            window.currentContent = xmlContent;
            
            // 如果内容变化了，保存光标位置到全局变量（供 loadContent 使用）
            // 这样即使 Swift 端重新加载内容，也能恢复光标位置
            // 但只在确实需要时才保存（避免不必要的保存）
            if (savedPosition) {
                window._pendingCursorPosition = savedPosition;
                // 设置一个标志，表示有待恢复的光标位置
                window._hasPendingCursorPosition = true;
            }
            
            // 通知 Swift
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorBridge) {
                const editor = document.getElementById('editor-content');
                const htmlContent = editor ? editor.innerHTML : '';
                window.webkit.messageHandlers.editorBridge.postMessage({
                    type: 'contentChanged',
                    content: xmlContent,
                    html: htmlContent
                });
            }
        } else {
            // 如果内容没有变化，清除待恢复的光标位置（避免使用过期的位置）
            window._pendingCursorPosition = null;
            window._hasPendingCursorPosition = false;
        }
        
        // 同步格式状态
        // 使用 requestAnimationFrame 确保状态检查在 DOM 更新后执行
        requestAnimationFrame(() => {
            if (!window.isComposing && !window.isLoadingContent) {
                syncFormatState();
            }
        });
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Editor = window.MiNoteEditor.Editor || {};
    window.MiNoteEditor.EditorCore = window.MiNoteEditor.EditorCore || {}; // 为了向后兼容，也导出到 EditorCore
    window.MiNoteEditor.Editor.loadContent = loadContent;
    window.MiNoteEditor.Editor.getContent = getContent;
    window.MiNoteEditor.Editor.normalizeCursorPosition = normalizeCursorPosition;
    window.MiNoteEditor.Editor.syncFormatState = syncFormatState;
    window.MiNoteEditor.Editor.notifyContentChanged = notifyContentChanged;
    // 向后兼容：也导出到 EditorCore
    window.MiNoteEditor.EditorCore.loadContent = loadContent;
    window.MiNoteEditor.EditorCore.getContent = getContent;
    window.MiNoteEditor.EditorCore.normalizeCursorPosition = normalizeCursorPosition;
    window.MiNoteEditor.EditorCore.syncFormatState = syncFormatState;
    window.MiNoteEditor.EditorCore.notifyContentChanged = notifyContentChanged;

    // 向后兼容：暴露到全局
    window.loadContent = loadContent;
    window.getContent = getContent;
    window.normalizeCursorPosition = normalizeCursorPosition;
    window.syncFormatState = syncFormatState;
    window.notifyContentChanged = notifyContentChanged;
    
    // 确保 window.MiNoteWebEditor 对象存在，并添加核心函数
    // 注意：Editor API 模块会扩展这个对象，添加其他 API 方法
    if (!window.MiNoteWebEditor) {
        window.MiNoteWebEditor = {};
    }
    window.MiNoteWebEditor.loadContent = loadContent;
    window.MiNoteWebEditor.getContent = getContent;
    
})();
