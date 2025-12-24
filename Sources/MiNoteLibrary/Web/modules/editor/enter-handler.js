/**
 * Enter Handler 模块
 * 处理回车键事件，包括 checkbox、bullet、order 列表的处理
 * 依赖: logger, constants, utils
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { EDITOR: 'Editor', LIST: 'List' };
    const getIndentFromElement = window.getIndentFromElement || (window.MiNoteEditor && window.MiNoteEditor.Utils && window.MiNoteEditor.Utils.getIndentFromElement);
    const getNotifyContentChanged = () => {
        return (window.MiNoteEditor && window.MiNoteEditor.Editor && window.MiNoteEditor.Editor.notifyContentChanged) ||
               (window.MiNoteEditor && window.MiNoteEditor.EditorCore && window.MiNoteEditor.EditorCore.notifyContentChanged) ||
               window.notifyContentChanged;
    };

    // ==================== Enter Key Handler ====================
    
    /**
     * 处理回车键事件
     * @param {KeyboardEvent} e - 键盘事件
     */
    function handleEnterKey(e) {
        // 如果正在组合输入，不处理回车键（避免打断输入）
        if (window.isComposing) {
            return;
        }
        
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        const selection = window.getSelection();
        if (!selection.rangeCount) {
            return;
        }

        const range = selection.getRangeAt(0);
        const container = range.commonAncestorContainer;
        
        // 查找当前所在的元素
        let currentNode = container;
        if (container.nodeType === Node.TEXT_NODE) {
            currentNode = container.parentElement;
        } else if (container.nodeType === Node.ELEMENT_NODE) {
            currentNode = container;
        }

        // 向上查找 checkbox、bullet 或 order 元素
        let checkboxElement = null;
        let bulletElement = null;
        let orderElement = null;
        let current = currentNode;
        
        while (current && current !== editor) {
            if (current.classList && current.classList.contains('mi-note-checkbox')) {
                checkboxElement = current;
                break;
            }
            if (current.classList && current.classList.contains('mi-note-bullet')) {
                bulletElement = current;
                break;
            }
            if (current.classList && current.classList.contains('mi-note-order')) {
                orderElement = current;
                break;
            }
            current = current.parentElement;
        }

        // 处理 checkbox 回车
        if (checkboxElement) {
            e.preventDefault();
            e.stopPropagation(); // 阻止事件冒泡，确保不会触发其他处理
            e.stopImmediatePropagation(); // 立即停止事件传播
            
            // 检查是否为空，如果为空则转换为普通正文
            if (isCheckboxEmpty(checkboxElement)) {
                convertCheckboxToText(checkboxElement);
            } else {
                createNewCheckbox(checkboxElement);
            }
            return false; // 确保返回 false，进一步阻止默认行为
        }

        // 处理无序列表回车
        if (bulletElement) {
            e.preventDefault();
            // 检查是否为空，如果为空则转换为普通正文
            if (isBulletEmpty(bulletElement)) {
                convertBulletToText(bulletElement);
            } else {
                createNewBullet(bulletElement);
            }
            return;
        }

        // 处理有序列表回车
        if (orderElement) {
            e.preventDefault();
            // 检查是否为空，如果为空则转换为普通正文
            if (isOrderEmpty(orderElement)) {
                convertOrderToText(orderElement);
            } else {
                createNewOrder(orderElement);
            }
            return;
        }
    }

    /**
     * 创建新的 checkbox
     * @param {HTMLElement} currentCheckbox - 当前的 checkbox 元素
     */
    function createNewCheckbox(currentCheckbox) {
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        // 检查是否已经有下一个 checkbox（防止重复创建）
        // 如果下一个兄弟节点已经是 checkbox，说明可能已经创建过了
        if (currentCheckbox.nextSibling && 
            currentCheckbox.nextSibling.classList && 
            currentCheckbox.nextSibling.classList.contains('mi-note-checkbox')) {
            // 已经有下一个 checkbox，直接移动光标到那里
            const nextCheckbox = currentCheckbox.nextSibling;
            const nextSpan = nextCheckbox.querySelector('span');
            if (nextSpan) {
                const selection = window.getSelection();
                const range = document.createRange();
                if (nextSpan.firstChild && nextSpan.firstChild.nodeType === Node.TEXT_NODE) {
                    range.setStart(nextSpan.firstChild, 0);
                } else {
                    range.selectNodeContents(nextSpan);
                }
                range.collapse(true);
                selection.removeAllRanges();
                selection.addRange(range);
            }
            return;
        }
        
        const indent = getIndentFromElement(currentCheckbox);
        const level = currentCheckbox.getAttribute('data-level') || '3';

        // 创建新的 checkbox
        const newCheckbox = document.createElement('div');
        newCheckbox.className = 'mi-note-checkbox';
        newCheckbox.setAttribute('data-level', level);
        newCheckbox.style.paddingLeft = currentCheckbox.style.paddingLeft || '0px';

        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        newCheckbox.appendChild(checkbox);

        const span = document.createElement('span');
        span.innerHTML = '\u200B';
        newCheckbox.appendChild(span);

        // 插入到当前 checkbox 之后
        if (currentCheckbox.nextSibling) {
            editor.insertBefore(newCheckbox, currentCheckbox.nextSibling);
        } else {
            editor.appendChild(newCheckbox);
        }

        // 立即设置光标到新 checkbox，避免浏览器默认行为
        // 使用双重 requestAnimationFrame 确保 DOM 更新完成后再设置光标
        requestAnimationFrame(() => {
            requestAnimationFrame(() => {
                const selection = window.getSelection();
                if (!selection) return;
                
                const range = document.createRange();
                // 确保选择 span 内的文本节点，而不是整个 span
                if (span.firstChild && span.firstChild.nodeType === Node.TEXT_NODE) {
                    range.setStart(span.firstChild, 0);
                } else {
                    range.selectNodeContents(span);
                }
                range.collapse(true);
                selection.removeAllRanges();
                selection.addRange(range);
                
                // 延迟通知内容变化，确保光标位置已设置
                setTimeout(() => {
                    const notifyContentChanged = getNotifyContentChanged();
                    if (notifyContentChanged) {
                        notifyContentChanged();
                    }
                }, 0);
            });
        });
    }

    /**
     * 创建新的无序列表项
     * @param {HTMLElement} currentBullet - 当前的无序列表项
     */
    function createNewBullet(currentBullet) {
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        const indent = getIndentFromElement(currentBullet);

        // 创建新的 bullet
        const newBullet = document.createElement('div');
        newBullet.className = 'mi-note-bullet';
        newBullet.style.paddingLeft = currentBullet.style.paddingLeft || '0px';
        newBullet.innerHTML = '\u200B';

        // 插入到当前 bullet 之后
        if (currentBullet.nextSibling) {
            editor.insertBefore(newBullet, currentBullet.nextSibling);
        } else {
            editor.appendChild(newBullet);
        }

        // 设置光标到新 bullet
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(newBullet);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);

        const notifyContentChanged = getNotifyContentChanged();
        if (notifyContentChanged) {
            notifyContentChanged();
        }
    }

    /**
     * 创建新的有序列表项
     * @param {HTMLElement} currentOrder - 当前的有序列表项
     */
    function createNewOrder(currentOrder) {
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        const indent = getIndentFromElement(currentOrder);
        const currentNumber = parseInt(currentOrder.getAttribute('data-number') || '1', 10);
        const nextNumber = currentNumber + 1;

        // 创建新的 order
        const newOrder = document.createElement('div');
        newOrder.className = 'mi-note-order';
        newOrder.setAttribute('data-number', nextNumber.toString());
        newOrder.style.paddingLeft = currentOrder.style.paddingLeft || '0px';
        newOrder.innerHTML = '\u200B';

        // 插入到当前 order 之后
        if (currentOrder.nextSibling) {
            editor.insertBefore(newOrder, currentOrder.nextSibling);
        } else {
            editor.appendChild(newOrder);
        }

        // 设置光标到新 order 的内容区域（确保可以正常输入和换行）
        const selection = window.getSelection();
        const range = document.createRange();
        // 直接选择列表项的内容，而不是整个节点
        if (newOrder.firstChild && newOrder.firstChild.nodeType === Node.TEXT_NODE) {
            range.setStart(newOrder.firstChild, 0);
            range.collapse(true);
        } else {
            // 如果没有文本节点，创建一个
            const textNode = document.createTextNode('\u200B');
            newOrder.appendChild(textNode);
            range.setStart(textNode, 0);
            range.collapse(true);
        }
        selection.removeAllRanges();
        selection.addRange(range);
        
        const notifyContentChanged = getNotifyContentChanged();
        if (notifyContentChanged) {
            notifyContentChanged();
        }
    }

    /**
     * 检查 checkbox 是否为空
     * @param {HTMLElement} checkboxElement - checkbox 元素
     * @returns {boolean} 是否为空
     */
    function isCheckboxEmpty(checkboxElement) {
        // 查找 span 元素（checkbox 的内容在 span 中）
        const span = checkboxElement.querySelector('span');
        if (!span) {
            return true;
        }
        
        // 获取文本内容，去除零宽空格和空白字符
        const text = span.textContent || span.innerText || '';
        const trimmedText = text.replace(/\u200B/g, '').trim();
        
        return trimmedText === '';
    }

    /**
     * 检查无序列表项是否为空
     * @param {HTMLElement} bulletElement - 无序列表项元素
     * @returns {boolean} 是否为空
     */
    function isBulletEmpty(bulletElement) {
        // 获取文本内容，去除零宽空格和空白字符
        const text = bulletElement.textContent || bulletElement.innerText || '';
        const trimmedText = text.replace(/\u200B/g, '').trim();
        
        return trimmedText === '';
    }

    /**
     * 检查有序列表项是否为空
     * @param {HTMLElement} orderElement - 有序列表项元素
     * @returns {boolean} 是否为空
     */
    function isOrderEmpty(orderElement) {
        // 获取文本内容，去除零宽空格和空白字符
        const text = orderElement.textContent || orderElement.innerText || '';
        const trimmedText = text.replace(/\u200B/g, '').trim();
        
        return trimmedText === '';
    }

    /**
     * 将 checkbox 转换为普通正文
     * @param {HTMLElement} checkboxElement - checkbox 元素
     */
    function convertCheckboxToText(checkboxElement) {
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        // 获取缩进级别
        const indent = getIndentFromElement(checkboxElement);
        
        // 创建普通正文元素
        const textDiv = document.createElement('div');
        textDiv.className = 'mi-note-text indent-' + indent;
        textDiv.innerHTML = '\u200B';
        
        // 替换 checkbox 元素
        if (checkboxElement.nextSibling) {
            editor.insertBefore(textDiv, checkboxElement.nextSibling);
        } else {
            editor.appendChild(textDiv);
        }
        editor.removeChild(checkboxElement);
        
        // 设置光标到新文本元素
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(textDiv);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        
        const notifyContentChanged = getNotifyContentChanged();
        if (notifyContentChanged) {
            notifyContentChanged();
        }
    }

    /**
     * 将无序列表项转换为普通正文
     * @param {HTMLElement} bulletElement - 无序列表项元素
     */
    function convertBulletToText(bulletElement) {
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        // 获取缩进级别
        const indent = getIndentFromElement(bulletElement);
        
        // 创建普通正文元素
        const textDiv = document.createElement('div');
        textDiv.className = 'mi-note-text indent-' + indent;
        textDiv.innerHTML = '\u200B';
        
        // 替换 bullet 元素
        if (bulletElement.nextSibling) {
            editor.insertBefore(textDiv, bulletElement.nextSibling);
        } else {
            editor.appendChild(textDiv);
        }
        editor.removeChild(bulletElement);
        
        // 设置光标到新文本元素
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(textDiv);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        
        const notifyContentChanged = getNotifyContentChanged();
        if (notifyContentChanged) {
            notifyContentChanged();
        }
    }

    /**
     * 将有序列表项转换为普通正文
     * @param {HTMLElement} orderElement - 有序列表项元素
     */
    function convertOrderToText(orderElement) {
        const editor = document.getElementById('editor-content');
        if (!editor) return;
        
        // 获取缩进级别
        const indent = getIndentFromElement(orderElement);
        
        // 创建普通正文元素
        const textDiv = document.createElement('div');
        textDiv.className = 'mi-note-text indent-' + indent;
        textDiv.innerHTML = '\u200B';
        
        // 替换 order 元素
        if (orderElement.nextSibling) {
            editor.insertBefore(textDiv, orderElement.nextSibling);
        } else {
            editor.appendChild(textDiv);
        }
        editor.removeChild(orderElement);
        
        // 设置光标到新文本元素
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(textDiv);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
        
        const notifyContentChanged = getNotifyContentChanged();
        if (notifyContentChanged) {
            notifyContentChanged();
        }
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.EnterHandler = {
        handleEnterKey: handleEnterKey,
        createNewCheckbox: createNewCheckbox,
        createNewBullet: createNewBullet,
        createNewOrder: createNewOrder,
        isCheckboxEmpty: isCheckboxEmpty,
        isBulletEmpty: isBulletEmpty,
        isOrderEmpty: isOrderEmpty,
        convertCheckboxToText: convertCheckboxToText,
        convertBulletToText: convertBulletToText,
        convertOrderToText: convertOrderToText
    };
    
    // 向后兼容：暴露到全局
    window.handleEnterKey = handleEnterKey;

})();


