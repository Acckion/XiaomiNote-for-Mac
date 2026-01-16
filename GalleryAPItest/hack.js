// ==UserScript==
// @name         通用网络请求监听器
// @namespace    http://tampermonkey.net/
// @version      0.8
// @description  捕获所有页面的网络请求（Fetch/XHR）
// @author       You
// @match        *://*/*
// @grant        unsafeWindow
// @run-at       document-start
// @inject-into  page
// ==/UserScript==

(function() {
    'use strict';

    const CONFIG = {
        MAX_ENTRIES: 500,
        MAX_BODY_LENGTH: 2 * 1024 * 1024
    };

    const win = typeof unsafeWindow !== 'undefined' ? unsafeWindow : window;
    
    if (!win.__capturedRequests) {
        win.__capturedRequests = [];
    }
    const capturedRequests = win.__capturedRequests;

    function safeStringify(obj, maxLen) {
        try {
            const str = typeof obj === 'string' ? obj : JSON.stringify(obj);
            return str && str.length > maxLen ? str.substring(0, maxLen) + '...[截断]' : str;
        } catch (e) {
            return String(obj);
        }
    }

    function extractHeaders(headers) {
        if (!headers) return null;
        try {
            if (typeof headers.entries === 'function') {
                return Object.fromEntries(headers.entries());
            }
            const result = {};
            if (typeof headers.forEach === 'function') {
                headers.forEach((v, k) => result[k] = v);
            } else {
                for (const k in headers) result[k] = headers[k];
            }
            return Object.keys(result).length ? result : null;
        } catch (e) { return null; }
    }

    function addRequest(info) {
        capturedRequests.push(info);
        if (capturedRequests.length > CONFIG.MAX_ENTRIES) {
            capturedRequests.shift();
        }
        updateUI();
    }

    // ==================== 注入拦截代码到页面 ====================
    const interceptorCode = `
    (function() {
        if (window.__fetchIntercepted) return;
        window.__fetchIntercepted = true;
        
        const MAX_BODY = ${CONFIG.MAX_BODY_LENGTH};
        
        function safeStr(obj, max) {
            try {
                const s = typeof obj === 'string' ? obj : JSON.stringify(obj);
                return s && s.length > max ? s.substring(0, max) + '...[截断]' : s;
            } catch(e) { return String(obj); }
        }
        
        function getHeaders(h) {
            if (!h) return null;
            try {
                if (typeof h.entries === 'function') return Object.fromEntries(h.entries());
                const r = {};
                if (typeof h.forEach === 'function') h.forEach((v,k) => r[k] = v);
                else for (const k in h) r[k] = h[k];
                return Object.keys(r).length ? r : null;
            } catch(e) { return null; }
        }
        
        function addReq(info) {
            if (!window.__capturedRequests) window.__capturedRequests = [];
            window.__capturedRequests.push(info);
            if (window.__capturedRequests.length > 500) window.__capturedRequests.shift();
            if (window.__updateCaptureUI) window.__updateCaptureUI();
        }
        
        // 拦截 fetch
        const _fetch = window.fetch;
        window.fetch = function(input, init) {
            const start = Date.now();
            const url = typeof input === 'string' ? input : (input?.url || String(input));
            const method = ((init?.method) || (input?.method) || 'GET').toUpperCase();
            
            const info = {
                id: start.toString(36) + Math.random().toString(36).substr(2,6),
                type: 'fetch',
                method: method,
                url: url,
                timestamp: new Date().toISOString(),
                request: { headers: null, body: null },
                response: { status: null, headers: null, body: null },
                duration: null
            };
            
            try {
                if (init?.headers) info.request.headers = getHeaders(new Headers(init.headers));
                else if (input?.headers) info.request.headers = getHeaders(input.headers);
            } catch(e) {}
            
            try {
                if (init?.body) info.request.body = safeStr(init.body, MAX_BODY);
            } catch(e) {}
            
            return _fetch.apply(this, arguments).then(function(resp) {
                info.duration = (Date.now() - start) + 'ms';
                info.response.status = resp.status;
                info.response.statusText = resp.statusText;
                try { info.response.headers = getHeaders(resp.headers); } catch(e) {}
                
                const clone = resp.clone();
                clone.text().then(function(text) {
                    try { info.response.body = JSON.parse(text); }
                    catch { info.response.body = safeStr(text, MAX_BODY); }
                    addReq(info);
                }).catch(function() { addReq(info); });
                
                return resp;
            }).catch(function(err) {
                info.duration = (Date.now() - start) + 'ms';
                info.error = { message: err.message };
                addReq(info);
                throw err;
            });
        };
        
        // 拦截 XMLHttpRequest
        const _open = XMLHttpRequest.prototype.open;
        const _send = XMLHttpRequest.prototype.send;
        const _setHeader = XMLHttpRequest.prototype.setRequestHeader;
        
        XMLHttpRequest.prototype.open = function(method, url) {
            this.__info = {
                id: Date.now().toString(36) + Math.random().toString(36).substr(2,6),
                type: 'xhr',
                method: method.toUpperCase(),
                url: url,
                timestamp: new Date().toISOString(),
                start: Date.now(),
                request: { headers: {}, body: null },
                response: { status: null, headers: null, body: null },
                duration: null
            };
            return _open.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
            if (this.__info) this.__info.request.headers[name] = value;
            return _setHeader.apply(this, arguments);
        };
        
        XMLHttpRequest.prototype.send = function(body) {
            const xhr = this;
            if (xhr.__info && body) {
                xhr.__info.request.body = safeStr(body, MAX_BODY);
            }
            
            xhr.addEventListener('loadend', function() {
                if (!xhr.__info) return;
                const info = xhr.__info;
                info.duration = (Date.now() - info.start) + 'ms';
                delete info.start;
                info.response.status = xhr.status;
                info.response.statusText = xhr.statusText;
                
                try {
                    const h = xhr.getAllResponseHeaders();
                    if (h) {
                        const headers = {};
                        h.trim().split('\\r\\n').forEach(function(line) {
                            const i = line.indexOf(':');
                            if (i > 0) headers[line.substring(0,i).trim()] = line.substring(i+1).trim();
                        });
                        info.response.headers = headers;
                    }
                } catch(e) {}
                
                try {
                    const text = xhr.responseText;
                    try { info.response.body = JSON.parse(text); }
                    catch { info.response.body = safeStr(text, MAX_BODY); }
                } catch(e) {}
                
                addReq(info);
            });
            
            return _send.apply(this, arguments);
        };
        
        console.log('[拦截器] fetch/XHR 已注入');
    })();
    `;

    function injectScript(code) {
        const script = document.createElement('script');
        script.textContent = code;
        (document.head || document.documentElement).appendChild(script);
        script.remove();
    }

    injectScript(interceptorCode);

    // ==================== PerformanceObserver 备用 ====================
    try {
        const observer = new PerformanceObserver((list) => {
            list.getEntries().forEach(entry => {
                if (entry.initiatorType === 'fetch' || entry.initiatorType === 'xmlhttprequest') {
                    const exists = capturedRequests.some(r => 
                        r.url === entry.name && r.type !== 'perf-fetch' && r.type !== 'perf-xhr'
                    );
                    if (!exists) {
                        addRequest({
                            id: Date.now().toString(36) + Math.random().toString(36).substr(2,6),
                            type: 'perf-' + entry.initiatorType,
                            method: '?',
                            url: entry.name,
                            timestamp: new Date().toISOString(),
                            request: { headers: null, body: '[Performance API]' },
                            response: { status: null, headers: null, body: '[Performance API]' },
                            duration: entry.duration.toFixed(0) + 'ms',
                            timing: {
                                transferSize: entry.transferSize,
                                encodedBodySize: entry.encodedBodySize,
                                decodedBodySize: entry.decodedBodySize
                            },
                            _fallback: true
                        });
                    }
                }
            });
        });
        observer.observe({ entryTypes: ['resource'] });
    } catch (e) {}

    // ==================== UI ====================
    let panel = null;
    let countSpan = null;
    let filterInput = null;

    function updateUI() {
        if (countSpan) countSpan.textContent = capturedRequests.length;
    }
    
    win.__updateCaptureUI = updateUI;

    function createUI() {
        if (panel || document.getElementById('net-capture-panel')) return;

        panel = document.createElement('div');
        panel.id = 'net-capture-panel';
        Object.assign(panel.style, {
            position: 'fixed', bottom: '20px', right: '20px', zIndex: '2147483647',
            backgroundColor: 'rgba(30,30,30,0.95)', border: '1px solid #555',
            borderRadius: '8px', padding: '12px 16px', minWidth: '280px', maxWidth: '350px',
            fontFamily: '-apple-system, sans-serif', fontSize: '13px', color: '#eee',
            boxShadow: '0 4px 20px rgba(0,0,0,0.5)'
        });

        panel.innerHTML = `
            <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
                <span style="font-weight:600;">🔍 网络监听 v0.8</span>
                <div>
                    <span id="minimize-btn" style="cursor:pointer;font-size:14px;color:#888;margin-right:8px;">−</span>
                    <span id="close-btn" style="cursor:pointer;font-size:18px;color:#888;">×</span>
                </div>
            </div>
            <div id="panel-content">
                <div style="margin-bottom:8px;font-size:12px;color:#aaa;">
                    当前页面: <span style="color:#4CAF50;">${location.hostname}</span>
                </div>
                <div style="margin-bottom:10px;font-size:12px;color:#aaa;">
                    已捕获: <span id="cap-count" style="color:#4CAF50;font-weight:bold;">0</span> 条
                    (<span id="fetch-count">0</span> fetch, <span id="xhr-count">0</span> xhr)
                </div>
                <input id="filter-input" type="text" placeholder="过滤 URL..." style="width:100%;padding:6px 8px;border:1px solid #444;border-radius:4px;background:#222;color:#eee;font-size:12px;margin-bottom:10px;box-sizing:border-box;">
                <div style="display:flex;gap:6px;flex-wrap:wrap;">
                    <button id="dl-btn" style="flex:1;min-width:60px;padding:6px;border:none;border-radius:4px;background:#4CAF50;color:#fff;cursor:pointer;font-size:11px;">📥 下载</button>
                    <button id="dl-filter-btn" style="flex:1;min-width:60px;padding:6px;border:none;border-radius:4px;background:#FF9800;color:#fff;cursor:pointer;font-size:11px;">� 过滤</button>
                    <button id="clr-btn" style="flex:1;min-width:60px;padding:6px;border:none;border-radius:4px;background:#f44336;color:#fff;cursor:pointer;font-size:11px;">�️ 清除</button>
                    <button id="view-btn" style="flex:1;min-width:60px;padding:6px;border:none;border-radius:4px;background:#2196F3;color:#fff;cursor:pointer;font-size:11px;">📋 控制台</button>
                </div>
            </div>
        `;

        document.body.appendChild(panel);
        countSpan = panel.querySelector('#cap-count');
        filterInput = panel.querySelector('#filter-input');
        
        const content = panel.querySelector('#panel-content');
        let minimized = false;
        
        const updateCounts = () => {
            const fetchCount = capturedRequests.filter(r => r.type === 'fetch').length;
            const xhrCount = capturedRequests.filter(r => r.type === 'xhr').length;
            panel.querySelector('#fetch-count').textContent = fetchCount;
            panel.querySelector('#xhr-count').textContent = xhrCount;
            countSpan.textContent = capturedRequests.length;
        };
        
        win.__updateCaptureUI = updateCounts;
        updateCounts();
        
        panel.querySelector('#minimize-btn').onclick = () => {
            minimized = !minimized;
            content.style.display = minimized ? 'none' : 'block';
            panel.querySelector('#minimize-btn').textContent = minimized ? '+' : '−';
        };
        
        panel.querySelector('#close-btn').onclick = () => panel.style.display = 'none';
        
        const getFilteredRequests = () => {
            const filter = filterInput.value.toLowerCase().trim();
            if (!filter) return capturedRequests;
            return capturedRequests.filter(r => r.url.toLowerCase().includes(filter));
        };
        
        panel.querySelector('#dl-btn').onclick = () => {
            if (!capturedRequests.length) return alert('没有数据');
            downloadJSON(capturedRequests, 'all');
        };
        
        panel.querySelector('#dl-filter-btn').onclick = () => {
            const filtered = getFilteredRequests();
            if (!filtered.length) return alert('没有匹配的数据');
            downloadJSON(filtered, 'filtered');
        };
        
        panel.querySelector('#clr-btn').onclick = () => {
            if (capturedRequests.length && confirm('确定清除？')) {
                capturedRequests.length = 0;
                updateCounts();
            }
        };
        
        panel.querySelector('#view-btn').onclick = () => {
            const filtered = getFilteredRequests();
            console.group('📡 网络请求 (' + filtered.length + ')');
            console.table(filtered.map(r => ({
                类型: r.type,
                方法: r.method,
                URL: r.url.length > 60 ? r.url.substr(0,60) + '...' : r.url,
                状态: r.response?.status || '-',
                耗时: r.duration
            })));
            console.log('完整数据:', filtered);
            console.groupEnd();
        };
    }
    
    function downloadJSON(data, suffix) {
        const blob = new Blob([JSON.stringify({ 
            exportedAt: new Date().toISOString(),
            page: location.href,
            total: data.length,
            requests: data 
        }, null, 2)], { type: 'application/json' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `requests_${location.hostname}_${suffix}_${Date.now()}.json`;
        a.click();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', createUI);
    } else {
        setTimeout(createUI, 100);
    }

    win.__netCapture = {
        get: () => capturedRequests,
        filter: (keyword) => capturedRequests.filter(r => r.url.includes(keyword)),
        clear: () => { capturedRequests.length = 0; updateUI(); },
        show: () => { if (panel) panel.style.display = 'block'; else createUI(); },
        hide: () => { if (panel) panel.style.display = 'none'; },
        download: (filter) => {
            const data = filter ? capturedRequests.filter(r => r.url.includes(filter)) : capturedRequests;
            downloadJSON(data, filter || 'all');
        }
    };

    console.log('[网络监听器 v0.8] 已加载 - ' + location.hostname);
})();
