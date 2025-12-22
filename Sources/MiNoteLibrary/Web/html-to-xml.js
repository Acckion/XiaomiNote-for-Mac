/**
 * HTML to XML Converter
 * 将编辑器中的 HTML 内容转换为小米笔记 XML 格式，用于保存
 */

class HTMLToXMLConverter {
    constructor() {
        // 有序列表状态跟踪
        this.orderListState = {
            lastIndent: null,
            lastNumber: null,
            isInContinuousList: false
        };
    }

    /**
     * 主转换方法：将 HTML 内容转换为 XML
     * @param {string} htmlContent - HTML 内容
     * @returns {string} 小米笔记 XML 格式内容
     */
    convert(htmlContent) {
        if (!htmlContent || htmlContent.trim() === '') {
            return '';
        }

        // 重置有序列表状态
        this.orderListState = {
            lastIndent: null,
            lastNumber: null,
            isInContinuousList: false
        };

        // 创建临时 div 来解析 HTML
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = htmlContent;

        let xmlLines = [];

        // 遍历所有子节点
        const nodes = tempDiv.childNodes;
        for (let node of nodes) {
            const result = this.processNode(node);
            if (result) {
                if (Array.isArray(result)) {
                    xmlLines.push(...result);
                } else {
                    xmlLines.push(result);
                }
            }
        }

        return xmlLines.join('\n');
    }

    /**
     * 处理单个 DOM 节点
     * @param {Node} node - DOM 节点
     * @returns {string|string[]|null} XML 行或行数组，null 表示跳过
     */
    processNode(node) {
        if (node.nodeType === Node.ELEMENT_NODE) {
            const tagName = node.tagName ? node.tagName.toLowerCase() : '';
            const className = node.className || '';

            // 检查是否是特殊元素
            const isSpecialElement = 
                className.includes('mi-note-bullet') ||
                className.includes('mi-note-order') ||
                className.includes('mi-note-checkbox') ||
                className.includes('mi-note-hr') ||
                className.includes('mi-note-quote') ||
                className.includes('mi-note-image') ||
                tagName === 'hr' ||
                tagName === 'blockquote' ||
                tagName === 'img';

            if (isSpecialElement) {
                return this.convertNodeToXML(node);
            } else if (className.includes('mi-note-text') || tagName === 'div' || tagName === 'p') {
                // 处理文本元素，检查是否包含嵌套的特殊元素
                const hasSpecialChildren = node.querySelector(
                    '.mi-note-bullet, .mi-note-order, .mi-note-checkbox, .mi-note-hr, .mi-note-quote, .mi-note-image, hr, blockquote, img'
                );

                if (hasSpecialChildren) {
                    // 如果包含特殊子元素，递归处理子节点
                    let results = [];
                    const children = node.childNodes;
                    for (let child of children) {
                        const result = this.processNode(child);
                        if (result) {
                            if (Array.isArray(result)) {
                                results.push(...result);
                            } else {
                                results.push(result);
                            }
                        }
                    }
                    return results.length > 0 ? results : null;
                } else {
                    // 普通文本元素
                    const result = this.convertNodeToXML(node);
                    if (result) {
                        // 文本元素会中断有序列表的连续性
                        this.orderListState.isInContinuousList = false;
                        this.orderListState.lastIndent = null;
                        this.orderListState.lastNumber = null;
                    }
                    return result;
                }
            } else {
                // 其他元素，递归处理子节点
                let results = [];
                const children = node.childNodes;
                for (let child of children) {
                    const result = this.processNode(child);
                    if (result) {
                        if (Array.isArray(result)) {
                            results.push(...result);
                        } else {
                            results.push(result);
                        }
                    }
                }
                return results.length > 0 ? results : null;
            }
        } else if (node.nodeType === Node.TEXT_NODE && node.textContent.trim() !== '') {
            // 处理纯文本节点（可能是占位符）
            if (!node.textContent.includes('开始输入...')) {
                const result = `<text indent="1">${this.escapeXML(node.textContent)}</text>`;
                // 文本节点会中断有序列表的连续性
                this.orderListState.isInContinuousList = false;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
                return result;
            }
        }

        return null;
    }

    /**
     * 将 DOM 节点转换为 XML 行
     * @param {Node} node - DOM 节点
     * @returns {string|null} XML 行，null 表示跳过
     */
    convertNodeToXML(node) {
        const tagName = node.tagName ? node.tagName.toLowerCase() : '';
        const className = node.className || '';

        // 处理文本元素
        if (className.includes('mi-note-text') || (tagName === 'p' && !className.includes('pm-block'))) {
            const indent = this.getIndentFromClass(className) || this.getIndentFromDataAttr(node) || '1';
            const align = this.getAlignFromClass(className);
            const content = this.extractContentWithRichText(node);

            // 如果内容为空或只有零宽度空格，返回空文本
            const trimmedContent = content.replace(/\u200B/g, '').trim();
            if (!trimmedContent) {
                return `<text indent="${indent}"></text>`;
            }

            let result = `<text indent="${indent}"`;
            if (align && align !== 'left') {
                result += ` align="${align}"`;
            }
            result += `>${content}</text>`;
            return result;
        }

        // 处理无序列表
        if (className.includes('mi-note-bullet')) {
            // 从 style 属性或类名获取缩进
            const indent = this.getIndentFromStyle(node) || this.getIndentFromClass(className) || this.getIndentFromDataAttr(node) || '1';
            let content = this.extractContentWithRichText(node);
            
            // 清理内容中的 <br> 标签、零宽度空格和多余的空白
            content = content.replace(/<br\s*\/?>/gi, '');
            content = content.replace(/\u200B/g, '');
            content = content.replace(/<span[^>]*><\/span>/gi, ''); // 清理空的 span
            content = content.trim();

            // 文本元素会中断有序列表的连续性
            this.orderListState.isInContinuousList = false;
            this.orderListState.lastIndent = null;
            this.orderListState.lastNumber = null;

            // 即使内容为空也返回，保持格式
            return `<bullet indent="${indent}" />${content}`;
        }

        // 处理有序列表
        if (className.includes('mi-note-order')) {
            // 从 style 属性或类名获取缩进
            const indent = this.getIndentFromStyle(node) || this.getIndentFromClass(className) || this.getIndentFromDataAttr(node) || '1';
            const numberAttr = node.getAttribute('data-number') || node.getAttribute('data-start') || '1';
            const number = parseInt(numberAttr, 10);

            // 根据小米笔记格式示例的规则：
            // 连续多行的有序列表，第一行的inputNumber是实际值，后续行的inputNumber都是0
            let inputNumber;

            if (this.orderListState.isInContinuousList && 
                this.orderListState.lastIndent === indent) {
                // 在连续的有序列表中，且缩进级别相同
                // 这是后续行，inputNumber应该为0
                inputNumber = 0;
            } else {
                // 第一行或不同缩进级别，使用实际值
                // 小米笔记 XML 中 inputNumber 是 0-based，所以需要减 1
                inputNumber = Math.max(0, number - 1);
                // 更新状态
                this.orderListState.lastIndent = indent;
                this.orderListState.lastNumber = number;
                this.orderListState.isInContinuousList = true;
            }

            let content = this.extractContentWithRichText(node);
            
            // 清理内容中的 <br> 标签、零宽度空格和多余的空白
            content = content.replace(/<br\s*\/?>/gi, '');
            content = content.replace(/\u200B/g, '');
            content = content.replace(/<span[^>]*><\/span>/gi, ''); // 清理空的 span
            content = content.trim();

            // 即使内容为空也返回，保持格式
            return `<order indent="${indent}" inputNumber="${inputNumber}" />${content}`;
        }

        // 处理复选框
        if (className.includes('mi-note-checkbox')) {
            const checkbox = node.querySelector('input[type="checkbox"]');
            const checked = checkbox ? checkbox.checked : false;
            // 从 style 属性或类名获取缩进
            const indent = this.getIndentFromStyle(node) || this.getIndentFromClass(className) || this.getIndentFromDataAttr(node) || '1';
            const level = node.getAttribute('data-level') || '3';

            // 提取内容，但排除 checkbox input 元素本身
            let content = this.extractContentFromCheckbox(node);
            
            // 清理内容中的 <br> 标签、零宽度空格和多余的空白
            content = content.replace(/<br\s*\/?>/gi, '');
            content = content.replace(/\u200B/g, '');
            content = content.replace(/<span[^>]*><\/span>/gi, ''); // 清理空的 span
            content = content.trim();

            // 文本元素会中断有序列表的连续性
            this.orderListState.isInContinuousList = false;
            this.orderListState.lastIndent = null;
            this.orderListState.lastNumber = null;

            // 注意：XML 格式中没有 checked 属性，所以不保存选中状态
            // 即使内容为空也返回，保持格式
            return `<input type="checkbox" indent="${indent}" level="${level}" />${content}`;
        }

        // 处理水平分割线
        if (className.includes('mi-note-hr') || tagName === 'hr') {
            // 文本元素会中断有序列表的连续性
            this.orderListState.isInContinuousList = false;
            this.orderListState.lastIndent = null;
            this.orderListState.lastNumber = null;
            return '<hr />';
        }

        // 处理引用块
        if (className.includes('mi-note-quote') || (tagName === 'blockquote')) {
            let quoteContent = '';
            const children = node.childNodes;
            for (let child of children) {
                if (child.nodeType === Node.ELEMENT_NODE) {
                    const childTag = child.tagName ? child.tagName.toLowerCase() : '';
                    const childClass = child.className || '';
                    if (childTag === 'p' || childClass.includes('mi-note-text')) {
                        const indent = this.getIndentFromClass(childClass) || this.getIndentFromDataAttr(child) || '1';
                        let content = this.extractContentWithRichText(child);
                        // 清理零宽度空格
                        content = content.replace(/\u200B/g, '').trim();
                        // 如果内容为空，至少保留空文本标签
                        quoteContent += `<text indent="${indent}">${content}</text>\n`;
                    }
                }
            }
            quoteContent = quoteContent.trim();

            // 文本元素会中断有序列表的连续性
            this.orderListState.isInContinuousList = false;
            this.orderListState.lastIndent = null;
            this.orderListState.lastNumber = null;

            // 即使内容为空也返回，保持格式
            if (!quoteContent) {
                quoteContent = '<text indent="1"></text>';
            }
            return `<quote>${quoteContent}</quote>`;
        }

        // 处理图片
        if (className.includes('mi-note-image') || tagName === 'img') {
            const src = node.getAttribute('src') || '';
            const alt = node.getAttribute('alt') || '';
            const fileId = node.getAttribute('fileid') || '';

            // 文本元素会中断有序列表的连续性
            this.orderListState.isInContinuousList = false;
            this.orderListState.lastIndent = null;
            this.orderListState.lastNumber = null;

            if (fileId) {
                return `<img fileid="${fileId}" src="${src}" alt="${alt}" />`;
            }
            return `<img src="${src}" alt="${alt}" />`;
        }

        // 处理标准HTML元素（如p, div等），但只有在没有特殊class时才处理
        if ((tagName === 'p' || tagName === 'div') && !className.includes('mi-note-')) {
            const content = this.extractContentWithRichText(node);
            if (content.trim() !== '') {
                // 文本元素会中断有序列表的连续性
                this.orderListState.isInContinuousList = false;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
                return `<text indent="1">${content}</text>`;
            }
        }

        return null;
    }

    /**
     * 从 checkbox 元素提取内容
     * @param {Node} node - checkbox DOM 节点
     * @returns {string} XML 格式的富文本内容
     */
    extractContentFromCheckbox(node) {
        if (!node) return '';

        // 克隆节点以避免修改原始节点
        const clone = node.cloneNode(true);

        // 移除 checkbox input 元素
        const checkbox = clone.querySelector('input[type="checkbox"]');
        if (checkbox) {
            checkbox.remove();
        }

        // 移除所有 br 标签
        const brs = clone.querySelectorAll('br');
        brs.forEach(br => br.remove());

        // 移除所有只包含零宽度空格的 span
        const spans = clone.querySelectorAll('span');
        spans.forEach(span => {
            const text = span.textContent || '';
            if (text.trim() === '' || text === '\u200B' || text.trim() === '\u200B') {
                span.remove();
            }
        });

        // 提取文本内容（不处理富文本格式，因为 checkbox 后面直接跟文本）
        // 但保留基本的格式标签（如加粗、斜体等）
        let text = '';
        const processNode = (n) => {
            if (n.nodeType === Node.TEXT_NODE) {
                const nodeText = n.textContent;
                // 跳过零宽度空格
                if (nodeText !== '\u200B') {
                    text += nodeText;
                }
            } else if (n.nodeType === Node.ELEMENT_NODE) {
                const tagName = n.tagName ? n.tagName.toLowerCase() : '';
                // 对于 checkbox，保留基本的格式标签
                if (tagName === 'b' || tagName === 'strong') {
                    text += '<b>';
                    for (let child of n.childNodes) {
                        processNode(child);
                    }
                    text += '</b>';
                } else if (tagName === 'i' || tagName === 'em') {
                    text += '<i>';
                    for (let child of n.childNodes) {
                        processNode(child);
                    }
                    text += '</i>';
                } else if (tagName === 'u') {
                    text += '<u>';
                    for (let child of n.childNodes) {
                        processNode(child);
                    }
                    text += '</u>';
                } else if (tagName === 's' || tagName === 'strike' || tagName === 'del') {
                    text += '<delete>';
                    for (let child of n.childNodes) {
                        processNode(child);
                    }
                    text += '</delete>';
                } else {
                    // 其他元素，递归处理
                    for (let child of n.childNodes) {
                        processNode(child);
                    }
                }
            }
        };

        for (let child of clone.childNodes) {
            processNode(child);
        }

        return this.escapeXML(text.trim());
    }

    /**
     * 提取节点内容并保留富文本格式
     * @param {Node} node - DOM 节点
     * @returns {string} XML 格式的富文本内容
     */
    extractContentWithRichText(node) {
        if (!node) return '';

        // 克隆节点以避免修改原始节点
        const clone = node.cloneNode(true);

        // 移除 checkbox input 元素（如果存在）
        const checkbox = clone.querySelector('input[type="checkbox"]');
        if (checkbox) {
            checkbox.remove();
        }

        let content = '';

        // 移除所有空的 span 和 br 标签
        const emptySpans = clone.querySelectorAll('span:empty, span:has(br:only-child)');
        emptySpans.forEach(span => span.remove());
        
        const brs = clone.querySelectorAll('br');
        brs.forEach(br => br.remove());

        // 递归处理子节点
        const processChild = (child) => {
            if (child.nodeType === Node.TEXT_NODE) {
                const text = child.textContent;
                // 跳过零宽度空格
                if (text.trim() && !text.includes('\u200B')) {
                    content += this.escapeXML(text);
                }
            } else if (child.nodeType === Node.ELEMENT_NODE) {
                const tagName = child.tagName ? child.tagName.toLowerCase() : '';
                const className = child.className || '';

                // 跳过空的 span 和 br 标签
                if (tagName === 'br') {
                    return;
                }
                if (tagName === 'span' && (!child.textContent.trim() || child.textContent === '\u200B')) {
                    return;
                }

                // 处理大标题
                if (className.includes('mi-note-size') || tagName === 'h1') {
                    content += '<size>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</size>';
                }
                // 处理二级标题
                else if (className.includes('mi-note-mid-size') || tagName === 'h2') {
                    content += '<mid-size>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</mid-size>';
                }
                // 处理三级标题
                else if (className.includes('mi-note-h3-size') || tagName === 'h3') {
                    content += '<h3-size>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</h3-size>';
                }
                // 处理加粗
                else if (tagName === 'b' || tagName === 'strong') {
                    content += '<b>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</b>';
                }
                // 处理斜体
                else if (tagName === 'i' || tagName === 'em') {
                    content += '<i>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</i>';
                }
                // 处理下划线
                else if (tagName === 'u') {
                    content += '<u>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</u>';
                }
                // 处理删除线
                else if (tagName === 's' || tagName === 'strike' || tagName === 'del') {
                    content += '<delete>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</delete>';
                }
                // 处理高亮
                else if (className.includes('mi-note-highlight')) {
                    const style = child.getAttribute('style') || '';
                    const colorMatch = style.match(/background-color:\s*([^;]+)/);
                    const color = colorMatch ? colorMatch[1].trim() : '#9affe8af';
                    content += `<background color="${color}">`;
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</background>';
                }
                // 处理居中对齐
                else if (className.includes('mi-note-center') || className.includes('center')) {
                    content += '<center>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</center>';
                }
                // 处理右对齐
                else if (className.includes('mi-note-right') || className.includes('right')) {
                    content += '<right>';
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                    content += '</right>';
                }
                // 其他元素，递归处理
                else {
                    for (let subChild of child.childNodes) {
                        processChild(subChild);
                    }
                }
            }
        };

        for (let child of clone.childNodes) {
            processChild(child);
        }

        return content;
    }

    /**
     * 从 CSS 类提取缩进级别
     * @param {string} className - CSS 类名
     * @returns {string|null} 缩进级别，null 表示未找到
     */
    getIndentFromClass(className) {
        if (!className) return null;
        const match = className.match(/indent-(\d+)/);
        return match ? match[1] : null;
    }

    /**
     * 从 data 属性提取缩进级别
     * @param {Node} node - DOM 节点
     * @returns {string|null} 缩进级别，null 表示未找到
     */
    getIndentFromDataAttr(node) {
        if (!node) return null;
        const indent = node.getAttribute('data-indent');
        return indent || null;
    }

    /**
     * 从 style 属性提取缩进级别
     * @param {Node} node - DOM 节点
     * @returns {string|null} 缩进级别，null 表示未找到
     */
    getIndentFromStyle(node) {
        if (!node) return null;
        const style = node.getAttribute('style') || '';
        const match = style.match(/padding-left:\s*(\d+)px/);
        if (match) {
            // padding-left 是 (indent - 1) * 20，所以 indent = padding-left / 20 + 1
            const paddingLeft = parseInt(match[1], 10);
            const indent = Math.floor(paddingLeft / 20) + 1;
            return indent.toString();
        }
        return null;
    }

    /**
     * 从 CSS 类提取对齐方式
     * @param {string} className - CSS 类名
     * @returns {string} 对齐方式（left, center, right）
     */
    getAlignFromClass(className) {
        if (!className) return 'left';
        if (className.includes('center')) return 'center';
        if (className.includes('right')) return 'right';
        return 'left';
    }

    /**
     * XML 转义
     * @param {string} text - 文本
     * @returns {string} 转义后的文本
     */
    escapeXML(text) {
        if (!text) return '';
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&apos;');
    }
}

// 导出供外部使用
if (typeof module !== 'undefined' && module.exports) {
    module.exports = HTMLToXMLConverter;
}

