/**
 * Editor Init 模块
 * 处理编辑器初始化逻辑
 * 依赖: 所有模块（logger, converter, cursor, dom-writer, command, format, editor-core）
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { EDITOR: 'Editor' };

    // 注意：以下全局变量和函数需要在其他模块或 editor.html 中定义
    // - window.xmlToHtmlConverter
    // - window.htmlToXmlConverter
    // - window.domWriter
    // - window.commandManager
    // - window.isComposing
    // - window.isLoadingContent
    // - window.isInitialized
    // - window.currentContent
    // - window.contentChangeTimer
    // - window.formatStateSyncTimer
    // - window.MiNoteEditor.Converter (XMLToHTMLConverter, HTMLToXMLConverter)
    // - window.MiNoteEditor.DOMWriter (DOMWriter)
    // - window.MiNoteEditor.Command (CommandManager)
    // - window.MiNoteEditor.Command.registerFormatCommands
    // - window.MiNoteEditor.EditorCore (syncFormatState, notifyContentChanged, normalizeCursorPosition)
    // - window.MiNoteEditor.EnterHandler (回车键处理模块)

    /**
     * 初始化编辑器
     */
    function initEditor() {
        // 初始化转换器
        const XMLToHTMLConverter = window.MiNoteEditor && window.MiNoteEditor.Converter && window.MiNoteEditor.Converter.XMLToHTMLConverter;
        const HTMLToXMLConverter = window.MiNoteEditor && window.MiNoteEditor.Converter && window.MiNoteEditor.Converter.HTMLToXMLConverter;
        
        if (XMLToHTMLConverter) {
            window.xmlToHtmlConverter = new XMLToHTMLConverter();
        } else {
            log.error(LOG_MODULES.EDITOR, 'XMLToHTMLConverter 未找到');
        }
        
        if (HTMLToXMLConverter) {
            window.htmlToXmlConverter = new HTMLToXMLConverter();
        } else {
            log.error(LOG_MODULES.EDITOR, 'HTMLToXMLConverter 未找到');
        }

        const editor = document.getElementById('editor-content');
        if (!editor) {
            log.error(LOG_MODULES.EDITOR, '无法找到编辑器元素');
            return;
        }
        
        // 初始化 DOM Writer（统一 DOM 操作接口）
        const DOMWriter = window.MiNoteEditor && window.MiNoteEditor.DOMWriter;
        if (DOMWriter) {
            window.domWriter = new DOMWriter(editor);
        } else {
            log.error(LOG_MODULES.EDITOR, 'DOMWriter 未找到');
        }
        
        // 初始化命令管理器
        const CommandManager = window.MiNoteEditor && window.MiNoteEditor.Command && window.MiNoteEditor.Command.CommandManager;
        if (CommandManager && window.domWriter) {
            window.commandManager = new CommandManager(window.domWriter);
        } else {
            log.error(LOG_MODULES.EDITOR, 'CommandManager 未找到或 DOMWriter 未初始化');
        }
        
        // 注册格式命令
        const registerFormatCommands = window.MiNoteEditor && window.MiNoteEditor.Command && window.MiNoteEditor.Command.registerFormatCommands;
        if (registerFormatCommands && window.commandManager && window.domWriter) {
            registerFormatCommands(window.commandManager, window.domWriter);
        } else {
            log.error(LOG_MODULES.EDITOR, 'registerFormatCommands 未找到或依赖未初始化');
        }
            
        // 设置占位符
        if (!editor.innerHTML.trim()) {
            editor.innerHTML = '<div class="placeholder">开始输入...</div>';
        }

        // 组合输入开始（IME 输入法开始输入，如中文输入）
        editor.addEventListener('compositionstart', function() {
            window.isComposing = true;
            log.debug(LOG_MODULES.EDITOR, '组合输入开始');
            // 清除待处理的定时器，避免在组合输入期间触发
            if (window.contentChangeTimer) {
                clearTimeout(window.contentChangeTimer);
            }
            if (window.formatStateSyncTimer) {
                clearTimeout(window.formatStateSyncTimer);
            }
        });

        // 组合输入更新（IME 输入法输入过程中）
        editor.addEventListener('compositionupdate', function() {
            // 保持 isComposing 为 true
            window.isComposing = true;
        });

        // 组合输入结束（IME 输入法输入完成）
        editor.addEventListener('compositionend', function() {
            window.isComposing = false;
            log.debug(LOG_MODULES.EDITOR, '组合输入结束');
            // 组合输入结束后，延迟触发内容变化通知（等待 DOM 更新）
            setTimeout(function() {
                if (!window.isLoadingContent && !window.isComposing) {
                    // 尝试从多个位置获取 notifyContentChanged 函数
                    const notifyContentChanged = (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.notifyContentChanged) ||
                                                 (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged) ||
                                                 window.notifyContentChanged;
                    if (notifyContentChanged) {
                        notifyContentChanged();
                    }
                }
            }, 50); // 50ms 延迟，确保 DOM 更新完成
        });

        // 内容变化监听（防抖处理）
        // 注意：在组合输入期间不触发，避免打断输入
        editor.addEventListener('input', function(e) {
            if (window.isLoadingContent || window.isComposing) {
                return;
            }
            if (window.contentChangeTimer) {
                clearTimeout(window.contentChangeTimer);
            }
            window.contentChangeTimer = setTimeout(function() {
                if (!window.isComposing) {
                    // 尝试从多个位置获取 notifyContentChanged 函数
                    const notifyContentChanged = (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.notifyContentChanged) ||
                                                 (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged) ||
                                                 window.notifyContentChanged;
                    if (notifyContentChanged) {
                        notifyContentChanged();
                    }
                }
            }, 300); // 300ms 防抖
        });

        // 选择变化监听（用于同步格式状态）
        // 参考 CKEditor 5：在 selectionchange 时同步所有格式状态
        // 注意：不要在这里修复光标位置，避免与格式操作冲突导致光标跳动
        // 注意：在组合输入期间不触发，避免打断输入
        document.addEventListener('selectionchange', function() {
            if (window.isLoadingContent || !window.isInitialized || window.isComposing) {
                return;
            }
            // 延迟同步，避免频繁更新
            // 使用 requestAnimationFrame 确保状态检查在 DOM 更新后执行
            if (window.formatStateSyncTimer) {
                clearTimeout(window.formatStateSyncTimer);
            }
            window.formatStateSyncTimer = setTimeout(function() {
                if (!window.isComposing) {
                    requestAnimationFrame(() => {
                        if (!window.isComposing && !window.isLoadingContent) {
                            // 尝试从多个位置获取 syncFormatState 函数
                            const syncFormatState = (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.syncFormatState) ||
                                                   (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.syncFormatState) ||
                                                   window.syncFormatState;
                            if (syncFormatState) {
                                syncFormatState();
                            }
                        }
                    });
                }
            }, 30); // 减少防抖延迟到 30ms，提高响应速度
        });

        // 输入事件时也同步格式状态（参考 CKEditor 5）
        // 注意：在组合输入期间不触发，避免打断输入
        editor.addEventListener('input', function() {
            if (window.isLoadingContent || !window.isInitialized || window.isComposing) {
                return;
            }
            // 延迟同步，避免频繁更新
            // 使用 requestAnimationFrame 确保状态检查在 DOM 更新后执行
            if (window.formatStateSyncTimer) {
                clearTimeout(window.formatStateSyncTimer);
            }
            window.formatStateSyncTimer = setTimeout(function() {
                if (!window.isComposing) {
                    requestAnimationFrame(() => {
                        if (!window.isComposing && !window.isLoadingContent) {
                            // 尝试从多个位置获取 syncFormatState 函数
                            const syncFormatState = (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.syncFormatState) ||
                                                   (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.syncFormatState) ||
                                                   window.syncFormatState;
                            if (syncFormatState) {
                                syncFormatState();
                            }
                        }
                    });
                }
            }, 30); // 减少防抖延迟到 30ms，提高响应速度
        });

        // 键盘事件时也同步格式状态（参考 CKEditor 5）
        // 注意：在组合输入期间不触发，避免打断输入
        editor.addEventListener('keyup', function() {
            if (window.isLoadingContent || !window.isInitialized || window.isComposing) {
                return;
            }
            // 延迟同步，避免频繁更新
            // 使用 requestAnimationFrame 确保状态检查在 DOM 更新后执行
            if (window.formatStateSyncTimer) {
                clearTimeout(window.formatStateSyncTimer);
            }
            window.formatStateSyncTimer = setTimeout(function() {
                if (!window.isComposing) {
                    requestAnimationFrame(() => {
                        if (!window.isComposing && !window.isLoadingContent) {
                            // 尝试从多个位置获取 syncFormatState 函数
                            const syncFormatState = (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.syncFormatState) ||
                                                   (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.syncFormatState) ||
                                                   window.syncFormatState;
                            if (syncFormatState) {
                                syncFormatState();
                            }
                        }
                    });
                }
            }, 30); // 减少防抖延迟到 30ms，提高响应速度
        });

        // 处理回车键事件
        // 注意：在组合输入期间不处理，避免打断输入
        // 使用 capture 阶段捕获事件，确保在其他处理之前执行
        editor.addEventListener('keydown', function(e) {
            if (window.isComposing) {
                return; // 组合输入期间不处理
            }
            if (e.key === 'Enter' && !e.shiftKey) {
                // 在处理回车键之前，先检查是否在 checkbox、bullet 或 order 中
                // 如果是，立即阻止默认行为，避免浏览器创建额外的元素
                const selection = window.getSelection();
                if (selection && selection.rangeCount > 0) {
                    const range = selection.getRangeAt(0);
                    let container = range.commonAncestorContainer;
                    if (container.nodeType === Node.TEXT_NODE) {
                        container = container.parentElement;
                    }
                    
                    let current = container;
                    while (current && current !== editor) {
                        if (current.classList && (
                            current.classList.contains('mi-note-checkbox') ||
                            current.classList.contains('mi-note-bullet') ||
                            current.classList.contains('mi-note-order')
                        )) {
                            // 在特殊元素中，立即阻止默认行为
                            e.preventDefault();
                            e.stopPropagation();
                            // 尝试从多个位置获取 handleEnterKey 函数
                            const handleEnterKey = (window.MiNoteEditor && window.MiNoteEditor.EnterHandler && window.MiNoteEditor.EnterHandler.handleEnterKey) ||
                                                 window.handleEnterKey;
                            if (handleEnterKey) {
                                handleEnterKey(e);
                            }
                            return;
                        }
                        current = current.parentElement;
                    }
                }
                
                // 不在特殊元素中，正常处理
                // 尝试从多个位置获取 handleEnterKey 函数
                const handleEnterKey = (window.MiNoteEditor && window.MiNoteEditor.EnterHandler && window.MiNoteEditor.EnterHandler.handleEnterKey) ||
                                     window.handleEnterKey;
                if (handleEnterKey) {
                    handleEnterKey(e);
                }
            }
        }, true); // 使用 capture 阶段，确保在其他处理之前执行

        // 使用 MutationObserver 监听 DOM 变化，自动修复光标位置（参考 CKEditor 5 的 Selection Post-Fixer）
        // 这确保在每次 DOM 操作后，光标位置都是有效的
        let mutationObserverTimer = null;
        const mutationObserver = new MutationObserver(function(mutations) {
            // 只在非加载内容时修复光标位置
            if (window.isLoadingContent || !window.isInitialized || window.isComposing) {
                return;
            }
            
            // 防抖处理，避免频繁调用 normalizeCursorPosition
            if (mutationObserverTimer) {
                clearTimeout(mutationObserverTimer);
            }
            mutationObserverTimer = setTimeout(() => {
                // 延迟修复，确保 DOM 操作完成
                    requestAnimationFrame(() => {
                        if (!window.isComposing && !window.isLoadingContent) {
                            // 尝试从多个位置获取 normalizeCursorPosition 函数
                            const normalizeCursorPosition = (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.normalizeCursorPosition) ||
                                                           (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.normalizeCursorPosition) ||
                                                           window.normalizeCursorPosition;
                            if (normalizeCursorPosition) {
                                normalizeCursorPosition();
                            }
                        }
                    });
            }, 10); // 10ms 防抖，平衡响应速度和性能
        });
        
        // 开始监听 DOM 变化
        mutationObserver.observe(editor, {
            childList: true,      // 监听子节点的添加和删除
            subtree: true,        // 监听所有后代节点
            characterData: true,  // 监听文本内容变化
            attributes: false     // 不监听属性变化（避免频繁触发）
        });

        // 语音占位符点击事件处理 
        editor.addEventListener('click', function(e) {
            // 查找点击的语音占位符元素
            let target = e.target;
            let soundElement = null;
            
            // 向上查找 .mi-note-sound 元素
            while (target && target !== editor) {
                if (target.classList && target.classList.contains('mi-note-sound')) {
                    soundElement = target;
                    break;
                }
                target = target.parentElement;
            }
            
            if (soundElement) {
                const fileId = soundElement.getAttribute('data-fileid');
                if (fileId) {
                    log.debug(LOG_MODULES.EDITOR, '点击语音占位符', { fileId });
                    
                    // 通过 WebKit 消息处理器通知 Swift 
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorBridge) {
                        window.webkit.messageHandlers.editorBridge.postMessage({
                            type: 'playAudio',
                            fileId: fileId
                        });
                    }
                    
                    // 阻止事件冒泡，避免触发其他点击处理
                    e.preventDefault();
                    e.stopPropagation();
                }
            }
        });

        // 初始化完成
        window.isInitialized = true;
        log.info(LOG_MODULES.EDITOR, '编辑器初始化完成');

        // 通知 Swift 编辑器已准备好
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorBridge) {
            window.webkit.messageHandlers.editorBridge.postMessage({
                type: 'editorReady'
            });
        }
    }

    // 等待 DOM 加载完成
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initEditor);
    } else {
        // DOM 已经加载完成，直接初始化
        initEditor();
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Init = {
        initEditor: initEditor
    };
    
})();

