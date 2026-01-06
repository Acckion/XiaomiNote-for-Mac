/**
 * Utils 模块
 * 提供通用工具函数
 * 依赖: 无
 */

(function() {
    'use strict';

    /**
     * 从元素获取缩进级别
     * @param {Element} element - 元素
     * @returns {string} 缩进级别（'0' 到 '5'）
     */
    function getIndentFromElement(element) {
        if (!element || !element.classList) {
            return '0';
        }
        
        // 检查 indent-X 类
        for (let i = 1; i <= 5; i++) {
            if (element.classList.contains(`indent-${i}`)) {
                return String(i);
            }
        }
        
        // 检查 padding-left 样式
        const paddingLeft = window.getComputedStyle(element).paddingLeft;
        if (paddingLeft) {
            const px = parseInt(paddingLeft, 10);
            if (px >= 80) return '5';
            if (px >= 60) return '4';
            if (px >= 40) return '3';
            if (px >= 20) return '2';
            if (px > 0) return '1';
        }
        
        return '0';
    }
    
    /**
     * 为元素设置缩进级别
     * @param {Element} element - 元素
     * @param {number} indent - 缩进级别（0 到 5）
     */
    function setIndentForElement(element, indent) {
        if (!element || !element.classList) {
            return;
        }
        
        // 移除所有 indent-X 类
        for (let i = 0; i <= 5; i++) {
            element.classList.remove(`indent-${i}`);
        }
        
        // 添加新的缩进类
        if (indent > 0 && indent <= 5) {
            element.classList.add(`indent-${indent}`);
        }
        
        // 同时设置 padding-left（作为备用）
        if (indent === 0) {
            element.style.paddingLeft = '';
        } else if (indent === 1) {
            element.style.paddingLeft = '0px';
        } else if (indent === 2) {
            element.style.paddingLeft = '20px';
        } else if (indent === 3) {
            element.style.paddingLeft = '40px';
        } else if (indent === 4) {
            element.style.paddingLeft = '60px';
        } else if (indent === 5) {
            element.style.paddingLeft = '80px';
        }
    }
    
    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Utils = {
        getIndentFromElement: getIndentFromElement,
        setIndentForElement: setIndentForElement
    };
    
    // 向后兼容：直接暴露到全局
    window.getIndentFromElement = getIndentFromElement;
    window.setIndentForElement = setIndentForElement;
    
})();
