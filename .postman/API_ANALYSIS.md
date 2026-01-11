# 小米笔记语音文件 API 分析

## 概述

本文档记录了从实际 API 响应中分析出的语音文件相关 API 信息。

## 1. 获取笔记 API

### 请求

```
GET https://i.mi.com/note/note/{noteId}/?ts={timestamp}
```

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| noteId | string | 笔记 ID，如 `48926433520534752` |
| ts | number | 时间戳（毫秒） |

### 响应示例

```json
{
  "result": "ok",
  "retriable": false,
  "code": 0,
  "data": {
    "entry": {
      "snippet": "<sound fileid=\"1315204657.jgHyouv563iSF_XCE4jhAg\" />\n<text indent=\"1\"></text>",
      "modifyDate": 1768067381113,
      "colorId": 0,
      "subject": "",
      "alertDate": 0,
      "type": "note",
      "folderId": 0,
      "content": "<sound fileid=\"1315204657.jgHyouv563iSF_XCE4jhAg\" />\n<text indent=\"1\"></text>",
      "setting": {
        "data": [
          {
            "digest": "8a41074a7bf788cf921a32a781e7b676f3103968.mp3",
            "mimeType": "audio/mp3",
            "fileId": "1315204657.jgHyouv563iSF_XCE4jhAg"
          }
        ],
        "themeId": 0,
        "stickyTime": 0,
        "version": 0
      },
      "deleteTime": 0,
      "alertTag": 0,
      "id": "48926433520534752",
      "tag": "48926435156968800",
      "createDate": 1768067367974,
      "status": "normal",
      "extraInfo": "{\"note_content_type\":\"common\",\"web_images\":\"\",\"mind_content_plain_text\":\"\",\"title\":\"语音笔记\",\"mind_content\":\"\"}"
    }
  },
  "description": "成功",
  "ts": 1768067395519
}
```

## 2. 语音文件 XML 格式

### Sound 标签格式

```xml
<sound fileid="1315204657.jgHyouv563iSF_XCE4jhAg" />
```

### 属性说明

| 属性 | 类型 | 说明 |
|------|------|------|
| fileid | string | 语音文件唯一标识符 |

### FileId 格式

```
{数字}.{随机字符串}
```

示例：`1315204657.jgHyouv563iSF_XCE4jhAg`

- 前缀数字：可能是用户 ID 或时间戳
- 后缀字符串：Base64 编码的随机标识符

## 3. Setting.data 元数据格式

### 结构

```json
{
  "data": [
    {
      "digest": "8a41074a7bf788cf921a32a781e7b676f3103968.mp3",
      "mimeType": "audio/mp3",
      "fileId": "1315204657.jgHyouv563iSF_XCE4jhAg"
    }
  ]
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| digest | string | 文件摘要，格式为 `{SHA1哈希值}.{扩展名}` |
| mimeType | string | MIME 类型，如 `audio/mp3` |
| fileId | string | 与 sound 标签中的 fileid 对应 |

### Digest 格式

```
{40位SHA1哈希值}.{扩展名}
```

示例：`8a41074a7bf788cf921a32a781e7b676f3103968.mp3`

## 4. 图片上传 API（已确认）

基于你提供的实际请求数据：

### 请求信息

```
POST https://i.mi.com/file/v2/user/request_upload_file
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

### 请求头

| 头部 | 值 |
|------|------|
| Content-Type | application/x-www-form-urlencoded; charset=UTF-8 |
| Cookie | (包含 serviceToken 等认证信息) |
| Origin | https://i.mi.com |
| Referer | https://i.mi.com/note/h5 |

### 请求体（图片上传）

```
data={"type":"note_img","storage":{"filename":"头像.png","size":1049250,"sha1":"2c16413bdd14de8f2f4d2f80791b5101d9bf44fc","mimeType":"image/png","kss":{"block_infos":[{"blob":{},"size":1049250,"md5":"8515cd26bb45daf9fac449323e580f7b","sha1":"2c16413bdd14de8f2f4d2f80791b5101d9bf44fc"}]}}}&serviceToken=...
```

### data 参数结构（图片）

```json
{
  "type": "note_img",
  "storage": {
    "filename": "头像.png",
    "size": 1049250,
    "sha1": "2c16413bdd14de8f2f4d2f80791b5101d9bf44fc",
    "mimeType": "image/png",
    "kss": {
      "block_infos": [
        {
          "blob": {},
          "size": 1049250,
          "md5": "8515cd26bb45daf9fac449323e580f7b",
          "sha1": "2c16413bdd14de8f2f4d2f80791b5101d9bf44fc"
        }
      ]
    }
  }
}
```

## 5. 语音文件上传 API（已验证）

根据 2026-01-11 的完整测试结果：

### 完整上传流程

语音文件上传分为三个步骤：

#### 步骤 1：请求上传（request_upload_file）

```
POST https://i.mi.com/file/v2/user/request_upload_file
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

**请求体**:
```
data={JSON数据}&serviceToken={token}
```

**data 参数结构（语音文件）**:
```json
{
  "type": "note_img",
  "storage": {
    "filename": "recording.mp3",
    "size": 12345,
    "sha1": "8a41074a7bf788cf921a32a781e7b676f3103968",
    "mimeType": "audio/mpeg",
    "kss": {
      "block_infos": [
        {
          "blob": {},
          "size": 12345,
          "md5": "...",
          "sha1": "8a41074a7bf788cf921a32a781e7b676f3103968"
        }
      ]
    }
  }
}
```

**响应示例（服务器无缓存）**:
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "storage": {
      "uploadId": "FuK4o-YJFk4YFKe-Q-5_1YxLL2Sph...",
      "exists": false,
      "kss": {
        "stat": "OK",
        "block_metas": [
          {
            "is_existed": 0,
            "block_meta": "GBSnvkPuf9WMSy9kqYR3aZHt4ZEs..."
          }
        ],
        "node_urls": ["https://ali.xmssdn.micloud.mi.com/2/1566455553514"],
        "file_meta": "VpFtRGfOo9rR47jTmT421sh7ot0G..."
      }
    }
  }
}
```

#### 步骤 2：上传文件块（upload_block_chunk）

```
POST {node_url}/upload_block_chunk?chunk_pos=0&&file_meta={file_meta}&block_meta={block_meta}
Content-Type: application/octet-stream
```

**请求体**: 原始文件二进制数据

**响应**: 返回 `commit_meta` 用于下一步提交

#### 步骤 3：提交上传（commit）

```
POST https://i.mi.com/file/v2/user/commit
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
```

**请求体**:
```
commit={JSON数据}&serviceToken={token}
```

**commit 参数结构**:
```json
{
  "storage": {
    "uploadId": "FuK4o-YJFk4YFKe-Q-5_1YxLL2Sph...",
    "size": 12345,
    "sha1": "8a41074a7bf788cf921a32a781e7b676f3103968",
    "kss": {
      "file_meta": "VpFtRGfOo9rR47jTmT421sh7ot0G...",
      "commit_metas": [
        {
          "commit_meta": "..."
        }
      ]
    }
  }
}
```

**响应示例**:
```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "fileId": "1315204657.xxxxxxxxxxxxx"
  }
}
```

### type 参数测试结果

| 文件类型 | type 参数 | 状态 | 备注 |
|----------|-----------|------|------|
| 图片 | `note_img` | ✅ 有效 | 官方使用 |
| 语音 | `note_img` | ✅ 有效 | **必须使用此值** |
| 语音 | `note_sound` | ❌ 无效 | 返回 "wrong type value" |
| 语音 | `note_recording` | ❌ 无效 | 返回 "wrong type value" |
| 语音 | `note_audio` | ❌ 无效 | 返回 "wrong type value" |

### MIME 类型说明

| MIME 类型 | 状态 | 说明 |
|-----------|------|------|
| `audio/mpeg` | ✅ 推荐 | RFC 3003 标准 MIME 类型 |
| `audio/mp3` | ⚠️ 可用 | 非标准但服务器接受 |

### 重要发现

1. **type 参数**: 语音文件**必须**使用 `note_img` 类型，与图片上传相同
2. **JSON 字段顺序**: 必须与图片上传保持一致（type → storage → filename → size → sha1 → mimeType → kss）
3. **mimeType**: 推荐使用标准 MIME 类型 `audio/mpeg`
4. **block_infos.size**: 必须包含 size 字段，否则可能失败

## 5. 验证要点

### 解析验证

1. ✅ 能够正确解析 `<sound fileid="xxx" />` 标签
2. ✅ 能够提取 fileId 属性值
3. ✅ 能够解析 setting.data 中的元数据
4. ✅ fileId 格式验证：`数字.随机字符串`
5. ✅ digest 格式验证：`SHA1.扩展名`
6. ✅ mimeType 验证：以 `audio/` 开头

### 错误处理验证

1. 缺少 fileid 属性时的处理
2. fileid 为空时的处理
3. 笔记不存在时的错误响应

## 6. 测试数据

### 测试笔记

- 笔记 ID：`48926433520534752`
- 语音 fileId：`1315204657.jgHyouv563iSF_XCE4jhAg`
- 语音 digest：`8a41074a7bf788cf921a32a781e7b676f3103968.mp3`
- 语音 mimeType：`audio/mp3`

## 6. 语音文件下载 API

### 获取下载 URL

```
GET https://i.mi.com/file/full/v2?ts={timestamp}&type=note_img&fileid={fileId}
```

### 参数

| 参数 | 类型 | 说明 |
|------|------|------|
| ts | number | 时间戳（毫秒） |
| type | string | 文件类型，必须使用 `note_img` |
| fileid | string | 文件 ID（如 `1315204657.jgHyouv563iSF_XCE4jhAg`） |

### 请求头

| 头部 | 值 |
|------|------|
| Cookie | (包含 serviceToken 等认证信息) |

### 响应格式

API 返回两种可能的响应格式：

#### 格式 1：简单格式（直接 URL）

```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "url": "https://xxx.xmssdn.micloud.mi.com/xxx?..."
  }
}
```

#### 格式 2：KSS 格式（分块下载，可能包含解密密钥）

```json
{
  "result": "ok",
  "code": 0,
  "data": {
    "kss": {
      "blocks": [
        {
          "urls": ["http://xxx.xmssdn.micloud.mi.com/xxx?..."]
        }
      ],
      "secure_key": "base64_encoded_aes_key"
    }
  }
}
```

### secure_key 解密密钥

| 字段 | 类型 | 说明 |
|------|------|------|
| secure_key | string | Base64 编码的 AES 解密密钥（可选） |

**重要说明**：
- `secure_key` 字段可能存在于 KSS 格式的响应中
- 如果存在 `secure_key`，表示下载的音频文件是加密的，需要使用该密钥进行 AES 解密
- 如果不存在 `secure_key`，表示音频文件未加密，可以直接播放

### 下载音频文件

获取到下载 URL 后，直接使用 GET 请求下载音频数据：

```
GET {download_url}
```

注意：下载请求不需要认证头，因为 URL 已经包含了认证信息（签名参数）。

### 重要发现

1. **type 参数**: 下载时也必须使用 `note_img` 类型（与上传时相同）
2. **URL 有效期**: 下载 URL 是临时的，有一定的有效期
3. **无需认证**: 下载 URL 本身包含认证信息，不需要额外的 Cookie
4. **响应格式**: API 可能返回简单格式或 KSS 格式，代码需要同时支持两种格式
5. **加密文件**: KSS 格式响应可能包含 `secure_key` 字段，表示文件已加密，需要 AES 解密

## 7. 音频文件解密

### 解密服务

小米云服务返回的音频文件可能是加密的，需要使用 `secure_key` 进行解密。

**服务位置**: `Sources/Service/AudioDecryptService.swift`

### 支持的解密算法

| 算法 | 优先级 | 说明 |
|------|--------|------|
| RC4 变体 (1024轮预热) | 1 | 小米云服务常用，在标准 RC4 基础上增加 1024 轮预热 |
| 标准 RC4 | 2 | 标准 RC4 流密码算法 |
| 简单 XOR | 3 | 简单的 XOR 加密 |

### 密钥格式

- **类型**: 十六进制字符串
- **示例**: `22eaa6338446d728`
- **来源**: KSS 响应的 `secure_key` 字段

### 支持的音频格式检测

| 格式 | 魔数 (Magic Bytes) | 说明 |
|------|-------------------|------|
| MP3 (ID3) | `49 44 33` | ID3 标签开头 |
| MP3 (帧同步) | `FF FB/FA/F3/F2` | MP3 帧同步字 |
| AAC (ADTS) | `FF F0/F1` | AAC ADTS 同步字 |
| M4A/MP4 | `xx xx xx xx 66 74 79 70` | ftyp 标识 |
| WAV | `52 49 46 46 ... 57 41 56 45` | RIFF...WAVE |
| OGG | `4F 67 67 53` | OggS 标识 |
| FLAC | `66 4C 61 43` | fLaC 标识 |

### 解密流程

```
1. 调用 getAudioDownloadInfo 获取下载 URL 和 secure_key
2. 下载加密的音频数据
3. 如果存在 secure_key，调用 AudioDecryptService.decrypt()
4. 解密服务自动尝试多种算法，返回第一个成功的结果
5. 通过检查音频文件头部魔数验证解密是否成功
6. 如果所有解密方法都失败，返回原始数据（可能本身未加密）
```

### 代码示例

```swift
// 获取下载信息
let downloadInfo = try await MiNoteService.shared.getAudioDownloadInfo(fileId: fileId)
let downloadURL = downloadInfo.url
let secureKey = downloadInfo.secureKey

// 下载音频数据
let audioData = try await downloadAudioData(from: downloadURL)

// 解密（如果需要）
let decryptedData: Data
if let key = secureKey {
    decryptedData = AudioDecryptService.shared.decrypt(data: audioData, secureKey: key)
} else {
    decryptedData = audioData
}

// 播放解密后的音频
try AudioPlayerService.shared.play(data: decryptedData)
```

## 8. 后续工作

1. ✅ 验证语音上传 API 的 type 参数 - **必须使用 `note_img`**
2. ✅ 完整上传流程测试（request_upload_file → upload_block_chunk → commit）
3. ✅ 测试语音文件的下载/播放 URL - **使用 `/file/full/v2` API**
4. ✅ 实现音频解密服务 - **AudioDecryptService 支持 RC4 变体/标准 RC4/XOR**
5. 验证删除语音后的 XML 导出
6. 集成解密服务到 AudioAttachment 播放流程
