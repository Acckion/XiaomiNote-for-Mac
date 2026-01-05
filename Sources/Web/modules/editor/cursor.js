/**
 * Cursor 模块
 * 提供光标位置保存和恢复功能
 * 依赖: logger, dom-writer
 */

(function () {
  "use strict";

  // 获取依赖
  const log = window.log || console;
  const LOG_MODULES = window.LOG_MODULES || { CURSOR: "Cursor" };

  /**
   * 保存光标位置
   * 参考 CKEditor 5 的光标管理机制
   * 优先使用新的光标管理模块，保持向后兼容
   * @returns {Object|null} 保存的光标位置信息
   */
  function saveCursorPosition() {
    const editor = document.getElementById("editor-content");
    if (!editor) {
      return null;
    }

    // 优先使用新的光标管理模块
    if (window.MiNoteEditor && window.MiNoteEditor.CursorModule) {
      const position = window.MiNoteEditor.CursorModule.savePosition(editor);
      if (position) {
        // 将新的 Position 对象转换为兼容格式
        return {
          // 新模块的 Position 数据
          positionData: position,
          // 向后兼容的字段
          startAnchorText: position.anchorText || "",
          startAnchorOffset: position.anchorOffset || 0,
          endAnchorText: position.focusText || "",
          endAnchorOffset: position.focusOffset || 0,
          collapsed: position.collapsed || true,
          // 标记为新格式
          _isNewFormat: true
        };
      }
    }

    // 回退到原有的实现
    const selection = window.getSelection();
    if (!selection || !selection.rangeCount) {
      return null;
    }

    const range = selection.getRangeAt(0);
    if (!editor.contains(range.commonAncestorContainer)) {
      return null;
    }

    try {
      // 方法1：保存文本锚点（最可靠的方法，参考 CKEditor 5 的文本位置标记）
      // 在光标前后保存一些文本内容作为锚点，用于恢复时定位
      const startNode = range.startContainer;
      const endNode = range.endContainer;

      // 获取光标前后的文本内容作为锚点
      let startAnchorText = "";
      let endAnchorText = "";
      let startAnchorOffset = 0;
      let endAnchorOffset = 0;

      if (startNode.nodeType === Node.TEXT_NODE) {
        const text = startNode.textContent || "";
        const offset = range.startOffset;
        // 保存光标前 20 个字符和后 20 个字符作为锚点
        const beforeText = text.substring(Math.max(0, offset - 20), offset);
        const afterText = text.substring(offset, Math.min(text.length, offset + 20));
        startAnchorText = beforeText + "|" + afterText; // 使用 | 标记光标位置
        startAnchorOffset = beforeText.length;
      } else {
        // 如果不是文本节点，尝试获取父文本节点
        const textNode = findTextNode(startNode, range.startOffset);
        if (textNode) {
          const text = textNode.textContent || "";
          const offset = textNode === startNode ? range.startOffset : 0;
          const beforeText = text.substring(Math.max(0, offset - 20), offset);
          const afterText = text.substring(offset, Math.min(text.length, offset + 20));
          startAnchorText = beforeText + "|" + afterText;
          startAnchorOffset = beforeText.length;
        }
      }

      if (endNode.nodeType === Node.TEXT_NODE) {
        const text = endNode.textContent || "";
        const offset = range.endOffset;
        const beforeText = text.substring(Math.max(0, offset - 20), offset);
        const afterText = text.substring(offset, Math.min(text.length, offset + 20));
        endAnchorText = beforeText + "|" + afterText;
        endAnchorOffset = beforeText.length;
      } else {
        const textNode = findTextNode(endNode, range.endOffset);
        if (textNode) {
          const text = textNode.textContent || "";
          const offset = textNode === endNode ? range.endOffset : 0;
          const beforeText = text.substring(Math.max(0, offset - 20), offset);
          const afterText = text.substring(offset, Math.min(text.length, offset + 20));
          endAnchorText = beforeText + "|" + afterText;
          endAnchorOffset = beforeText.length;
        }
      }

      // 方法2：保存路径信息（作为备用）
      const startPath = getNodePath(range.startContainer, editor);
      const endPath = getNodePath(range.endContainer, editor);

      return {
        // 文本锚点（主要方法）
        startAnchorText: startAnchorText,
        startAnchorOffset: startAnchorOffset,
        endAnchorText: endAnchorText,
        endAnchorOffset: endAnchorOffset,
        // 路径信息（备用方法）
        startPath: startPath,
        startOffset: range.startOffset,
        endPath: endPath,
        endOffset: range.endOffset,
        collapsed: range.collapsed,
        // 原始节点引用（如果 DOM 没变可以直接使用）
        startContainer: range.startContainer,
        endContainer: range.endContainer
      };
    } catch (e) {
      log.warn(LOG_MODULES.CURSOR, "保存光标位置失败", { error: e.message });
      return null;
    }
  }

  /**
   * 恢复光标位置（参考 CKEditor 5 的光标管理）
   * 优先使用新的光标管理模块，保持向后兼容
   * @param {Object} savedPosition - 保存的光标位置信息
   */
  function restoreCursorPosition(savedPosition) {
    if (!savedPosition) {
      return;
    }

    const editor = document.getElementById("editor-content");
    if (!editor) {
      return;
    }

    // 优先使用新的光标管理模块
    if (window.MiNoteEditor && window.MiNoteEditor.CursorModule) {
      // 检查是否是新格式
      if (savedPosition._isNewFormat && savedPosition.positionData) {
        const restored = window.MiNoteEditor.CursorModule.restorePosition(editor, savedPosition.positionData);
        if (restored) {
          return;
        }
      }
    }

    // 回退到原有的实现
    const selection = window.getSelection();
    if (!selection) {
      return;
    }

    try {
      // 方法1：使用文本锚点恢复（最可靠，即使 DOM 结构变化也能恢复）
      if (savedPosition.startAnchorText) {
        const anchorText = savedPosition.startAnchorText;
        const parts = anchorText.split("|");
        if (parts.length === 2) {
          const beforeText = parts[0];
          const afterText = parts[1];

          // 在整个编辑器中搜索匹配的文本
          const editorText = editor.textContent || editor.innerText || "";
          const searchText = beforeText + afterText;
          const index = editorText.indexOf(searchText);

          if (index !== -1) {
            // 找到匹配的文本，计算光标位置
            const targetOffset = index + beforeText.length;

            // 找到对应的文本节点和偏移量
            const walker = document.createTreeWalker(
              editor,
              NodeFilter.SHOW_TEXT,
              null
            );

            let currentOffset = 0;
            let targetNode = null;
            let targetNodeOffset = 0;

            let node = walker.nextNode();
            while (node) {
              const nodeLength = node.textContent.length;
              if (currentOffset + nodeLength >= targetOffset) {
                targetNode = node;
                targetNodeOffset = targetOffset - currentOffset;
                break;
              }
              currentOffset += nodeLength;
              node = walker.nextNode();
            }

            if (targetNode) {
              const range = document.createRange();
              range.setStart(
                targetNode,
                Math.min(targetNodeOffset, targetNode.textContent.length)
              );
              range.collapse(true);
              selection.removeAllRanges();
              selection.addRange(range);
              return;
            }
          }
        }
      }

      // 方法2：使用路径恢复（如果 DOM 结构没变）
      if (savedPosition.startPath && savedPosition.endPath) {
        const startNode = getNodeByPath(savedPosition.startPath, editor);
        const endNode = getNodeByPath(savedPosition.endPath, editor);

        if (startNode && endNode) {
          try {
            const range = document.createRange();
            const startOffset = Math.min(
              savedPosition.startOffset || 0,
              startNode.nodeType === Node.TEXT_NODE
                ? startNode.textContent.length
                : 0
            );
            const endOffset = Math.min(
              savedPosition.endOffset || 0,
              endNode.nodeType === Node.TEXT_NODE
                ? endNode.textContent.length
                : 0
            );

            range.setStart(startNode, startOffset);
            range.setEnd(endNode, endOffset);

            selection.removeAllRanges();
            selection.addRange(range);
            return;
          } catch (e) {
            // 路径恢复失败，继续尝试其他方法
          }
        }
      }

      // 方法3：使用保存的容器恢复（如果 DOM 结构完全没变）
      if (savedPosition.startContainer && savedPosition.endContainer) {
        try {
          const range = document.createRange();
          const startOffset = Math.min(
            savedPosition.startOffset || 0,
            savedPosition.startContainer.nodeType === Node.TEXT_NODE
              ? savedPosition.startContainer.textContent.length
              : 0
          );
          const endOffset = Math.min(
            savedPosition.endOffset || 0,
            savedPosition.endContainer.nodeType === Node.TEXT_NODE
              ? savedPosition.endContainer.textContent.length
              : 0
          );

          range.setStart(savedPosition.startContainer, startOffset);
          range.setEnd(savedPosition.endContainer, endOffset);

          selection.removeAllRanges();
          selection.addRange(range);
          return;
        } catch (e) {
          // 节点已不存在，继续尝试其他方法
        }
      }

      // 方法4：回退到文档末尾（避免光标跳到开头）
      const walker = document.createTreeWalker(
        editor,
        NodeFilter.SHOW_TEXT,
        null
      );
      let lastTextNode = null;
      let textNode = walker.nextNode();
      while (textNode) {
        lastTextNode = textNode;
        textNode = walker.nextNode();
      }
      if (lastTextNode) {
        const range = document.createRange();
        const offset = Math.min(
          savedPosition.startOffset || 0,
          lastTextNode.textContent.length
        );
        range.setStart(lastTextNode, offset);
        range.collapse(true);
        selection.removeAllRanges();
        selection.addRange(range);
      }
    } catch (e) {
      log.warn(LOG_MODULES.CURSOR, "恢复光标位置失败", { error: e.message });
      // 最后的回退：将光标放到文档末尾
      try {
        const range = document.createRange();
        range.selectNodeContents(editor);
        range.collapse(false);
        selection.removeAllRanges();
        selection.addRange(range);
      } catch (e2) {
        log.error(LOG_MODULES.CURSOR, "回退光标位置也失败", {
          error: e2.message,
        });
      }
    }
  }

  /**
   * 查找文本节点（用于光标位置保存）
   * @param {Node} node - 起始节点
   * @param {number} offset - 偏移量
   * @returns {Node|null} 文本节点
   */
  function findTextNode(node, offset) {
    if (node.nodeType === Node.TEXT_NODE) {
      return node;
    }

    // 如果是元素节点，根据偏移量查找子节点
    if (node.nodeType === Node.ELEMENT_NODE && node.childNodes.length > 0) {
      if (offset < node.childNodes.length) {
        const child = node.childNodes[offset];
        if (child.nodeType === Node.TEXT_NODE) {
          return child;
        }
        // 递归查找
        return findTextNode(child, 0);
      }
    }

    return null;
  }

  /**
   * 获取节点在编辑器中的路径（用于恢复光标位置）
   * 参考 CKEditor 5 的路径保存机制
   * @param {Node} node - 节点
   * @param {HTMLElement} root - 根元素
   * @returns {Array|null} 节点路径
   */
  function getNodePath(node, root) {
    const path = [];
    let current = node;

    while (current && current !== root && current !== document.body) {
      // 计算当前节点在父节点中的索引
      let index = 0;
      let sibling = current;
      while (sibling.previousSibling) {
        sibling = sibling.previousSibling;
        index++;
      }
      path.unshift(index);
      current = current.parentNode;
    }

    return path.length > 0 ? path : null;
  }

  /**
   * 根据路径获取节点（参考 CKEditor 5 的路径恢复机制）
   * @param {Array} path - 节点路径
   * @param {HTMLElement} root - 根元素
   * @returns {Node|null} 节点
   */
  function getNodeByPath(path, root) {
    let current = root;

    for (let i = 0; i < path.length; i++) {
      const index = path[i];

      if (
        !current ||
        !current.childNodes ||
        index >= current.childNodes.length
      ) {
        return null;
      }

      current = current.childNodes[index];
    }

    return current;
  }

  // 导出到全局命名空间
  window.MiNoteEditor = window.MiNoteEditor || {};
  window.MiNoteEditor.Cursor = {
    saveCursorPosition: saveCursorPosition,
    restoreCursorPosition: restoreCursorPosition,
    findTextNode: findTextNode,
    getNodePath: getNodePath,
    getNodeByPath: getNodeByPath,
  };

  // 向后兼容：暴露到 window.MiNoteWebEditor（将在 editor-api.js 中设置）
  // 这里先设置，以便 DOMWriter 可以使用
  if (!window.MiNoteWebEditor) {
    window.MiNoteWebEditor = {};
  }
  window.MiNoteWebEditor._saveCursorPosition = saveCursorPosition;
  window.MiNoteWebEditor._restoreCursorPosition = restoreCursorPosition;
})();
