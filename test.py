#!/usr/bin/env python3
"""
小米笔记音频文件解密测试脚本

测试多种可能的解密方法：
1. 简单 XOR（使用 secure_key）
2. 标准 RC4
3. 小米变体 RC4（带 1024 轮预热）
4. AES-128-ECB
5. AES-128-CBC
6. AES-128-CTR
"""

import sys
from binascii import unhexlify
from Crypto.Cipher import AES

def xor_decrypt(data, key):
    """简单 XOR 解密"""
    out = bytearray()
    key_len = len(key)
    for i, byte in enumerate(data):
        out.append(byte ^ key[i % key_len])
    return bytes(out)

def rc4_decrypt(data, key):
    """标准 RC4 解密"""
    S = list(range(256))
    j = 0
    
    # KSA (Key Scheduling Algorithm)
    for i in range(256):
        j = (j + S[i] + key[i % len(key)]) % 256
        S[i], S[j] = S[j], S[i]
    
    # PRGA (Pseudo-Random Generation Algorithm)
    i = j = 0
    out = bytearray()
    for byte in data:
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
        out.append(byte ^ S[(S[i] + S[j]) % 256])
    
    return bytes(out)

def rc4mi_decrypt(data, key):
    """小米变体 RC4 解密（带 1024 轮预热）"""
    S = list(range(256))
    j = 0
    
    # KSA
    for i in range(256):
        j = (j + S[i] + key[i % len(key)]) % 256
        S[i], S[j] = S[j], S[i]
    
    # 1024 fake rounds (小米变体)
    i = j = 0
    for _ in range(1024):
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
    
    # PRGA
    out = bytearray()
    for byte in data:
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
        out.append(byte ^ S[(S[i] + S[j]) % 256])
    
    return bytes(out)

def aes_ecb_decrypt(data, key):
    """AES-128-ECB 解密"""
    try:
        cipher = AES.new(key, AES.MODE_ECB)
        # 需要填充到 16 字节的倍数
        padded_len = (len(data) + 15) // 16 * 16
        padded_data = data + b'\x00' * (padded_len - len(data))
        return cipher.decrypt(padded_data)[:len(data)]
    except Exception as e:
        return f"Error: {e}".encode()

def aes_cbc_decrypt(data, key, iv=None):
    """AES-128-CBC 解密"""
    try:
        if iv is None:
            iv = b'\x00' * 16  # 默认 IV 为全零
        cipher = AES.new(key, AES.MODE_CBC, iv)
        # 需要填充到 16 字节的倍数
        padded_len = (len(data) + 15) // 16 * 16
        padded_data = data + b'\x00' * (padded_len - len(data))
        return cipher.decrypt(padded_data)[:len(data)]
    except Exception as e:
        return f"Error: {e}".encode()

def aes_ctr_decrypt(data, key, nonce=None):
    """AES-128-CTR 解密"""
    try:
        if nonce is None:
            nonce = b'\x00' * 8  # 默认 nonce 为全零
        cipher = AES.new(key, AES.MODE_CTR, nonce=nonce)
        return cipher.decrypt(data)
    except Exception as e:
        return f"Error: {e}".encode()

def is_valid_mp3(data):
    """检查是否是有效的 MP3 文件"""
    if len(data) < 4:
        return False
    # ID3 标签
    if data[:3] == b'ID3':
        return True
    # MP3 帧同步
    if data[0] == 0xFF and (data[1] & 0xE0) == 0xE0:
        return True
    return False

def print_hex(data, length=32):
    """打印十六进制数据"""
    return ' '.join(f'{b:02x}' for b in data[:length])

def main():
    # 音频文件路径（需要替换为实际路径）
    audio_file = "/Users/acckion/Library/Application Support/com.minote.MiNoteMac/audio/1315204657.VkSmwhizGV-R1PbeCuDBUw.mp3"
    
    # secure_key（需要替换为实际值）
    # 从 API 响应中获取
    secure_key_hex = "22eaa6338446d7288c0f7e627c8900c9"
    
    print("=" * 60)
    print("小米笔记音频文件解密测试")
    print("=" * 60)
    
    # 读取加密文件
    try:
        with open(audio_file, 'rb') as f:
            encrypted_data = f.read()
        print(f"\n✅ 读取文件成功: {audio_file}")
        print(f"   文件大小: {len(encrypted_data)} 字节")
    except FileNotFoundError:
        print(f"\n❌ 文件不存在: {audio_file}")
        print("请更新 audio_file 变量为实际的音频文件路径")
        return
    
    # 解析密钥
    secure_key = unhexlify(secure_key_hex)
    print(f"\n密钥信息:")
    print(f"   Hex: {secure_key_hex}")
    print(f"   长度: {len(secure_key)} 字节")
    
    # 显示加密数据头部
    print(f"\n加密数据头部 (hex): {print_hex(encrypted_data)}")
    print(f"加密数据头部 (ascii): {encrypted_data[:32]}")
    
    # 测试各种解密方法
    methods = [
        ("简单 XOR", lambda d, k: xor_decrypt(d, k)),
        ("标准 RC4", lambda d, k: rc4_decrypt(d, k)),
        ("小米变体 RC4 (1024轮)", lambda d, k: rc4mi_decrypt(d, k)),
        ("AES-128-ECB", lambda d, k: aes_ecb_decrypt(d, k)),
        ("AES-128-CBC (IV=0)", lambda d, k: aes_cbc_decrypt(d, k)),
        ("AES-128-CTR (nonce=0)", lambda d, k: aes_ctr_decrypt(d, k)),
    ]
    
    print("\n" + "=" * 60)
    print("测试各种解密方法")
    print("=" * 60)
    
    for name, decrypt_func in methods:
        print(f"\n--- {name} ---")
        try:
            decrypted = decrypt_func(encrypted_data, secure_key)
            print(f"解密后头部 (hex): {print_hex(decrypted)}")
            
            # 尝试显示 ASCII（如果可打印）
            try:
                ascii_preview = decrypted[:32].decode('latin-1')
                print(f"解密后头部 (ascii): {repr(ascii_preview)}")
            except:
                pass
            
            if is_valid_mp3(decrypted):
                print(f"✅ 可能是有效的 MP3 文件！")
                output_file = f"/tmp/decrypted_{name.replace(' ', '_').replace('(', '').replace(')', '').replace('=', '')}.mp3"
                with open(output_file, 'wb') as f:
                    f.write(decrypted)
                print(f"   已保存到: {output_file}")
            else:
                print(f"❌ 不是有效的 MP3 文件")
        except Exception as e:
            print(f"❌ 解密失败: {e}")
    
    # 额外测试：使用 MIUI 相册的 AES-CTR IV
    print("\n" + "=" * 60)
    print("额外测试：MIUI 相册 AES-CTR IV")
    print("=" * 60)
    
    # MIUI 相册使用的 IV
    miui_iv = bytes([17, 19, 33, 35, 49, 51, 65, 67, 81, 83, 97, 102, 103, 104, 113, 114])
    print(f"MIUI IV (hex): {print_hex(miui_iv, 16)}")
    
    try:
        cipher = AES.new(secure_key, AES.MODE_CTR, nonce=miui_iv[:8])
        decrypted = cipher.decrypt(encrypted_data)
        print(f"解密后头部 (hex): {print_hex(decrypted)}")
        if is_valid_mp3(decrypted):
            print(f"✅ 可能是有效的 MP3 文件！")
            with open("/tmp/decrypted_miui_ctr.mp3", 'wb') as f:
                f.write(decrypted)
            print(f"   已保存到: /tmp/decrypted_miui_ctr.mp3")
        else:
            print(f"❌ 不是有效的 MP3 文件")
    except Exception as e:
        print(f"❌ 解密失败: {e}")
    
    # 测试：使用密钥的 MD5 作为 AES 密钥
    print("\n" + "=" * 60)
    print("额外测试：使用 secure_key 的 MD5 作为 AES 密钥")
    print("=" * 60)
    
    import hashlib
    md5_key = hashlib.md5(secure_key_hex.encode()).digest()
    print(f"MD5 密钥 (hex): {print_hex(md5_key, 16)}")
    
    for mode_name, mode in [("ECB", AES.MODE_ECB), ("CBC", AES.MODE_CBC)]:
        try:
            if mode == AES.MODE_CBC:
                cipher = AES.new(md5_key, mode, iv=b'\x00' * 16)
            else:
                cipher = AES.new(md5_key, mode)
            padded_len = (len(encrypted_data) + 15) // 16 * 16
            padded_data = encrypted_data + b'\x00' * (padded_len - len(encrypted_data))
            decrypted = cipher.decrypt(padded_data)[:len(encrypted_data)]
            print(f"\nAES-128-{mode_name} (MD5 key):")
            print(f"解密后头部 (hex): {print_hex(decrypted)}")
            if is_valid_mp3(decrypted):
                print(f"✅ 可能是有效的 MP3 文件！")
        except Exception as e:
            print(f"AES-128-{mode_name} (MD5 key): ❌ {e}")

if __name__ == "__main__":
    main()
