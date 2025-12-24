/**
 * Converter 模块
 * 包装 XML/HTML 转换器，提供统一的转换接口
 * 依赖: logger (可选)
 * 注意: XMLToHTMLConverter 和 HTMLToXMLConverter 类在 xml-to-html.js 和 html-to-xml.js 中定义
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { CONVERTER: 'Converter', INIT: 'Init' };

    // 转换器实例（延迟初始化）
    let xmlToHtmlConverter = null;
    let htmlToXmlConverter = null;

    /**
     * 初始化转换器
     */
    function initConverters() {
        if (!xmlToHtmlConverter) {
            if (typeof XMLToHTMLConverter !== 'undefined') {
                xmlToHtmlConverter = new XMLToHTMLConverter();
                log.debug(LOG_MODULES.CONVERTER, 'XMLToHTMLConverter 初始化完成');
            } else {
                log.error(LOG_MODULES.CONVERTER, 'XMLToHTMLConverter 类未定义，请确保 xml-to-html.js 已加载');
            }
        }

        if (!htmlToXmlConverter) {
            if (typeof HTMLToXMLConverter !== 'undefined') {
                htmlToXmlConverter = new HTMLToXMLConverter();
                log.debug(LOG_MODULES.CONVERTER, 'HTMLToXMLConverter 初始化完成');
            } else {
                log.error(LOG_MODULES.CONVERTER, 'HTMLToXMLConverter 类未定义，请确保 html-to-xml.js 已加载');
            }
        }
    }

    /**
     * 将 XML 转换为 HTML
     * @param {string} xmlContent - XML 内容
     * @returns {string} HTML 内容
     */
    function xmlToHtml(xmlContent) {
        if (!xmlToHtmlConverter) {
            initConverters();
        }

        if (!xmlToHtmlConverter) {
            log.error(LOG_MODULES.CONVERTER, 'XMLToHTMLConverter 未初始化');
            return '';
        }

        try {
            return xmlToHtmlConverter.convert(xmlContent);
        } catch (error) {
            log.error(LOG_MODULES.CONVERTER, 'XML 转 HTML 失败', { error: error.message });
            return '';
        }
    }

    /**
     * 将 HTML 转换为 XML
     * @param {string} htmlContent - HTML 内容
     * @returns {string} XML 内容
     */
    function htmlToXml(htmlContent) {
        if (!htmlToXmlConverter) {
            initConverters();
        }

        if (!htmlToXmlConverter) {
            log.error(LOG_MODULES.CONVERTER, 'HTMLToXMLConverter 未初始化');
            return '';
        }

        try {
            return htmlToXmlConverter.convert(htmlContent);
        } catch (error) {
            log.error(LOG_MODULES.CONVERTER, 'HTML 转 XML 失败', { error: error.message });
            return '';
        }
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Converter = {
        init: initConverters,
        xmlToHtml: xmlToHtml,
        htmlToXml: htmlToXml,
        // 导出转换器类（如果已定义）
        XMLToHTMLConverter: typeof XMLToHTMLConverter !== 'undefined' ? XMLToHTMLConverter : undefined,
        HTMLToXMLConverter: typeof HTMLToXMLConverter !== 'undefined' ? HTMLToXMLConverter : undefined,
        getXmlToHtmlConverter: () => {
            if (!xmlToHtmlConverter) initConverters();
            return xmlToHtmlConverter;
        },
        getHtmlToXmlConverter: () => {
            if (!htmlToXmlConverter) initConverters();
            return htmlToXmlConverter;
        }
    };

    // 向后兼容：直接暴露到全局
    window.xmlToHtmlConverter = null; // 将在初始化时设置
    window.htmlToXmlConverter = null; // 将在初始化时设置
    
    // 提供初始化函数
    window.initConverters = initConverters;
    
})();

