/**
 * CursorManager 类
 * 集成所有组件，提供统一的光标保存/恢复/规范化接口
 * 参考 CKEditor 5 的光标管理机制
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { CURSOR: 'Cursor' };

    /**
     * CursorManager 类
     * 管理光标状态和位置
     */
    class CursorManager {
        /**
         * 构造函数
         * @param {HTMLElement} editor - 编辑器根元素
         * @param {Object} options - 配置选项
         */
        constructor(editor, options = {}) {
            this.editor = editor;
            this.options = {
                enabled: true,
                usePostFixer: true,
                postFixerDelay: 10, // ms
                validatePositions: true,
                maxRecoveryAttempts: 3,
                ...options
            };
            
            this.currentPosition = null;
            this.lastStablePosition = null;
            this.postFixer = new window.MiNoteEditor.SelectionPostFixer(editor);
            this.schema = window.CursorSchema || new window.MiNoteEditor.SchemaValidator();
            this.isRestoring = false;
            this.recoveryAttempts = 0;
            this.eventListeners = [];
            
            if (this.options.enabled) {
                this._setupEventListeners();
            }
        }
        
        /**
         * 保存当前光标位置
         * @returns {Position|null} 保存的位置
         */
        savePosition() {
            if (!this.options.enabled) {
                return null;
            }
            
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return null;
            }
            
            const range = selection.getRangeAt(0);
            if (!this.editor.contains(range.commonAncestorContainer)) {
                return null;
            }
            
            try {
                this.currentPosition = window.MiNoteEditor.Position.fromDOM(range, this.editor);
                
                // 验证位置
                if (this.options.validatePositions) {
                    const validationResult = this.schema.validate(this.currentPosition, this.editor);
                    if (validationResult === window.MiNoteEditor.CursorState.STABLE) {
                        this.lastStablePosition = this.currentPosition;
                        this.recoveryAttempts = 0; // 重置恢复尝试次数
                    }
                } else {
                    this.lastStablePosition = this.currentPosition;
                }
                
                log.debug(LOG_MODULES.CURSOR, '保存光标位置', { position: this.currentPosition });
                return this.currentPosition;
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '保存光标位置失败', { error: error.message });
                return null;
            }
        }
        
        /**
         * 恢复光标位置
         * @param {Position} position - 要恢复的位置
         * @returns {boolean} 是否恢复成功
         */
        restorePosition(position) {
            if (!this.options.enabled || !position || this.isRestoring) {
                return false;
            }
            
            this.isRestoring = true;
            
            try {
                // 验证位置
                let targetPosition = position;
                if (this.options.validatePositions) {
                    const validationResult = this.schema.validate(position, this.editor);
                    if (validationResult === window.MiNoteEditor.CursorState.INVALID) {
                        targetPosition = this.schema.getNearestValidPosition(position, this.editor);
                    }
                }
                
                // 转换为DOM位置并设置
                const domPosition = targetPosition.toDOMPosition(this.editor);
                if (domPosition) {
                    const selection = window.getSelection();
                    selection.removeAllRanges();
                    selection.addRange(domPosition);
                    
                    // 应用Post-Fixer确保位置有效
                    if (this.options.usePostFixer) {
                        setTimeout(() => {
                            this.postFixer.fix(selection);
                        }, this.options.postFixerDelay);
                    }
                    
                    this.currentPosition = targetPosition;
                    this.lastStablePosition = targetPosition;
                    this.recoveryAttempts = 0; // 重置恢复尝试次数
                    
                    log.debug(LOG_MODULES.CURSOR, '恢复光标位置', { position: targetPosition });
                    return true;
                }
            } catch (error) {
                log.warn(LOG_MODULES.CURSOR, '恢复光标位置失败', { error: error.message });
                
                // 增加恢复尝试次数
                this.recoveryAttempts++;
                if (this.recoveryAttempts >= this.options.maxRecoveryAttempts) {
                    log.error(LOG_MODULES.CURSOR, '达到最大恢复尝试次数', { attempts: this.recoveryAttempts });
                    this._fallbackToDefaultPosition();
                }
            } finally {
                this.isRestoring = false;
            }
            
            return false;
        }
        
        /**
         * 恢复到最后稳定位置
         * @returns {boolean} 是否恢复成功
         */
        restoreLastStablePosition() {
            if (!this.lastStablePosition) {
                return this._fallbackToDefaultPosition();
            }
            
            return this.restorePosition(this.lastStablePosition);
        }
        
        /**
         * 规范化当前光标位置
         * @returns {boolean} 是否进行了规范化
         */
        normalizePosition() {
            if (!this.options.enabled) {
                return false;
            }
            
            const selection = window.getSelection();
            if (!selection.rangeCount) {
                return false;
            }
            
            if (this.options.usePostFixer) {
                return this.postFixer.fix(selection);
            }
            
            return false;
        }
        
        /**
         * 获取当前光标位置
         * @returns {Position|null} 当前位置
         */
        getCurrentPosition() {
            return this.currentPosition;
        }
        
        /**
         * 获取最后稳定位置
         * @returns {Position|null} 最后稳定位置
         */
        getLastStablePosition() {
            return this.lastStablePosition;
        }
        
        /**
         * 检查光标是否在有效位置
         * @returns {string} 光标状态
         */
        checkCursorState() {
            if (!this.currentPosition) {
                return window.MiNoteEditor.CursorState.INVALID;
            }
            
            return this.schema.validate(this.currentPosition, this.editor);
        }
        
        /**
         * 启用光标管理
         */
        enable() {
            this.options.enabled = true;
            this._setupEventListeners();
        }
        
        /**
         * 禁用光标管理
         */
        disable() {
            this.options.enabled = false;
            this._removeEventListeners();
        }
        
        /**
         * 设置配置选项
         * @param {Object} newOptions - 新的配置选项
         */
        setOptions(newOptions) {
            this.options = { ...this.options, ...newOptions };
            
            // 如果启用状态改变，更新事件监听器
            if (newOptions.enabled !== undefined) {
                if (newOptions.enabled) {
                    this._setupEventListeners();
                } else {
                    this._removeEventListeners();
                }
            }
        }
        
        /**
         * 设置事件监听器
         * @private
         */
        _setupEventListeners() {
            this._removeEventListeners();
            
            // selectionchange 事件监听器
            const handleSelectionChange = () => {
                if (this.isRestoring) return;
                
                this.savePosition();
            };
            
            this.editor.addEventListener('selectionchange', handleSelectionChange);
            this.eventListeners.push({ type: 'selectionchange', handler: handleSelectionChange });
            
            // input 事件监听器
            const handleInput = () => {
                if (this.isRestoring) return;
                
                // 在内容变化后延迟调用Post-Fixer
                setTimeout(() => {
                    this.normalizePosition();
                }, this.options.postFixerDelay);
            };
            
            this.editor.addEventListener('input', handleInput);
            this.eventListeners.push({ type: 'input', handler: handleInput });
            
            // keydown 事件监听器（处理特殊按键）
            const handleKeyDown = (event) => {
                if (this.isRestoring) return;
                
                // 在特定按键后保存光标位置
                const saveKeys = ['Enter', 'Tab', 'Backspace', 'Delete'];
                if (saveKeys.includes(event.key)) {
                    setTimeout(() => {
                        this.savePosition();
                    }, 0);
                }
            };
            
            this.editor.addEventListener('keydown', handleKeyDown);
            this.eventListeners.push({ type: 'keydown', handler: handleKeyDown });
            
            // 监听编辑器内容变化
            const observer = new MutationObserver((mutations) => {
                if (this.isRestoring) return;
                
                // 检查是否有影响光标位置的突变
                const relevantMutations = mutations.filter(mutation => 
                    mutation.type === 'childList' || mutation.type === 'characterData'
                );
                
                if (relevantMutations.length > 0) {
                    setTimeout(() => {
                        this.normalizePosition();
                    }, this.options.postFixerDelay);
                }
            });
            
            observer.observe(this.editor, {
                childList: true,
                subtree: true,
                characterData: true
            });
            
            this.eventListeners.push({ type: 'observer', handler: observer });
            
            log.debug(LOG_MODULES.CURSOR, '设置光标管理器事件监听器');
        }
        
        /**
         * 移除事件监听器
         * @private
         */
        _removeEventListeners() {
            for (const listener of this.eventListeners) {
                if (listener.type === 'observer') {
                    listener.handler.disconnect();
                } else {
                    this.editor.removeEventListener(listener.type, listener.handler);
                }
            }
            
            this.eventListeners = [];
            log.debug(LOG_MODULES.CURSOR, '移除光标管理器事件监听器');
        }
        
        /**
         * 回退到默认位置
         * @private
         * @returns {boolean} 是否回退成功
         */
        _fallbackToDefaultPosition() {
            try {
                const defaultPosition = this.schema._getDefaultPosition(this.editor);
                if (defaultPosition) {
                    const domPosition = defaultPosition.toDOMPosition(this.editor);
                    if (domPosition) {
                        const selection = window.getSelection();
                        selection.removeAllRanges();
                        selection.addRange(domPosition);
                        
                        this.currentPosition = defaultPosition;
                        this.lastStablePosition = defaultPosition;
                        this.recoveryAttempts = 0;
                        
                        log.warn(LOG_MODULES.CURSOR, '回退到默认光标位置');
                        return true;
                    }
                }
            } catch (error) {
                log.error(LOG_MODULES.CURSOR, '回退到默认位置失败', { error: error.message });
            }
            
            return false;
        }
        
        /**
         * 销毁光标管理器
         */
        destroy() {
            this._removeEventListeners();
            this.currentPosition = null;
            this.lastStablePosition = null;
            this.isRestoring = false;
            this.recoveryAttempts = 0;
            
            log.debug(LOG_MODULES.CURSOR, '销毁光标管理器');
        }
    }

    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.CursorManager = CursorManager;

    // 创建全局光标管理器实例
    window.MiNoteEditor.createCursorManager = function(editor, options) {
        return new CursorManager(editor, options);
    };

})();
