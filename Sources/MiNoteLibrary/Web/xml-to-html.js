/**
 * XML to HTML Converter
 * 将小米笔记 XML 格式转换为 HTML，用于在编辑器中渲染
 */

class XMLToHTMLConverter {
    constructor() {
        // 有序列表状态跟踪
        this.orderListState = {
            lastIndent: null,
            lastNumber: null,
            currentNumber: 1
        };
    }

    /**
     * 主转换方法：将 XML 内容转换为 HTML
     * @param {string} xmlContent - 小米笔记 XML 格式内容
     * @returns {string} HTML 内容
     */
    convert(xmlContent) {
        if (!xmlContent || xmlContent.trim() === '') {
            return '';
        }

        // 重置有序列表状态
        this.orderListState = {
            lastIndent: null,
            lastNumber: null,
            currentNumber: 1
        };

        // 解析 XML 行（保留空行用于引用块处理）
        const lines = xmlContent.split('\n');
        let html = '';
        let inQuote = false;
        let quoteContent = '';

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const trimmedLine = line.trim();
            
            // 处理引用块开始
            if (trimmedLine.startsWith('<quote>')) {
                inQuote = true;
                quoteContent = '';
                const content = trimmedLine.replace('<quote>', '').trim();
                if (content) {
                    quoteContent += content + '\n';
                }
                continue;
            }

            // 处理引用块结束
            if (trimmedLine.includes('</quote>')) {
                const content = trimmedLine.replace('</quote>', '').trim();
                if (content) {
                    quoteContent += content + '\n';
                }
                // 处理完整的引用内容
                html += this.parseQuoteElement(quoteContent);
                inQuote = false;
                quoteContent = '';
                this.orderListState.currentNumber = 1;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
                continue;
            }

            // 如果正在引用块中，累积内容
            if (inQuote) {
                quoteContent += line + '\n';
                continue;
            }

            // 跳过空行
            if (trimmedLine === '') {
                continue;
            }

            // 处理各种 XML 元素
            if (trimmedLine.startsWith('<text')) {
                html += this.parseTextElement(trimmedLine);
                this.orderListState.currentNumber = 1;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
            } else if (trimmedLine.startsWith('<bullet')) {
                html += this.parseBulletElement(trimmedLine);
                this.orderListState.currentNumber = 1;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
            } else if (trimmedLine.startsWith('<order')) {
                const result = this.parseOrderElement(trimmedLine);
                html += result.html;
                this.orderListState.currentNumber = result.nextNumber;
            } else if (trimmedLine.startsWith('<input type="checkbox"')) {
                html += this.parseCheckboxElement(trimmedLine);
                this.orderListState.currentNumber = 1;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
            } else if (trimmedLine.startsWith('<hr')) {
                html += this.parseHRElement(trimmedLine);
                this.orderListState.currentNumber = 1;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
            } else if (trimmedLine.startsWith('<img')) {
                html += this.parseImageElement(trimmedLine);
                this.orderListState.currentNumber = 1;
                this.orderListState.lastIndent = null;
                this.orderListState.lastNumber = null;
            }
        }

        return html;
    }

    /**
     * 解析 <text> 元素
     * @param {string} line - XML 行
     * @returns {string} HTML
     */
    parseTextElement(line) {
        // 提取 indent 属性
        const indentMatch = line.match(/indent="(\d+)"/);
        const indent = indentMatch ? indentMatch[1] : '1';

        // 提取 align 属性（如果有）
        const alignMatch = line.match(/align="(\w+)"/);
        const align = alignMatch ? alignMatch[1] : 'left';

        // 提取文本内容（去除 <text> 和 </text> 标签）
        const contentMatch = line.match(/<text[^>]*>(.*?)<\/text>/);
        if (!contentMatch) {
            return '';
        }

        let content = contentMatch[1];
        
        // 处理富文本格式
        const richContent = this.extractRichTextContent(content);

        // 构建 HTML
        const alignClass = align === 'center' ? ' center' : (align === 'right' ? ' right' : '');
        // 如果内容为空，至少保留一个空格以确保可见
        const finalContent = richContent || '\u200B';
        return `<div class="mi-note-text indent-${indent}${alignClass}">${finalContent}</div>`;
    }

    /**
     * 提取富文本内容并转换为 HTML
     * @param {string} xmlText - XML 格式的文本内容
     * @returns {string} HTML 格式的文本内容
     */
    extractRichTextContent(xmlText) {
        if (!xmlText) return '';

        let html = xmlText;

        // 注意：需要按照从内到外的顺序处理嵌套标签
        // 先处理最内层的格式标签，再处理外层的对齐标签

        // 处理高亮 <background color="...">（可能包含其他格式）
        html = html.replace(/<background\s+color="([^"]+)"\s*>(.*?)<\/background>/g, (match, color, content) => {
            // 递归处理内容中的其他格式
            let processedContent = content;
            processedContent = this.processNestedFormats(processedContent);
            return `<span class="mi-note-highlight" style="background-color: ${color};">${processedContent}</span>`;
        });

        // 处理大标题 <size>（可能包含其他格式）
        html = html.replace(/<size>(.*?)<\/size>/g, (match, content) => {
            let processedContent = this.processNestedFormats(content);
            return `<span class="mi-note-size">${processedContent}</span>`;
        });

        // 处理二级标题 <mid-size>
        html = html.replace(/<mid-size>(.*?)<\/mid-size>/g, (match, content) => {
            let processedContent = this.processNestedFormats(content);
            return `<span class="mi-note-mid-size">${processedContent}</span>`;
        });

        // 处理三级标题 <h3-size>
        html = html.replace(/<h3-size>(.*?)<\/h3-size>/g, (match, content) => {
            let processedContent = this.processNestedFormats(content);
            return `<span class="mi-note-h3-size">${processedContent}</span>`;
        });

        // 处理居中对齐 <center>（可能包含其他格式）
        html = html.replace(/<center>(.*?)<\/center>/g, (match, content) => {
            let processedContent = this.processNestedFormats(content);
            return `<span class="mi-note-center">${processedContent}</span>`;
        });

        // 处理右对齐 <right>（可能包含其他格式）
        html = html.replace(/<right>(.*?)<\/right>/g, (match, content) => {
            let processedContent = this.processNestedFormats(content);
            return `<span class="mi-note-right">${processedContent}</span>`;
        });

        // 处理基本格式标签（加粗、斜体、下划线、删除线）
        html = this.processNestedFormats(html);

        // XML 转义处理
        html = this.unescapeXML(html);

        return html;
    }

    /**
     * 处理嵌套的格式标签（加粗、斜体、下划线、删除线）
     * @param {string} text - 文本内容
     * @returns {string} 处理后的 HTML
     */
    processNestedFormats(text) {
        if (!text) return '';

        let html = text;

        // 处理加粗 <b>
        html = html.replace(/<b>(.*?)<\/b>/g, '<b>$1</b>');

        // 处理斜体 <i>
        html = html.replace(/<i>(.*?)<\/i>/g, '<i>$1</i>');

        // 处理下划线 <u>
        html = html.replace(/<u>(.*?)<\/u>/g, '<u>$1</u>');

        // 处理删除线 <delete>
        html = html.replace(/<delete>(.*?)<\/delete>/g, '<s>$1</s>');

        return html;
    }

    /**
     * 解析 <bullet> 元素（无序列表）
     * @param {string} line - XML 行
     * @returns {string} HTML
     */
    parseBulletElement(line) {
        // 提取 indent 属性
        const indentMatch = line.match(/indent="(\d+)"/);
        const indent = indentMatch ? indentMatch[1] : '1';

        // 提取内容（<bullet ... /> 后面的文本）
        const contentMatch = line.match(/\/>(.*)$/);
        const content = contentMatch ? contentMatch[1].trim() : '';

        // 处理内容中的富文本格式
        const richContent = this.extractRichTextContent(content);

        // 注意：bullet 和 order 不需要 indent 类，因为它们使用 padding-left 通过父元素控制
        return `<div class="mi-note-bullet" style="padding-left: ${(parseInt(indent) - 1) * 20}px;">${richContent || '\u200B'}</div>`;
    }

    /**
     * 解析 <order> 元素（有序列表）
     * @param {string} line - XML 行
     * @returns {{html: string, nextNumber: number}} HTML 和下一个序号
     */
    parseOrderElement(line) {
        // 提取 indent 属性
        const indentMatch = line.match(/indent="(\d+)"/);
        const indent = indentMatch ? indentMatch[1] : '1';

        // 提取 inputNumber 属性（0-based）
        const inputNumberMatch = line.match(/inputNumber="(\d+)"/);
        const inputNumber = inputNumberMatch ? parseInt(inputNumberMatch[1], 10) : 0;

        // 提取内容（<order ... /> 后面的文本）
        const contentMatch = line.match(/\/>(.*)$/);
        const content = contentMatch ? contentMatch[1].trim() : '';

        // 处理内容中的富文本格式
        const richContent = this.extractRichTextContent(content);

        // 计算显示序号
        // 如果 inputNumber 为 0 且与上一个列表的 indent 相同，则递增
        // 否则使用 inputNumber + 1（因为 inputNumber 是 0-based）
        let displayNumber;
        if (inputNumber === 0 && 
            this.orderListState.lastIndent === indent && 
            this.orderListState.lastNumber !== null) {
            // 连续列表，递增序号
            displayNumber = this.orderListState.currentNumber;
        } else {
            // 新列表或第一行，使用 inputNumber + 1
            displayNumber = inputNumber + 1;
        }

        // 更新状态
        this.orderListState.lastIndent = indent;
        this.orderListState.lastNumber = displayNumber;
        const nextNumber = displayNumber + 1;

        return {
            html: `<div class="mi-note-order" data-number="${displayNumber}" style="padding-left: ${(parseInt(indent) - 1) * 20}px;">${richContent || '\u200B'}</div>`,
            nextNumber: nextNumber
        };
    }

    /**
     * 解析 <input type="checkbox"> 元素（复选框）
     * @param {string} line - XML 行
     * @returns {string} HTML
     */
    parseCheckboxElement(line) {
        // 提取 indent 属性
        const indentMatch = line.match(/indent="(\d+)"/);
        const indent = indentMatch ? indentMatch[1] : '1';

        // 提取 level 属性
        const levelMatch = line.match(/level="(\d+)"/);
        const level = levelMatch ? levelMatch[1] : '3';

        // 提取内容（<input ... /> 后面的文本）
        const contentMatch = line.match(/\/>(.*)$/);
        const content = contentMatch ? contentMatch[1].trim() : '';

        // 处理内容中的富文本格式
        const richContent = this.extractRichTextContent(content);

        // 注意：XML 中没有 checked 属性，所以默认未选中
        return `<div class="mi-note-checkbox" data-level="${level}" style="padding-left: ${(parseInt(indent) - 1) * 20}px;">
            <input type="checkbox" />
            <span>${richContent || '\u200B'}</span>
        </div>`;
    }

    /**
     * 解析 <hr> 元素（分割线）
     * @param {string} line - XML 行
     * @returns {string} HTML
     */
    parseHRElement(line) {
        return '<hr class="mi-note-hr" />';
    }

    /**
     * 解析 <img> 元素（图片）
     * @param {string} line - XML 行
     * @returns {string} HTML
     */
    parseImageElement(line) {
        // 提取 src 属性
        const srcMatch = line.match(/src="([^"]+)"/);
        const src = srcMatch ? srcMatch[1] : '';

        // 提取 alt 属性
        const altMatch = line.match(/alt="([^"]+)"/);
        const alt = altMatch ? altMatch[1] : '';

        // 提取 fileid 属性（小米笔记特有）
        const fileIdMatch = line.match(/fileid="([^"]+)"/);
        const fileId = fileIdMatch ? fileIdMatch[1] : '';

        let imgTag = `<img src="${src}" alt="${alt}" class="mi-note-image"`;
        if (fileId) {
            imgTag += ` fileid="${fileId}"`;
        }
        imgTag += ' />';

        return `<div class="mi-note-image-container">${imgTag}</div>`;
    }

    /**
     * 解析 <quote> 元素（引用块）
     * @param {string} quoteContent - 引用块内的 XML 内容
     * @returns {string} HTML
     */
    parseQuoteElement(quoteContent) {
        if (!quoteContent || !quoteContent.trim()) {
            return '<div class="mi-note-quote"></div>';
        }

        // 解析引用块内的文本行
        const lines = quoteContent.split('\n').filter(line => line.trim() !== '');
        let html = '<div class="mi-note-quote">';

        for (const line of lines) {
            const trimmedLine = line.trim();
            if (trimmedLine.startsWith('<text')) {
                // 解析文本元素
                const indentMatch = trimmedLine.match(/indent="(\d+)"/);
                const indent = indentMatch ? indentMatch[1] : '1';

                const contentMatch = trimmedLine.match(/<text[^>]*>(.*?)<\/text>/);
                if (contentMatch) {
                    let content = contentMatch[1];
                    content = this.extractRichTextContent(content);
                    // 如果内容为空，至少保留一个空格以确保可见
                    if (!content || content.trim() === '') {
                        content = '\u200B';
                    }
                    html += `<div class="mi-note-text indent-${indent}">${content}</div>`;
                }
            }
        }

        html += '</div>';
        return html;
    }

    /**
     * XML 反转义
     * @param {string} text - 文本
     * @returns {string} 反转义后的文本
     */
    unescapeXML(text) {
        if (!text) return '';
        return text
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&amp;/g, '&')
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'");
    }
}

// 导出供外部使用
if (typeof module !== 'undefined' && module.exports) {
    module.exports = XMLToHTMLConverter;
}

