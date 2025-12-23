/**
 * Logger 模块
 * 提供分级日志系统，支持模块过滤、性能计时和日志历史
 */

(function() {
    'use strict';

    class Logger {
        constructor() {
            this.level = 'info'; // debug, info, warn, error
            this.enabled = true;
            this.levels = {
                debug: 0,
                info: 1,
                warn: 2,
                error: 3
            };
            this.enabledModules = new Set(); // 空集合表示所有模块都启用
            this.timers = new Map(); // 用于性能计时
            this.logHistory = []; // 日志历史记录（可选，用于调试）
            this.maxHistorySize = 100; // 最大历史记录数
        }
        
        /**
         * 设置日志级别
         * @param {string} level - 日志级别 (debug, info, warn, error)
         */
        setLevel(level) {
            if (this.levels.hasOwnProperty(level)) {
                const oldLevel = this.level;
                this.level = level;
                // 使用原生 console 避免循环调用
                if (oldLevel !== level) {
                    this._rawLog('info', `[Logger] 日志级别从 ${oldLevel} 更改为 ${level}`);
                }
            } else {
                this._rawLog('warn', `[Logger] 无效的日志级别: ${level}，有效值: ${Object.keys(this.levels).join(', ')}`);
            }
        }
        
        /**
         * 启用日志
         */
        enable() {
            if (!this.enabled) {
                this.enabled = true;
                this._rawLog('info', '[Logger] 日志已启用');
            }
        }
        
        /**
         * 禁用日志
         */
        disable() {
            if (this.enabled) {
                this.enabled = false;
                // 禁用时使用原生 console，因为 logger 已禁用
                console.info('[Logger] 日志已禁用');
            }
        }
        
        /**
         * 启用特定模块的日志
         * @param {string|string[]} modules - 模块名称或模块名称数组
         */
        enableModules(modules) {
            const moduleArray = Array.isArray(modules) ? modules : [modules];
            moduleArray.forEach(module => {
                this.enabledModules.add(module);
            });
        }
        
        /**
         * 禁用特定模块的日志
         * @param {string|string[]} modules - 模块名称或模块名称数组
         */
        disableModules(modules) {
            const moduleArray = Array.isArray(modules) ? modules : [modules];
            moduleArray.forEach(module => {
                this.enabledModules.delete(module);
            });
        }
        
        /**
         * 检查模块是否启用
         * @param {string} module - 模块名称
         * @returns {boolean}
         */
        _isModuleEnabled(module) {
            // 如果 enabledModules 为空，所有模块都启用
            if (this.enabledModules.size === 0) {
                return true;
            }
            return this.enabledModules.has(module);
        }
        
        /**
         * 格式化日志消息
         * @param {string} level - 日志级别
         * @param {string} module - 模块名称
         * @param {string} message - 消息
         * @param {object} context - 上下文对象（可选）
         * @returns {string}
         */
        _formatMessage(level, module, message, context) {
            const levelUpper = level.toUpperCase();
            const modulePart = module ? `[${module}]` : '';
            let formatted = `[${levelUpper}] ${modulePart} ${message}`;
            
            if (context && Object.keys(context).length > 0) {
                try {
                    const contextStr = JSON.stringify(context, null, 0);
                    formatted += ` ${contextStr}`;
                } catch (e) {
                    formatted += ` [上下文序列化失败: ${e.message}]`;
                }
            }
            
            return formatted;
        }
        
        /**
         * 原始日志输出（避免循环调用）
         * @private
         */
        _rawLog(level, message, ...args) {
            const method = level === 'error' ? 'error' : 
                          level === 'warn' ? 'warn' : 
                          level === 'debug' ? 'debug' : 'info';
            console[method](message, ...args);
        }
        
        /**
         * 记录日志（内部方法）
         * @private
         */
        _log(level, module, message, context, ...args) {
            if (!this.enabled || !this._shouldLog(level) || !this._isModuleEnabled(module)) {
                return;
            }
            
            const formattedMessage = this._formatMessage(level, module, message, context);
            
            // 根据级别选择输出方法
            const consoleMethod = level === 'error' ? 'error' : 
                                 level === 'warn' ? 'warn' : 
                                 level === 'debug' ? 'debug' : 'info';
            
            console[consoleMethod](formattedMessage, ...args);
            
            // 可选：保存到历史记录
            if (this.logHistory.length >= this.maxHistorySize) {
                this.logHistory.shift();
            }
            this.logHistory.push({
                timestamp: new Date().toISOString(),
                level,
                module,
                message,
                context,
                args: args.length > 0 ? args : undefined
            });
        }
        
        /**
         * 调试日志
         * @param {string} module - 模块名称
         * @param {string} message - 消息
         * @param {object} context - 上下文对象（可选）
         * @param {...any} args - 额外参数
         */
        debug(module, message, context, ...args) {
            if (typeof module === 'string' && typeof message === 'string') {
                this._log('debug', module, message, context, ...args);
            } else {
                // 兼容旧格式：logger.debug('[Module] message', ...args)
                this._log('debug', '', module, message, ...args);
            }
        }
        
        /**
         * 信息日志
         * @param {string} module - 模块名称
         * @param {string} message - 消息
         * @param {object} context - 上下文对象（可选）
         * @param {...any} args - 额外参数
         */
        info(module, message, context, ...args) {
            if (typeof module === 'string' && typeof message === 'string') {
                this._log('info', module, message, context, ...args);
            } else {
                // 兼容旧格式：logger.info('[Module] message', ...args)
                this._log('info', '', module, message, ...args);
            }
        }
        
        /**
         * 警告日志
         * @param {string} module - 模块名称
         * @param {string} message - 消息
         * @param {object} context - 上下文对象（可选）
         * @param {...any} args - 额外参数
         */
        warn(module, message, context, ...args) {
            if (typeof module === 'string' && typeof message === 'string') {
                this._log('warn', module, message, context, ...args);
            } else {
                // 兼容旧格式：logger.warn('[Module] message', ...args)
                this._log('warn', '', module, message, ...args);
            }
        }
        
        /**
         * 错误日志
         * @param {string} module - 模块名称
         * @param {string} message - 消息
         * @param {object} context - 上下文对象（可选）
         * @param {...any} args - 额外参数
         */
        error(module, message, context, ...args) {
            if (typeof module === 'string' && typeof message === 'string') {
                this._log('error', module, message, context, ...args);
            } else {
                // 兼容旧格式：logger.error('[Module] message', ...args)
                this._log('error', '', module, module, message, ...args);
            }
        }
        
        /**
         * 开始性能计时
         * @param {string} module - 模块名称
         * @param {string} label - 计时标签
         */
        time(module, label) {
            const timerKey = `${module}:${label}`;
            this.timers.set(timerKey, performance.now());
            this.debug(module, `开始计时: ${label}`);
        }
        
        /**
         * 结束性能计时并输出
         * @param {string} module - 模块名称
         * @param {string} label - 计时标签
         */
        timeEnd(module, label) {
            const timerKey = `${module}:${label}`;
            const startTime = this.timers.get(timerKey);
            if (startTime !== undefined) {
                const duration = performance.now() - startTime;
                this.debug(module, `计时结束: ${label}`, { duration: `${duration.toFixed(2)}ms` });
                this.timers.delete(timerKey);
            } else {
                this.warn(module, `未找到计时器: ${label}`);
            }
        }
        
        /**
         * 开始日志分组
         * @param {string} module - 模块名称
         * @param {string} label - 分组标签
         */
        group(module, label) {
            if (this.enabled && this._shouldLog('debug') && this._isModuleEnabled(module)) {
                console.group(`[${module}] ${label}`);
            }
        }
        
        /**
         * 结束日志分组
         */
        groupEnd() {
            if (this.enabled && this._shouldLog('debug')) {
                console.groupEnd();
            }
        }
        
        /**
         * 获取日志历史
         * @param {number} count - 获取最近 N 条日志
         * @returns {Array}
         */
        getHistory(count) {
            if (count) {
                return this.logHistory.slice(-count);
            }
            return this.logHistory.slice();
        }
        
        /**
         * 清空日志历史
         */
        clearHistory() {
            this.logHistory = [];
        }
        
        /**
         * 检查是否应该记录该级别的日志
         * @private
         */
        _shouldLog(level) {
            return this.levels[level] >= this.levels[this.level];
        }
    }
    
    // 创建全局日志实例
    const logger = new Logger();
    
    // 从 URL 参数或 localStorage 读取日志配置
    (function() {
        const urlParams = new URLSearchParams(window.location.search);
        
        // 日志级别
        const logLevel = urlParams.get('logLevel') || localStorage.getItem('editorLogLevel') || 'info';
        logger.setLevel(logLevel);
        
        // 启用的模块（逗号分隔）
        const enabledModules = urlParams.get('logModules') || localStorage.getItem('editorLogModules');
        if (enabledModules) {
            logger.enableModules(enabledModules.split(',').map(m => m.trim()));
        }
        
        // 禁用的模块（逗号分隔）
        const disabledModules = urlParams.get('logDisableModules') || localStorage.getItem('editorLogDisableModules');
        if (disabledModules) {
            logger.disableModules(disabledModules.split(',').map(m => m.trim()));
        }
    })();
    
    /**
     * 日志辅助函数：简化日志调用
     * 使用方式：
     *   log.debug(LOG_MODULES.EDITOR, '消息', {context: 'value'})
     *   log.info(LOG_MODULES.EDITOR, '消息')
     *   log.warn(LOG_MODULES.EDITOR, '消息', error)
     *   log.error(LOG_MODULES.EDITOR, '消息', {error: error.message})
     */
    const log = {
        debug: (module, message, context, ...args) => logger.debug(module, message, context, ...args),
        info: (module, message, context, ...args) => logger.info(module, message, context, ...args),
        warn: (module, message, context, ...args) => logger.warn(module, message, context, ...args),
        error: (module, message, context, ...args) => logger.error(module, message, context, ...args),
        time: (module, label) => logger.time(module, label),
        timeEnd: (module, label) => logger.timeEnd(module, label),
        group: (module, label) => logger.group(module, label),
        groupEnd: () => logger.groupEnd()
    };
    
    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Logger = Logger;
    window.logger = logger;
    window.log = log; // 全局 log 辅助函数
    window.MiNoteLogger = logger; // 向后兼容
    
})();
