# 短期功能
1. 搜索框实现Mac备忘录样式
    1.1 使用SwiftUI标准 ✅
    1.2 笔记编辑视图中搜索结果匹配的高亮
    1.3 修复：高亮不完全

3. 优化设置页面

4. 优化重命名文件夹、新建文件夹弹窗
    4.1 重命名 ✅
    4.2 新建 ✅
    4.3 修复：新建文件夹时不会选中的问题 
    4.4 修复：输入名称冲突提示窗选择“好”没有修改机会 ✅

5. 尝试静默刷新cookie ✅ 
    5.1 偶现显示刷新成功但实际失败
    5.2 添加自动刷新按钮

6. 私密笔记验证修复
    6.1 优化验证界面
    6.2 进一步提升安全性 ✅
    6.3 修复正文显示 ✅

7. 添加全部笔记和搜索结果的笔记列表文件夹显示 ✅
8. 修复默认笔记打开页面 ✅
9. 支持调整文字大小、行距等显示效果
10. 优化深色模式的闪动
11. 切换文件夹时编辑视图跟随
12. 修复文件夹删除（离线删除失败，无效的文件夹数据）
13. 修复笔记列表内容预览和图片预览不刷新的问题
14. 添加主题色设置
15. 修复笔记缺少一行
16. 排序选项问题修复

# 长期功能
1. 思维笔记解析和显示
2. 端到端加密支持
3. 代办事项支持
4. 自定义工具栏


# API接口记录
## 获取代办
请求 URL: https://i.mi.com/todo/v1/user/records/0?ts=1766599238280
请求方法: GET
状态代码: 200 OK
远程地址: 127.0.0.1:7897
引用站点策略: strict-origin-when-cross-origin
content-encoding: gzip
content-type: application/json
date: Wed, 24 Dec 2025 18:00:38 GMT
server: Tengine
:authority i.mi.com
:method GET
:path /todo/v1/user/records/0?ts=1766599238280
:scheme https
accept: */*
accept-encoding: gzip, deflate, br, zstd
accept-language: zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7
cookie: Hm_lvt_21cf8e00109c51ddc329127cade0bc77=1747382684......
dnt: 1
priority: u=1, i
referer: https://i.mi.com/note/h5
sec-ch-ua: "Microsoft Edge";v="143", "Chromium";v="143", "Not A(Brand";v="24"
sec-ch-ua-mobile: ?0
sec-ch-ua-platform: "macOS"
sec-fetch-dest: empty
sec-fetch-mode: cors
sec-fetch-site: same-origin
user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0

响应：
{
    "result": "ok",
    "retriable": false,
    "code": 0,
    "data": {
        "record": {
            "contentJson": {
                "folder": {
                    "syncId": 0
                },
                "sort": {
                    "eTag": "12697100320243872",
                    "orders": [
                        "11361199335997537",
                        "12209401093881920",
                        "12134475657380064",
                        "12195560091287744",
                        "11136039787626560"
                    ]
                }
            },
            "eTag": 0,
            "id": 0,
            "type": "folder",
            "status": "normal"
        },
        "purged": false,
        "existed": true
    },
    "description": "成功",
    "ts": 1766599238389
}