/**
 * Command 模块
 * 提供命令系统：Command 基类和 CommandManager
 * 依赖: logger, constants
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { FORMAT: 'Format' };
    const OPERATION_TYPES = window.OPERATION_TYPES || { FORMAT: 'format', OTHER: 'other' };

    /**
     * 命令基类
     * 参考 CKEditor 5 的命令系统设计
     * 统一所有操作的接口，支持执行、撤销、状态检查
     */
    class Command {
        /**
         * 创建命令
         * @param {string} name - 命令名称
         * @param {Object} options - 命令选项
         * @param {Function} options.execute - 执行函数
         * @param {Function} options.undo - 撤销函数（可选）
         * @param {Function} options.canExecute - 是否可执行检查函数（可选）
         * @param {Function} options.getState - 获取状态函数（可选）
         * @param {string} options.type - 操作类型（用于历史记录）
         */
        constructor(name, options = {}) {
            this.name = name;
            this.executeFn = options.execute;
            this.undoFn = options.undo;
            this.canExecuteFn = options.canExecute;
            this.getStateFn = options.getState;
            this.type = options.type || OPERATION_TYPES.OTHER;
            this.state = null; // 命令执行后的状态（用于撤销）
            this.metadata = options.metadata || {}; // 命令元数据
            
            if (!this.executeFn) {
                throw new Error(`Command ${name} must have an execute function`);
            }
        }
        
        /**
         * 执行命令
         * @param {Object} context - 执行上下文
         * @returns {*} 执行结果
         */
        execute(context = {}) {
            // 检查是否可执行
            if (!this.canExecute(context)) {
                const error = new Error(`Command ${this.name} cannot be executed in current context`);
                log.warn(LOG_MODULES.FORMAT, '命令无法执行', { 
                    command: this.name, 
                    context 
                });
                throw error;
            }
            
            try {
                // 执行命令
                this.state = this.executeFn(context);
                
                log.debug(LOG_MODULES.FORMAT, '命令执行成功', { 
                    command: this.name,
                    type: this.type
                });
                
                return this.state;
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '命令执行失败', { 
                    command: this.name, 
                    error: error.message,
                    stack: error.stack
                });
                throw error;
            }
        }
        
        /**
         * 撤销命令
         * @param {Object} context - 执行上下文
         * @returns {*} 撤销结果
         */
        undo(context = {}) {
            if (!this.undoFn) {
                throw new Error(`Command ${this.name} does not support undo`);
            }
            
            if (this.state === null) {
                throw new Error(`Command ${this.name} has no state to undo`);
            }
            
            try {
                const result = this.undoFn(context, this.state);
                
                log.debug(LOG_MODULES.FORMAT, '命令撤销成功', { 
                    command: this.name 
                });
                
                return result;
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '命令撤销失败', { 
                    command: this.name, 
                    error: error.message 
                });
                throw error;
            }
        }
        
        /**
         * 检查命令是否可执行
         * @param {Object} context - 执行上下文
         * @returns {boolean} 是否可执行
         */
        canExecute(context = {}) {
            if (!this.canExecuteFn) {
                return true; // 默认可以执行
            }
            
            try {
                return this.canExecuteFn(context);
            } catch (error) {
                log.warn(LOG_MODULES.FORMAT, '命令可执行性检查失败', { 
                    command: this.name, 
                    error: error.message 
                });
                return false;
            }
        }
        
        /**
         * 获取命令状态
         * @param {Object} context - 执行上下文
         * @returns {*} 命令状态
         */
        getState(context = {}) {
            if (!this.getStateFn) {
                return null;
            }
            
            try {
                return this.getStateFn(context);
            } catch (error) {
                log.warn(LOG_MODULES.FORMAT, '获取命令状态失败', { 
                    command: this.name, 
                    error: error.message 
                });
                return null;
            }
        }
    }
    
    /**
     * 命令管理器
     * 负责命令的注册、执行和管理
     */
    class CommandManager {
        constructor(domWriter) {
            this.domWriter = domWriter;
            this.commands = new Map(); // 命令注册表
            this.commandHistory = []; // 命令执行历史
            this.historyIndex = -1;
            this.stateCache = new Map(); // 状态缓存
            this.stateCacheTimeout = 50; // 状态缓存超时时间（毫秒）
        }
        
        /**
         * 注册命令
         * @param {string} name - 命令名称
         * @param {Command|Object} command - 命令对象或命令选项
         */
        register(name, command) {
            if (command instanceof Command) {
                this.commands.set(name, command);
            } else {
                // 如果是选项对象，创建命令
                this.commands.set(name, new Command(name, command));
            }
            
            log.debug(LOG_MODULES.FORMAT, '注册命令', { command: name });
        }
        
        /**
         * 执行命令
         * @param {string} name - 命令名称
         * @param {Object} context - 执行上下文
         * @returns {*} 执行结果
         */
        execute(name, context = {}) {
            const command = this.commands.get(name);
            if (!command) {
                throw new Error(`Command ${name} is not registered`);
            }
            
            // 执行命令
            const result = command.execute(context);
            
            // 如果命令支持撤销，记录到历史
            if (command.undoFn) {
                this._addToCommandHistory(name, command, context);
            }
            
            return result;
        }
        
        /**
         * 撤销上一个命令
         * @returns {boolean} 是否成功撤销
         */
        undo() {
            if (this.historyIndex < 0) {
                return false;
            }
            
            const historyItem = this.commandHistory[this.historyIndex];
            const command = this.commands.get(historyItem.name);
            
            if (!command || !command.undoFn) {
                return false;
            }
            
            try {
                command.undo(historyItem.context);
                this.historyIndex--;
                return true;
            } catch (error) {
                log.error(LOG_MODULES.FORMAT, '撤销命令失败', { 
                    command: historyItem.name, 
                    error: error.message 
                });
                return false;
            }
        }
        
        /**
         * 检查命令是否可执行
         * @param {string} name - 命令名称
         * @param {Object} context - 执行上下文
         * @returns {boolean} 是否可执行
         */
        canExecute(name, context = {}) {
            const command = this.commands.get(name);
            if (!command) {
                return false;
            }
            
            return command.canExecute(context);
        }
        
        /**
         * 获取命令状态
         * @param {string} name - 命令名称
         * @param {Object} context - 执行上下文
         * @param {boolean} useCache - 是否使用缓存（默认 true）
         * @returns {*} 命令状态
         */
        getState(name, context = {}, useCache = true) {
            const command = this.commands.get(name);
            if (!command) {
                return null;
            }
            
            // 检查缓存
            if (useCache && this.stateCache.has(name)) {
                const cached = this.stateCache.get(name);
                const now = Date.now();
                if (now - cached.timestamp < this.stateCacheTimeout) {
                    return cached.state;
                }
            }
            
            // 获取新状态
            const state = command.getState(context);
            
            // 更新缓存
            if (useCache) {
                this.stateCache.set(name, {
                    state: state,
                    timestamp: Date.now()
                });
            }
            
            return state;
        }
        
        /**
         * 批量获取多个命令的状态
         * @param {string[]} names - 命令名称数组
         * @param {Object} context - 执行上下文
         * @returns {Object} 命令状态映射
         */
        getStates(names, context = {}) {
            const states = {};
            names.forEach(name => {
                states[name] = this.getState(name, context);
            });
            return states;
        }
        
        /**
         * 清除状态缓存
         * @param {string} name - 命令名称（可选，不提供则清除所有缓存）
         */
        clearStateCache(name = null) {
            if (name) {
                this.stateCache.delete(name);
            } else {
                this.stateCache.clear();
            }
        }
        
        /**
         * 检查命令是否可执行（批量检查）
         * @param {string[]} names - 命令名称数组
         * @param {Object} context - 执行上下文
         * @returns {Object} 命令可执行性映射
         */
        canExecuteBatch(names, context = {}) {
            const results = {};
            names.forEach(name => {
                results[name] = this.canExecute(name, context);
            });
            return results;
        }
        
        /**
         * 添加到命令历史
         * @private
         */
        _addToCommandHistory(name, command, context) {
            // 如果当前不在历史末尾，删除后面的记录
            if (this.historyIndex < this.commandHistory.length - 1) {
                this.commandHistory = this.commandHistory.slice(0, this.historyIndex + 1);
            }
            
            this.commandHistory.push({
                name: name,
                command: command,
                context: context,
                timestamp: Date.now()
            });
            
            this.historyIndex = this.commandHistory.length - 1;
        }
    }
    
    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.Command = {
        Command: Command,
        CommandManager: CommandManager
    };
    
    // 向后兼容：直接暴露到全局
    window.Command = Command;
    window.CommandManager = CommandManager;
    
})();
