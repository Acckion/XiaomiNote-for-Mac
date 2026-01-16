import Foundation

/// 音频文件解密服务
/// 
/// 负责解密从小米云服务下载的加密音频文件。
/// 小米云服务使用 KSS（Key Storage Service）系统，
/// 每次下载请求会返回一个临时的 secure_key 用于解密。
/// 
/// 支持的解密算法：
/// - RC4 变体（带 1024 轮预热）- 小米云服务常用
/// - 标准 RC4
/// - 简单 XOR
final class AudioDecryptService: @unchecked Sendable {
    
    // MARK: - 单例
    
    static let shared = AudioDecryptService()
    
    private init() {}
    
    // MARK: - 解密方法
    
    /// 解密音频数据
    /// 
    /// 尝试使用多种解密方法解密音频数据，返回第一个成功的结果。
    /// 
    /// - Parameters:
    ///   - data: 加密的音频数据
    ///   - secureKey: 解密密钥（十六进制字符串）
    /// - Returns: 解密后的音频数据，如果解密失败则返回原始数据
    func decrypt(data: Data, secureKey: String) -> Data {
        print("[AudioDecrypt] 开始解密，数据大小: \(data.count) 字节，密钥: \(secureKey)")
        
        // 将十六进制密钥转换为字节数组
        guard let keyBytes = hexStringToBytes(secureKey) else {
            print("[AudioDecrypt] ❌ 无效的密钥格式，返回原始数据")
            return data
        }
        
        print("[AudioDecrypt] 密钥长度: \(keyBytes.count) 字节")
        print("[AudioDecrypt] 加密数据头部: \(data.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
        
        // 尝试不同的解密方法
        let methods: [(String, (Data, [UInt8]) -> Data)] = [
            ("RC4 变体 (1024轮)", rc4MiDecrypt),
            ("标准 RC4", rc4Decrypt),
            ("简单 XOR", xorDecrypt)
        ]
        
        for (name, decryptFunc) in methods {
            let decrypted = decryptFunc(data, keyBytes)
            
            // 检查是否是有效的音频文件
            if isValidAudioFile(decrypted) {
                print("[AudioDecrypt] ✅ 使用 \(name) 解密成功！")
                print("[AudioDecrypt] 解密后头部: \(decrypted.prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))")
                return decrypted
            } else {
                print("[AudioDecrypt] ❌ \(name) 解密后不是有效音频")
            }
        }
        
        // 如果所有方法都失败，返回原始数据（可能本身就是未加密的）
        if isValidAudioFile(data) {
            print("[AudioDecrypt] ⚠️ 原始数据已经是有效音频，无需解密")
            return data
        }
        
        print("[AudioDecrypt] ⚠️ 所有解密方法都失败，返回原始数据")
        return data
    }
    
    // MARK: - RC4 变体解密（带 1024 轮预热）
    
    /// RC4 变体解密（小米云服务使用）
    /// 
    /// 与标准 RC4 的区别是在生成密钥流之前先进行 1024 轮"预热"，
    /// 丢弃前 1024 个字节的密钥流。
    /// 
    /// - Parameters:
    ///   - data: 加密数据
    ///   - key: 密钥字节数组
    /// - Returns: 解密后的数据
    private func rc4MiDecrypt(_ data: Data, _ key: [UInt8]) -> Data {
        // 初始化 S 盒
        var S = Array(0...255).map { UInt8($0) }
        var j: Int = 0
        
        // KSA (Key Scheduling Algorithm)
        for i in 0..<256 {
            j = (j + Int(S[i]) + Int(key[i % key.count])) % 256
            S.swapAt(i, j)
        }
        
        // 1024 轮预热（小米变体特有）
        var i: Int = 0
        j = 0
        for _ in 0..<1024 {
            i = (i + 1) % 256
            j = (j + Int(S[i])) % 256
            S.swapAt(i, j)
        }
        
        // PRGA (Pseudo-Random Generation Algorithm)
        var output = Data(count: data.count)
        for (index, byte) in data.enumerated() {
            i = (i + 1) % 256
            j = (j + Int(S[i])) % 256
            S.swapAt(i, j)
            let k = S[(Int(S[i]) + Int(S[j])) % 256]
            output[index] = byte ^ k
        }
        
        return output
    }
    
    // MARK: - 标准 RC4 解密
    
    /// 标准 RC4 解密
    /// 
    /// - Parameters:
    ///   - data: 加密数据
    ///   - key: 密钥字节数组
    /// - Returns: 解密后的数据
    private func rc4Decrypt(_ data: Data, _ key: [UInt8]) -> Data {
        // 初始化 S 盒
        var S = Array(0...255).map { UInt8($0) }
        var j: Int = 0
        
        // KSA (Key Scheduling Algorithm)
        for i in 0..<256 {
            j = (j + Int(S[i]) + Int(key[i % key.count])) % 256
            S.swapAt(i, j)
        }
        
        // PRGA (Pseudo-Random Generation Algorithm)
        var i: Int = 0
        j = 0
        var output = Data(count: data.count)
        for (index, byte) in data.enumerated() {
            i = (i + 1) % 256
            j = (j + Int(S[i])) % 256
            S.swapAt(i, j)
            let k = S[(Int(S[i]) + Int(S[j])) % 256]
            output[index] = byte ^ k
        }
        
        return output
    }
    
    // MARK: - 简单 XOR 解密
    
    /// 简单 XOR 解密
    /// 
    /// - Parameters:
    ///   - data: 加密数据
    ///   - key: 密钥字节数组
    /// - Returns: 解密后的数据
    private func xorDecrypt(_ data: Data, _ key: [UInt8]) -> Data {
        var output = Data(count: data.count)
        for (index, byte) in data.enumerated() {
            output[index] = byte ^ key[index % key.count]
        }
        return output
    }
    
    // MARK: - 辅助方法
    
    /// 将十六进制字符串转换为字节数组
    /// 
    /// - Parameter hex: 十六进制字符串（如 "22eaa6338446d728"）
    /// - Returns: 字节数组，如果格式无效则返回 nil
    private func hexStringToBytes(_ hex: String) -> [UInt8]? {
        var bytes = [UInt8]()
        var index = hex.startIndex
        
        while index < hex.endIndex {
            guard let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else {
                return nil
            }
            
            let byteString = String(hex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            
            bytes.append(byte)
            index = nextIndex
        }
        
        return bytes.isEmpty ? nil : bytes
    }
    
    /// 检查数据是否是有效的音频文件
    /// 
    /// 通过检查文件头部的魔数来判断文件类型。
    /// 
    /// - Parameter data: 要检查的数据
    /// - Returns: 是否是有效的音频文件
    private func isValidAudioFile(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        
        let bytes = [UInt8](data.prefix(12))
        
        // MP3 文件头
        // ID3 标签：以 "ID3" 开头
        if bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 {
            print("[AudioDecrypt] 检测到 ID3 标签")
            return true
        }
        
        // MP3 帧同步：0xFF 0xFB, 0xFF 0xFA, 0xFF 0xF3, 0xFF 0xF2 等
        if bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 {
            print("[AudioDecrypt] 检测到 MP3 帧同步")
            return true
        }
        
        // AAC 文件头：ADTS 同步字 0xFF 0xF0 或 0xFF 0xF1
        if bytes[0] == 0xFF && (bytes[1] & 0xF0) == 0xF0 {
            print("[AudioDecrypt] 检测到 AAC ADTS 头")
            return true
        }
        
        // M4A/MP4 文件头：ftyp
        if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            print("[AudioDecrypt] 检测到 M4A/MP4 ftyp")
            return true
        }
        
        // WAV 文件头：RIFF....WAVE
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            print("[AudioDecrypt] 检测到 WAV RIFF 头")
            return true
        }
        
        // OGG 文件头：OggS
        if bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53 {
            print("[AudioDecrypt] 检测到 OGG 头")
            return true
        }
        
        // FLAC 文件头：fLaC
        if bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43 {
            print("[AudioDecrypt] 检测到 FLAC 头")
            return true
        }
        
        return false
    }
}
