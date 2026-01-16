# 小米云相册 API 文档

基于 `https://i.mi.com/gallery/h5#/photo` 页面抓包分析。

## 基础信息

- 基础 URL：`https://i.mi.com`
- 认证方式：Cookie（serviceToken）
- 响应格式：JSON
- 加密：端到端加密（E2EE），需要 `record_key` 和 `record_iv` 解密

## API 列表

### 1. 服务准备检查

```
POST /gallery/user/lite/index/prepare
Content-Type: application/x-www-form-urlencoded

serviceToken=<encoded_token>
```

响应：
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "isReady": true,
    "status": "ready"
  }
}
```

### 2. 获取加密信息

```
GET /mic/keybag/v1/getEncInfo?hsid=2&appId=micloud&ts={timestamp}
```

响应：
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "zone": 301,
    "e2eeStatus": "close",
    "nonce": "..."
  }
}
```

### 3. 获取相册列表

```
GET /gallery/user/album/list?ts={timestamp}&pageNum={page}&pageSize={size}&isShared={bool}&numOfThumbnails={num}
```

参数：
| 参数 | 类型 | 说明 |
|------|------|------|
| pageNum | int | 分页页码，从 0 开始 |
| pageSize | int | 每页数量，默认 20 |
| isShared | bool | 是否共享相册 |
| numOfThumbnails | int | 返回的缩略图数量 |

响应：
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "albums": [
      {
        "albumId": "1",
        "name": "相册名称",
        "mediaCount": 4320,
        "userId": 1315204657,
        "lastUpdateTime": 1768292123670,
        "thumbnails": [
          {
            "orientation": 1,
            "url": "https://..."
          }
        ]
      }
    ],
    "isLastPage": false,
    "indexHash": 1054389279
  }
}
```

特殊相册 ID：
- `1`：相机胶卷（所有照片）
- `2`：截图
- `1000`：回收站

### 4. 获取视频相册

```
GET /gallery/user/album/video?ts={timestamp}&isShared=false
```

响应结构与相册列表类似。

### 5. 获取时间线（按日期统计）

```
GET /gallery/user/timeline?ts={timestamp}
```

响应：
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "dayCount": {
      "20251022": 2,
      "20251021": 7,
      "20251020": 3
    },
    "indexHash": 1054389279
  }
}
```

日期格式：`YYYYMMDD`

### 6. 获取图片列表（核心 API）⭐

```
GET /gallery/user/galleries?ts={timestamp}&startDate={date}&endDate={date}&pageNum={page}&pageSize={size}
```

参数：
| 参数 | 类型 | 说明 |
|------|------|------|
| startDate | string | 开始日期，格式 YYYYMMDD |
| endDate | string | 结束日期，格式 YYYYMMDD |
| pageNum | int | 分页页码，从 0 开始 |
| pageSize | int | 每页数量，默认 30 |

响应：
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "isLastPage": true,
    "indexHash": 1054389279,
    "galleries": [
      {
        "id": "24886749771271584",
        "fileName": "IMG_20251022_150620.jpg",
        "title": "IMG_20251022_150620",
        "mimeType": "image/jpeg",
        "type": "image",
        "size": 387063,
        "sha1": "62b6b2fc399d30f64f40f00abf7903a2773dcf46",
        "dateTaken": 1761116780000,
        "sortTime": 1761116780000,
        "createTime": 1761116848906,
        "dateModified": 1761116788992,
        "groupId": 2,
        "isFavorite": false,
        "isLivePhoto": false,
        "isFrontCamera": false,
        "exifInfo": {
          "imageWidth": 960,
          "imageLength": 2086,
          "orientation": 0,
          "whiteBalance": 0
        },
        "thumbStatus": {
          "smallStatus": "custom",
          "largeStatus": "custom",
          "smallSizeInfo": { "width": 270, "height": 586 },
          "largeSizeInfo": { "width": 960, "height": 2086 }
        },
        "thumbnailInfo": {
          "data": "https://...",
          "isUrl": true
        },
        "bigThumbnailInfo": {
          "data": "https://...",
          "isUrl": true
        }
      }
    ]
  }
}
```

## 缩略图 URL 结构

```
https://{cdn}.xmssdn.micloud.mi.com/2/{userId}/get_thumbnail?data={encrypted}&w={width}&h={height}&ts={timestamp}&r=0&_cachekey={hash}&type={type}&record_key={key}&record_iv={iv}&sig={signature}
```

参数说明：
| 参数 | 说明 |
|------|------|
| data | 加密的图片数据标识 |
| w, h | 缩略图尺寸 |
| type | 0=小图, 2=大图 |
| record_key | E2EE 解密密钥 |
| record_iv | E2EE 初始化向量 |
| sig | 请求签名 |

CDN 域名：
- `ali.xmssdn.micloud.mi.com`
- `tos.xmssdn.micloud.mi.com`
- `kssh2thumb.xmssdn.micloud.mi.com`

## 典型调用流程

```
1. POST /gallery/user/lite/index/prepare
   └── 检查服务就绪状态

2. GET /gallery/user/timeline
   └── 获取有图片的日期列表

3. GET /gallery/user/album/list
   └── 获取相册列表（可选）

4. GET /gallery/user/galleries?startDate=20251022&endDate=20251022
   └── 根据日期获取图片列表

5. 使用 thumbnailInfo.data 或 bigThumbnailInfo.data 加载图片
```

## 其他辅助 API

### 用户信息
```
GET /status/lite/profile?ts={timestamp}
```

### VIP 等级
```
GET /status/vip/level?ts={timestamp}
```

### 存储空间详情
```
GET /status/lite/alldetail?ts={timestamp}
```

响应包含各类数据占用空间：
- `GalleryImage`：相册图片
- `Recorder`：录音备份
- `Creation`：创作内容
- `AppList`：桌面图标布局

## 注意事项

1. 所有请求需要携带有效的 Cookie（包含 serviceToken）
2. 图片可能启用端到端加密，需要使用 `record_key` 和 `record_iv` 解密
3. `ts` 参数为当前时间戳（毫秒）
4. 分页从 0 开始
5. `indexHash` 用于检测数据是否有更新
