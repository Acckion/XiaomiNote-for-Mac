/**
 * 光标管理模块入口点
 * 集成所有光标管理组件，提供统一的API接口
 */

(function() {
    'use strict';

    // 检查依赖
    if (!window.MiNoteEditor) {
        window.MiNoteEditor = {};
    }

    // 导入所有子模块
    // position.js 已经定义了 Position 类和相关工具函数
    // selection.js 已经定义了 SelectionRange 类
    // schema.js 已经定义了 SchemaValidator 类和 CursorState 枚举
    // post-fixer.js 已经定义了 SelectionPostFixer 类
    // manager.js 已经定义了 CursorManager 类和 createCursorManager 函数

    /**
     * 光标管理模块API
     */
    const CursorModule = {
        /**
         * 初始化光标管理模块
         * @param {HTMLElement} editor - 编辑器根元素
         * @param {Object} options - 配置选项
         * @returns {CursorManager} 光标管理器实例
         */
        init: function(editor, options = {}) {
            if (!editor) {
                console.error('CursorModule: 编辑器元素不能为空');
                return null;
            }

            // 确保所有依赖已加载
            this._ensureDependencies();

            // 创建光标管理器
            const cursorManager = window.MiNoteEditor.createCursorManager(editor, options);
            
            // 保存到编辑器实例
            editor._cursorManager = cursorManager;
            
            console.log('CursorModule: 光标管理模块初始化完成', { editor, options });
            return cursorManager;
        },

        /**
         * 获取编辑器对应的光标管理器
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {CursorManager|null} 光标管理器实例
         */
        getManager: function(editor) {
            return editor._cursorManager || null;
        },

        /**
         * 保存当前光标位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {Position|null} 保存的位置
         */
        savePosition: function(editor) {
            const manager = this.getManager(editor);
            if (manager) {
                return manager.savePosition();
            }
            
            // 如果没有管理器，使用基础功能
            return window.MiNoteEditor.Position.fromCurrentSelection(editor);
        },

        /**
         * 恢复光标位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @param {Position|string} position - 要恢复的位置或位置字符串
         * @returns {boolean} 是否恢复成功
         */
        restorePosition: function(editor, position) {
            const manager = this.getManager(editor);
            
            // 如果传入的是字符串，解析为Position对象
            let positionObj = position;
            if (typeof position === 'string') {
                positionObj = window.MiNoteEditor.Position.fromString(position);
            }
            
            if (manager && positionObj) {
                return manager.restorePosition(positionObj);
            }
            
            // 如果没有管理器，使用基础功能
            if (positionObj && positionObj.toDOMPosition) {
                const domPosition = positionObj.toDOMPosition(editor);
                if (domPosition) {
                    const selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(domPosition);
                    return true;
                }
            }
            
            return false;
        },

        /**
         * 规范化当前光标位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {boolean} 是否进行了规范化
         */
        normalizePosition: function(editor) {
            const manager = this.getManager(editor);
            if (manager) {
                return manager.normalizePosition();
            }
            
            // 如果没有管理器，使用Post-Fixer
            const postFixer = new window.MiNoteEditor.SelectionPostFixer(editor);
            const selection = window.getSelection();
            return postFixer.fix(selection);
        },

        /**
         * 验证光标位置有效性
         * @param {HTMLElement} editor - 编辑器根元素
         * @param {Position} position - 要验证的位置（可选，默认为当前位置）
         * @returns {string} 光标状态
         */
        validatePosition: function(editor, position = null) {
            if (!position) {
                const currentPosition = window.MiNoteEditor.Position.fromCurrentSelection(editor);
                if (!currentPosition) {
                    return window.MiNoteEditor.CursorState.INVALID;
                }
                position = currentPosition;
            }
            
            const schema = window.CursorSchema || new window.MiNoteEditor.SchemaValidator();
            return schema.validate(position, editor);
        },
        
        /**
         * 检查光标位置是否有效（validatePosition的别名）
         * @param {HTMLElement} editor - 编辑器根元素
         * @param {Range} range - DOM Range对象（可选）
         * @returns {boolean} 是否有效
         */
        isValidPosition: function(editor, range = null) {
            let position = null;
            if (range) {
                position = window.MiNoteEditor.Position.fromDOM(range, editor);
            } else {
                position = window.MiNoteEditor.Position.fromCurrentSelection(editor);
            }
            
            if (!position) {
                return false;
            }
            
            const result = this.validatePosition(editor, position);
            return result === window.MiNoteEditor.CursorState.STABLE;
        },

        /**
         * 获取最近的有效位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @param {Position} position - 当前位置
         * @returns {Position} 最近的有效位置
         */
        getNearestValidPosition: function(editor, position) {
            const schema = window.CursorSchema || new window.MiNoteEditor.SchemaValidator();
            return schema.getNearestValidPosition(position, editor);
        },

        /**
         * 修复选择位置
         * @param {HTMLElement} editor - 编辑器根元素
         * @returns {boolean} 是否进行了修复
         */
        fixSelection: function(editor) {
            const postFixer = new window.MiNoteEditor.SelectionPostFixer(editor);
            const selection = window.getSelection();
            return postFixer.fix(selection);
        },

        /**
         * 启用光标管理
         * @param {HTMLElement} editor - 编辑器根元素
         */
        enable: function(editor) {
            const manager = this.getManager(editor);
            if (manager) {
                manager.enable();
            }
        },

        /**
         * 禁用光标管理
         * @param {HTMLElement} editor - 编辑器根元素
         */
        disable: function(editor) {
            const manager = this.getManager(editor);
            if (manager) {
                manager.disable();
            }
        },

        /**
         * 销毁光标管理器
         * @param {HTMLElement} editor - 编辑器根元素
         */
        destroy: function(editor) {
            const manager = this.getManager(editor);
            if (manager) {
                manager.destroy();
                delete editor._cursorManager;
            }
        },

        /**
         * 确保所有依赖已加载
         * @private
         */
        _ensureDependencies: function() {
            // 检查并加载必要的依赖
            const dependencies = [
                'Position',
                'SelectionRange', 
                'SchemaValidator',
                'CursorState',
                'SelectionPostFixer',
                'CursorManager',
                'createCursorManager'
            ];

            for (const dep of dependencies) {
                if (dep === 'createCursorManager') {
                    if (typeof window.MiNoteEditor.createCursorManager !== 'function') {
                        console.warn(`CursorModule: 依赖 ${dep} 未加载，可能需要重新加载模块`);
                    }
                } else if (!window.MiNoteEditor[dep]) {
                    console.warn(`CursorModule: 依赖 ${dep} 未加载，可能需要重新加载模块`);
                }
            }
        },

        /**
         * 获取模块版本信息
         * @returns {Object} 版本信息
         */
        getVersion: function() {
            return {
                name: 'MiNoteEditor Cursor Module',
                version: '1.0.0',
                description: '光标管理模块，提供稳定可靠的光标位置管理',
                dependencies: {
                    Position: '1.0.0',
                    SelectionRange: '1.0.0',
                    SchemaValidator: '1.0.0',
                    SelectionPostFixer: '1.0.0',
                    CursorManager: '1.0.0'
                }
            };
        }
    };

    // 导出到全局命名空间
    window.MiNoteEditor.CursorModule = CursorModule;

    // 向后兼容：暴露到 window.MiNoteWebEditor
    if (!window.MiNoteWebEditor) {
        window.MiNoteWebEditor = {};
    }
    window.MiNoteWebEditor.CursorModule = CursorModule;

    console.log('CursorModule: 光标管理模块加载完成', CursorModule.getVersion());

})();
