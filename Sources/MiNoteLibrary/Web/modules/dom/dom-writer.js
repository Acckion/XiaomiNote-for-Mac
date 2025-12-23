/**
 * DOMWriter 模块
 * 提供统一的 DOM 操作接口，支持批量操作、撤销/重做、增量记录
 * 依赖: logger, constants
 */

(function() {
    'use strict';

    // 获取依赖
    const log = window.log || console;
    const LOG_MODULES = window.LOG_MODULES || { DOM_WRITER: 'DOMWriter', HISTORY: 'History' };
    const OPERATION_TYPES = window.OPERATION_TYPES || { INPUT: 'input', DELETE: 'delete', FORMAT: 'format', FORMAT_REMOVE: 'format_remove', BATCH: 'batch', OTHER: 'other' };

    // 注意：以下全局变量和函数需要在 editor.html 中定义
    // - isLoadingContent
    // - isComposing
    // - normalizeCursorPosition()
    // - syncFormatState()
    // - notifyContentChanged()
    // - window.MiNoteWebEditor._saveCursorPosition()
    // - window.MiNoteWebEditor._restoreCursorPosition()

    class DOMWriter {
            constructor(editor) {
                this.editor = editor;
                this.batchMode = false;
                this.batchOperations = [];
                this.shouldSyncState = false;
                
                // 操作历史（用于撤销/重做）
                this.operationHistory = [];
                this.historyIndex = -1;
                this.maxHistorySize = 50; // 最多保存 50 个操作
                this.useIncrementalRecording = true; // 是否使用增量记录
                this.snapshotInterval = 10; // 每隔 N 个操作保存一个完整快照
                this.lastSnapshotIndex = -1; // 最后一个完整快照的索引
            }

            /**
             * 开始批量操作模式
             * 在批量操作期间，DOM 更新会延迟执行
             */
            beginBatch() {
                this.batchMode = true;
                this.batchOperations = [];
            }

            /**
             * 结束批量操作模式
             * 执行所有延迟的 DOM 操作
             * @param {Object} metadata - 批量操作的元数据（用于历史记录）
             */
            endBatch(metadata = null) {
                this.batchMode = false;
                const operations = this.batchOperations;
                this.batchOperations = [];
                
                // 记录批量操作前的状态（使用增量记录）
                const previousState = this.operationHistory.length > 0 && this.historyIndex >= 0
                    ? (this.operationHistory[this.historyIndex].afterState || this.operationHistory[this.historyIndex].beforeState)
                    : null;
                const beforeState = this._captureState(this.useIncrementalRecording, previousState);
                const savedPosition = window.MiNoteWebEditor._saveCursorPosition();
                
                // 执行所有操作
                operations.forEach(op => op());
                
                // 记录批量操作后的状态（使用增量记录）
                const afterState = this._captureState(this.useIncrementalRecording, beforeState);
                
                // 添加到历史记录（如果不是加载内容操作）
                if (!isLoadingContent && metadata !== null) {
                    this._addToHistory({
                        type: metadata.type || OPERATION_TYPES.BATCH,
                        command: metadata.command || null,
                        value: metadata.value || null,
                        format: metadata.format || null,
                        beforeState: beforeState,
                        afterState: afterState,
                        savedPosition: savedPosition,
                        timestamp: Date.now(),
                        isBatch: metadata.isBatch !== false // 批量操作默认允许合并
                    });
                }
                
                // 批量操作后，统一处理光标和状态
                if (this.shouldSyncState) {
                    requestAnimationFrame(() => {
                        if (!isComposing && !isLoadingContent) {
                            normalizeCursorPosition();
                            syncFormatState();
                        }
                    });
                    this.shouldSyncState = false;
                }
            }

            /**
             * 执行 DOM 操作（自动处理光标和状态）
             * @param {Function} operation - DOM 操作函数
             * @param {boolean} syncState - 是否同步状态（默认 true）
             * @param {Object} metadata - 操作元数据（用于历史记录）
             */
            execute(operation, syncState = true, metadata = null) {
                // 保存光标位置
                const savedPosition = window.MiNoteWebEditor._saveCursorPosition();
                
                // 记录操作前的状态（用于撤销，使用增量记录）
                const previousState = this.operationHistory.length > 0 && this.historyIndex >= 0
                    ? (this.operationHistory[this.historyIndex].afterState || this.operationHistory[this.historyIndex].beforeState)
                    : null;
                const beforeState = this._captureState(this.useIncrementalRecording, previousState);
                
                if (this.batchMode) {
                    // 批量模式：延迟执行
                    this.batchOperations.push(() => {
                        operation();
                        if (syncState) {
                            this.shouldSyncState = true;
                        }
                    });
                } else {
                    // 立即执行
                    operation();
                    
                    // 记录操作后的状态（使用增量记录）
                    const afterState = this._captureState(this.useIncrementalRecording, beforeState);
                    
                    // 添加到历史记录（如果不是加载内容操作）
                    // 注意：metadata 为 null 时表示不记录历史（如加载内容、属性变化等）
                    if (!isLoadingContent && metadata !== null) {
                        this._addToHistory({
                            type: metadata.type || OPERATION_TYPES.OTHER,
                            command: metadata.command || null,
                            value: metadata.value || null,
                            format: metadata.format || null,
                            beforeState: beforeState,
                            afterState: afterState,
                            savedPosition: savedPosition,
                            timestamp: Date.now(),
                            isBatch: metadata.isBatch || false // 是否允许合并
                        });
                    }
                    
                    // 恢复光标位置
                    if (savedPosition) {
                        requestAnimationFrame(() => {
                            window.MiNoteWebEditor._restoreCursorPosition(savedPosition);
                        });
                    }
                    
                    // 同步状态
                    if (syncState) {
                        requestAnimationFrame(() => {
                            if (!isComposing && !isLoadingContent) {
                                normalizeCursorPosition();
                                syncFormatState();
                            }
                        });
                    }
                }
            }

            /**
             * 执行操作并记录历史（便捷方法）
             * @param {Function} operation - DOM 操作函数
             * @param {string} type - 操作类型
             * @param {boolean} syncState - 是否同步状态（默认 true）
             */
            executeWithHistory(operation, type, syncState = true) {
                this.execute(operation, syncState, { type: type });
            }

            /**
             * 执行 execCommand 并记录历史
             * 由于 execCommand 是浏览器原生 API，不能直接包装，所以需要在调用前后记录状态
             * @param {string} command - execCommand 命令
             * @param {boolean} showUI - 是否显示 UI（默认 false）
             * @param {string} value - 命令值（可选）
             * @param {string} type - 操作类型（用于历史记录）
             * @returns {boolean} execCommand 的返回值
             */
            executeCommandWithHistory(command, showUI = false, value = null, type = null) {
                // 如果没有指定类型，根据 command 推断
                if (!type) {
                    // 推断操作类型
                    if (command === 'insertText' || command === 'insertHTML') {
                        type = OPERATION_TYPES.INPUT;
                    } else if (command === 'delete' || command === 'forwardDelete') {
                        type = OPERATION_TYPES.DELETE;
                    } else if (command.startsWith('format')) {
                        type = OPERATION_TYPES.FORMAT;
                    } else {
                        type = OPERATION_TYPES.OTHER;
                    }
                }
                
                // 记录操作前的状态（使用增量记录）
                const previousState = this.operationHistory.length > 0 && this.historyIndex >= 0
                    ? (this.operationHistory[this.historyIndex].afterState || this.operationHistory[this.historyIndex].beforeState)
                    : null;
                const beforeState = this._captureState(this.useIncrementalRecording, previousState);
                const savedPosition = window.MiNoteWebEditor._saveCursorPosition();
                
                // 执行 execCommand
                const result = document.execCommand(command, showUI, value);
                
                // 如果执行成功，记录操作后的状态
                if (result && !isLoadingContent) {
                    // 延迟捕获状态，确保 DOM 更新完成
                    requestAnimationFrame(() => {
                        const afterState = this._captureState(this.useIncrementalRecording, beforeState);
                        
                        // 添加到历史记录（包含操作类型和命令信息）
                        // 格式操作标记为不合并（每次都是独立的撤销步骤）
                        this._addToHistory({
                            type: type,
                            command: command,
                            value: value,
                            beforeState: beforeState,
                            afterState: afterState,
                            savedPosition: savedPosition,
                            timestamp: Date.now(),
                            isBatch: false // 格式操作不是批量操作，不合并
                        });
                        
                        // 同步状态
                        if (!isComposing && !isLoadingContent) {
                            normalizeCursorPosition();
                            syncFormatState();
                        }
                    });
                }
                
                return result;
            }

            /**
             * DOM Diff 工具类
             * 用于计算两个 DOM 状态之间的差异，实现增量记录
             */
            static DOMDiff = class {
                /**
                 * 计算两个 HTML 字符串之间的差异
                 * @param {string} oldHtml - 旧的 HTML
                 * @param {string} newHtml - 新的 HTML
                 * @returns {Object} 差异对象
                 */
                static diff(oldHtml, newHtml) {
                    // 如果完全相同，返回空差异
                    if (oldHtml === newHtml) {
                        return { type: 'no-change' };
                    }
                    
                    // 简单实现：对于小变化，记录变化位置和内容
                    // 对于大变化，仍然使用完整快照（后续可以优化）
                    const oldLength = oldHtml.length;
                    const newLength = newHtml.length;
                    
                    // 如果变化超过 50%，使用完整快照（更高效）
                    const changeRatio = Math.abs(newLength - oldLength) / Math.max(oldLength, 1);
                    if (changeRatio > 0.5) {
                        return {
                            type: 'full-snapshot',
                            html: newHtml
                        };
                    }
                    
                    // 计算差异：找到第一个不同的位置和最后一个不同的位置
                    let startDiff = 0;
                    let endDiff = Math.min(oldLength, newLength);
                    
                    // 从前面找到第一个不同的位置
                    while (startDiff < endDiff && oldHtml[startDiff] === newHtml[startDiff]) {
                        startDiff++;
                    }
                    
                    // 从后面找到最后一个不同的位置
                    let oldEnd = oldLength - 1;
                    let newEnd = newLength - 1;
                    while (oldEnd >= startDiff && newEnd >= startDiff && 
                           oldHtml[oldEnd] === newHtml[newEnd]) {
                        oldEnd--;
                        newEnd--;
                    }
                    
                    // 提取变化的部分
                    const oldChanged = oldHtml.substring(startDiff, oldEnd + 1);
                    const newChanged = newHtml.substring(startDiff, newEnd + 1);
                    
                    return {
                        type: 'incremental',
                        start: startDiff,
                        oldLength: oldChanged.length,
                        newLength: newChanged.length,
                        oldContent: oldChanged,
                        newContent: newChanged
                    };
                }
                
                /**
                 * 根据差异恢复 HTML
                 * @param {string} baseHtml - 基础 HTML
                 * @param {Object} diff - 差异对象
                 * @returns {string} 恢复后的 HTML
                 */
                static apply(baseHtml, diff) {
                    if (diff.type === 'no-change') {
                        return baseHtml;
                    }
                    
                    if (diff.type === 'full-snapshot') {
                        return diff.html;
                    }
                    
                    if (diff.type === 'incremental') {
                        const before = baseHtml.substring(0, diff.start);
                        const after = baseHtml.substring(diff.start + diff.oldLength);
                        return before + diff.newContent + after;
                    }
                    
                    // 未知类型，返回原 HTML
                    log.warn(LOG_MODULES.HISTORY, '未知的差异类型', { type: diff.type });
                    return baseHtml;
                }
            };
            
            /**
             * 捕获当前编辑器状态（用于历史记录）
             * @param {boolean} useIncremental - 是否使用增量记录（默认 false，逐步启用）
             * @param {Object} previousState - 前一个状态（用于增量记录）
             * @returns {Object} 状态快照或增量差异
             */
            _captureState(useIncremental = false, previousState = null) {
                const html = this.editor.innerHTML;
                const cursorPosition = window.MiNoteWebEditor._saveCursorPosition();
                
                // 如果使用增量记录且有前一个状态
                if (useIncremental && previousState && previousState.html) {
                    try {
                        const diff = DOMWriter.DOMDiff.diff(previousState.html, html);
                        
                        // 如果差异类型是增量，返回增量记录
                        if (diff.type === 'incremental') {
                            return {
                                type: 'incremental',
                                diff: diff,
                                cursorPosition: cursorPosition,
                                baseState: previousState // 引用基础状态
                            };
                        }
                        
                        // 如果差异太大，使用完整快照
                        if (diff.type === 'full-snapshot') {
                            return {
                                type: 'full-snapshot',
                                html: diff.html,
                                cursorPosition: cursorPosition
                            };
                        }
                    } catch (error) {
                        log.warn(LOG_MODULES.HISTORY, '增量记录失败，使用完整快照', { 
                            error: error.message 
                        });
                    }
                }
                
                // 默认使用完整快照
                return {
                    type: 'full-snapshot',
                    html: html,
                    cursorPosition: cursorPosition
                };
            }
            
            /**
             * 恢复状态（支持增量记录）
             * @param {Object} state - 状态对象（可能是完整快照或增量差异）
             * @returns {Object} 恢复后的完整状态
             */
            _restoreState(state) {
                if (state.type === 'full-snapshot') {
                    return {
                        html: state.html,
                        cursorPosition: state.cursorPosition
                    };
                }
                
                if (state.type === 'incremental' && state.baseState) {
                    // 需要先恢复基础状态
                    const baseState = this._restoreState(state.baseState);
                    const html = DOMWriter.DOMDiff.apply(baseState.html, state.diff);
                    return {
                        html: html,
                        cursorPosition: state.cursorPosition
                    };
                }
                
                // 未知类型，尝试直接使用
                log.warn(LOG_MODULES.HISTORY, '未知的状态类型，尝试直接使用', { 
                    type: state.type 
                });
                return {
                    html: state.html || '',
                    cursorPosition: state.cursorPosition
                };
            }

            /**
             * 检查两个操作是否可以合并
             * 参考 CKEditor 5 的实现：只有连续的用户输入操作才合并，格式操作不合并
             * @param {Object} op1 - 第一个操作
             * @param {Object} op2 - 第二个操作
             * @returns {boolean} 是否可以合并
             */
            _shouldMergeOperations(op1, op2) {
                // 必须相同类型
                if (op1.type !== op2.type) {
                    return false;
                }
                
                // 时间间隔检查
                const timeDiff = op2.timestamp - op1.timestamp;
                
                // 输入操作：只合并非常短时间内的连续输入（100ms）
                // 这样可以合并快速连续输入，但不会合并用户停顿后的输入
                if (op1.type === OPERATION_TYPES.INPUT) {
                    const inputMergeWindow = 100; // 100ms 内的输入可以合并
                    if (timeDiff > inputMergeWindow) {
                        return false;
                    }
                    
                    // 限制合并次数，避免无限合并（最多合并 50 次）
                    const maxMergedCount = 50;
                    if (op1.mergedCount && op1.mergedCount >= maxMergedCount) {
                        return false;
                    }
                    
                    // 检查光标位置是否变化太大（如果光标位置变化很大，可能是用户移动了光标，不应该合并）
                    if (op1.savedPosition && op2.savedPosition) {
                        // 简单检查：如果两个操作的光标位置路径长度差异很大，不合并
                        const pos1Path = op1.savedPosition.path || [];
                        const pos2Path = op2.savedPosition.path || [];
                        if (Math.abs(pos1Path.length - pos2Path.length) > 2) {
                            return false;
                        }
                    }
                    
                    return true;
                }
                
                // 删除操作：只合并短时间内的连续删除（150ms）
                if (op1.type === OPERATION_TYPES.DELETE) {
                    const deleteMergeWindow = 150; // 150ms 内的删除可以合并
                    if (timeDiff > deleteMergeWindow) {
                        return false;
                    }
                    
                    // 限制合并次数
                    const maxMergedCount = 30;
                    if (op1.mergedCount && op1.mergedCount >= maxMergedCount) {
                        return false;
                    }
                    
                    return true;
                }
                
                // 格式操作：默认不合并（每次格式操作都是独立的撤销步骤）
                // 只有在明确的批量操作模式下才合并
                if (op1.type === OPERATION_TYPES.FORMAT || op1.type === OPERATION_TYPES.FORMAT_REMOVE) {
                    // 格式操作不合并，除非是明确的批量操作
                    if (op1.isBatch && op2.isBatch) {
                        // 批量操作可以合并
                        return true;
                    }
                    return false;
                }
                
                // 其他操作：只有批量操作才合并
                if (op1.type === OPERATION_TYPES.BATCH && op2.type === OPERATION_TYPES.BATCH) {
                    // 批量操作可以合并（如果时间间隔很短）
                    const batchMergeWindow = 200;
                    return timeDiff <= batchMergeWindow;
                }
                
                // 其他操作默认不合并
                return false;
            }
            
            /**
             * 合并两个操作
             * @param {Object} op1 - 第一个操作（将被合并到）
             * @param {Object} op2 - 第二个操作（将被合并）
             * @returns {Object} 合并后的操作
             */
            _mergeOperations(op1, op2) {
                // 合并后的操作使用第一个操作的时间戳和 beforeState
                // 使用第二个操作的 afterState（最新的状态）
                return {
                    ...op1,
                    afterState: op2.afterState,
                    savedPosition: op2.savedPosition, // 使用最新的光标位置
                    mergedCount: (op1.mergedCount || 1) + 1, // 记录合并次数
                    lastTimestamp: op2.timestamp // 记录最后一次操作时间
                };
            }
            
            /**
             * 添加到操作历史（支持操作合并和增量记录）
             * @param {Object} operation - 操作记录
             */
            _addToHistory(operation) {
                // 如果当前不在历史末尾，删除后面的记录（重做分支被覆盖）
                if (this.historyIndex < this.operationHistory.length - 1) {
                    this.operationHistory = this.operationHistory.slice(0, this.historyIndex + 1);
                    // 重置快照索引
                    this.lastSnapshotIndex = Math.min(this.lastSnapshotIndex, this.historyIndex);
                }
                
                // 检查是否可以与上一个操作合并
                if (this.operationHistory.length > 0) {
                    const lastOperation = this.operationHistory[this.operationHistory.length - 1];
                    
                    if (this._shouldMergeOperations(lastOperation, operation)) {
                        // 合并操作：替换最后一个操作
                        log.debug(LOG_MODULES.HISTORY, '合并操作', { 
                            type: operation.type, 
                            mergedCount: (lastOperation.mergedCount || 1) + 1 
                        });
                        
                        const mergedOperation = this._mergeOperations(lastOperation, operation);
                        
                        // 如果使用增量记录，需要重新计算 afterState
                        if (this.useIncrementalRecording && mergedOperation.afterState) {
                            const previousState = lastOperation.beforeState;
                            mergedOperation.afterState = this._captureState(true, previousState);
                        }
                        
                        this.operationHistory[this.operationHistory.length - 1] = mergedOperation;
                        this.historyIndex = this.operationHistory.length - 1;
                        return;
                    }
                }
                
                // 如果使用增量记录，尝试使用增量状态
                if (this.useIncrementalRecording && this.operationHistory.length > 0) {
                    const lastOperation = this.operationHistory[this.operationHistory.length - 1];
                    const previousState = lastOperation.afterState || lastOperation.beforeState;
                    
                    // 计算是否需要保存完整快照（每隔 N 个操作）
                    const shouldSaveSnapshot = (this.operationHistory.length - this.lastSnapshotIndex) >= this.snapshotInterval;
                    
                    if (shouldSaveSnapshot) {
                        // 保存完整快照
                        operation.beforeState = this._captureState(false);
                        operation.afterState = this._captureState(false);
                        this.lastSnapshotIndex = this.operationHistory.length;
                        log.debug(LOG_MODULES.HISTORY, '保存完整快照', { 
                            index: this.lastSnapshotIndex 
                        });
                    } else {
                        // 使用增量记录
                        operation.beforeState = this._captureState(true, previousState);
                        operation.afterState = this._captureState(true, operation.beforeState);
                        log.debug(LOG_MODULES.HISTORY, '使用增量记录', { 
                            type: operation.type 
                        });
                    }
                } else {
                    // 不使用增量记录，使用完整快照
                    operation.beforeState = this._captureState(false);
                    operation.afterState = this._captureState(false);
                }
                
                // 不能合并，添加新操作
                this.operationHistory.push(operation);
                this.historyIndex = this.operationHistory.length - 1;
                
                // 限制历史大小
                if (this.operationHistory.length > this.maxHistorySize) {
                    this.operationHistory.shift();
                    this.historyIndex--;
                    this.lastSnapshotIndex--;
                    
                    // 如果删除了快照，需要重新计算快照位置
                    if (this.lastSnapshotIndex < 0) {
                        this._rebuildSnapshots();
                    }
                }
            }
            
            /**
             * 重建快照（当历史记录被截断时）
             * @private
             */
            _rebuildSnapshots() {
                // 找到第一个完整快照
                let firstSnapshotIndex = -1;
                for (let i = 0; i < this.operationHistory.length; i++) {
                    const op = this.operationHistory[i];
                    if (op.beforeState && op.beforeState.type === 'full-snapshot') {
                        firstSnapshotIndex = i;
                        break;
                    }
                }
                
                // 如果找到了快照，从那里开始重新计算
                if (firstSnapshotIndex >= 0) {
                    this.lastSnapshotIndex = firstSnapshotIndex;
                } else {
                    // 如果没有快照，将第一个操作设为快照
                    if (this.operationHistory.length > 0) {
                        const firstOp = this.operationHistory[0];
                        firstOp.beforeState = this._captureState(false);
                        firstOp.afterState = this._captureState(false);
                        this.lastSnapshotIndex = 0;
                    }
                }
            }

            /**
             * 撤销上一个操作（支持增量记录）
             * @returns {boolean} 是否成功撤销
             */
            undo() {
                if (this.historyIndex < 0) {
                    return false; // 没有可撤销的操作
                }
                
                const operation = this.operationHistory[this.historyIndex];
                
                // 恢复之前的状态（支持增量记录）
                const restoredState = this._restoreState(operation.beforeState);
                this.editor.innerHTML = restoredState.html;
                
                // 恢复光标位置
                if (restoredState.cursorPosition) {
                    requestAnimationFrame(() => {
                        window.MiNoteWebEditor._restoreCursorPosition(restoredState.cursorPosition);
                    });
                }
                
                this.historyIndex--;
                
                // 同步状态
                requestAnimationFrame(() => {
                    if (!isComposing && !isLoadingContent) {
                        normalizeCursorPosition();
                        syncFormatState();
                        notifyContentChanged();
                    }
                });
                
                return true;
            }

            /**
             * 重做上一个操作（支持增量记录）
             * @returns {boolean} 是否成功重做
             */
            redo() {
                if (this.historyIndex >= this.operationHistory.length - 1) {
                    return false; // 没有可重做的操作
                }
                
                this.historyIndex++;
                const operation = this.operationHistory[this.historyIndex];
                
                // 恢复之后的状态（支持增量记录）
                const restoredState = this._restoreState(operation.afterState);
                this.editor.innerHTML = restoredState.html;
                
                // 恢复光标位置
                if (restoredState.cursorPosition) {
                    requestAnimationFrame(() => {
                        window.MiNoteWebEditor._restoreCursorPosition(restoredState.cursorPosition);
                    });
                }
                
                // 同步状态
                requestAnimationFrame(() => {
                    if (!isComposing && !isLoadingContent) {
                        normalizeCursorPosition();
                        syncFormatState();
                        notifyContentChanged();
                    }
                });
                
                return true;
            }

            /**
             * 清空操作历史
             */
            clearHistory() {
                this.operationHistory = [];
                this.historyIndex = -1;
            }

            /**
             * 检查是否可以撤销
             * @returns {boolean}
             */
            canUndo() {
                return this.historyIndex >= 0;
            }

            /**
             * 检查是否可以重做
             * @returns {boolean}
             */
            canRedo() {
                return this.historyIndex < this.operationHistory.length - 1;
            }

            /**
             * 插入节点
             * @param {Node} node - 要插入的节点
             * @param {Node} referenceNode - 参考节点
             * @param {boolean} before - 是否插入到参考节点之前（默认 false，插入之后）
             */
            insertNode(node, referenceNode, before = false) {
                this.execute(() => {
                    const parent = referenceNode.parentNode;
                    if (!parent) {
                        log.warn(LOG_MODULES.DOM_WRITER, '参考节点没有父节点，无法插入');
                        return;
                    }
                    
                    if (before) {
                        parent.insertBefore(node, referenceNode);
                    } else {
                        if (referenceNode.nextSibling) {
                            parent.insertBefore(node, referenceNode.nextSibling);
                        } else {
                            parent.appendChild(node);
                        }
                    }
                });
            }

            /**
             * 移除节点
             * @param {Node} node - 要移除的节点
             */
            removeNode(node) {
                this.execute(() => {
                    if (node.parentNode) {
                        node.parentNode.removeChild(node);
                    }
                });
            }

            /**
             * 替换节点
             * @param {Node} oldNode - 旧节点
             * @param {Node} newNode - 新节点
             */
            replaceNode(oldNode, newNode) {
                this.execute(() => {
                    if (oldNode.parentNode) {
                        oldNode.parentNode.replaceChild(newNode, oldNode);
                    }
                });
            }

            /**
             * 设置元素属性
             * @param {Element} element - 元素
             * @param {string} name - 属性名
             * @param {string} value - 属性值
             */
            setAttribute(element, name, value) {
                this.execute(() => {
                    element.setAttribute(name, value);
                }, false); // 属性变化不需要立即同步状态
            }

            /**
             * 移除元素属性
             * @param {Element} element - 元素
             * @param {string} name - 属性名
             */
            removeAttribute(element, name) {
                this.execute(() => {
                    element.removeAttribute(name);
                }, false);
            }

            /**
             * 设置元素类名
             * @param {Element} element - 元素
             * @param {string} className - 类名
             * @param {boolean} add - true 添加，false 移除
             */
            setClass(element, className, add) {
                this.execute(() => {
                    if (add) {
                        element.classList.add(className);
                    } else {
                        element.classList.remove(className);
                    }
                });
            }

            /**
             * 设置元素样式
             * @param {Element} element - 元素
             * @param {string} property - 样式属性
             * @param {string} value - 样式值
             */
            setStyle(element, property, value) {
                this.execute(() => {
                    element.style[property] = value;
                }, false);
            }

            /**
             * 设置元素内容
             * @param {Element} element - 元素
             * @param {string} content - 内容（HTML 字符串）
             */
            setContent(element, content) {
                this.execute(() => {
                    element.innerHTML = content;
                });
            }

            /**
             * 增量更新 DOM（只更新变化的部分）
             * 参考 CKEditor 5 的增量更新机制
             * @param {string} newHtml - 新的 HTML 内容
             * @param {string} oldHtml - 旧的 HTML 内容（可选，如果不提供则使用当前内容）
             * @returns {boolean} 是否成功更新
             */
            incrementalUpdate(newHtml, oldHtml = null) {
                if (!oldHtml) {
                    oldHtml = this.editor.innerHTML;
                }

                // 如果内容完全相同，不需要更新
                if (oldHtml === newHtml) {
                    return false;
                }

                // 简单的增量更新策略：
                // 1. 如果内容差异很大（超过 50%），完全重新加载
                // 2. 否则，尝试只更新变化的部分

                const oldLength = oldHtml.length;
                const newLength = newHtml.length;
                const lengthDiff = Math.abs(newLength - oldLength) / Math.max(oldLength, newLength, 1);

                // 如果差异超过 50%，完全重新加载
                if (lengthDiff > 0.5) {
                    this.execute(() => {
                        this.editor.innerHTML = newHtml;
                    }, true, null); // 不记录历史（因为是外部加载）
                    return true;
                }

                // 尝试增量更新：比较新旧内容的差异
                // 简化策略：如果内容结构相似，尝试保留光标位置附近的节点
                try {
                    // 创建临时容器来解析新 HTML
                    const tempDiv = document.createElement('div');
                    tempDiv.innerHTML = newHtml;

                    // 比较子节点数量
                    const oldChildren = Array.from(this.editor.children);
                    const newChildren = Array.from(tempDiv.children);

                    // 如果子节点数量相同，尝试逐个更新
                    if (oldChildren.length === newChildren.length) {
                        let hasChanges = false;
                        this.beginBatch();

                        for (let i = 0; i < oldChildren.length; i++) {
                            const oldChild = oldChildren[i];
                            const newChild = newChildren[i];

                            // 比较节点的 outerHTML
                            if (oldChild.outerHTML !== newChild.outerHTML) {
                                // 节点不同，替换它
                                this.replaceNode(oldChild, newChild.cloneNode(true));
                                hasChanges = true;
                            }
                        }

                        this.endBatch(null); // 不记录历史

                        if (hasChanges) {
                            return true;
                        }
                    }

                    // 如果增量更新失败，回退到完全重新加载
                    this.execute(() => {
                        this.editor.innerHTML = newHtml;
                    }, true, null); // 不记录历史
                    return true;
                } catch (e) {
                    log.warn(LOG_MODULES.DOM_WRITER, '增量更新失败，回退到完全重新加载', { error: e.message });
                    // 回退到完全重新加载
                    this.execute(() => {
                        this.editor.innerHTML = newHtml;
                    }, true, null); // 不记录历史
                    return true;
                }
            }

            /**
             * 设置光标位置
             * @param {Node} node - 节点
             * @param {number} offset - 偏移量
             */
            setSelection(node, offset) {
                this.execute(() => {
                    const selection = window.getSelection();
                    const range = document.createRange();
                    range.setStart(node, offset);
                    range.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(range);
                }, false); // 设置光标不需要同步状态
            }
        }
    
    // 导出到全局命名空间
    window.MiNoteEditor = window.MiNoteEditor || {};
    window.MiNoteEditor.DOMWriter = DOMWriter;
    
    // 向后兼容：直接暴露到全局
    window.DOMWriter = DOMWriter;
    
})();
