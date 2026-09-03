//
//  JavDBSignature.swift
//  AVDB
//
//  JAVDB 官方 App 逆向得到的签名算法。
//  每个请求的 jdsignature 头依赖当前 Unix 秒时间戳，逐请求实时计算。
//

import Foundation
import CryptoKit

/// JAVDB API 常量（逆向自官方 App v1.9.35）
public enum JavDBConstants {
    /// 生产基址
    public static let baseURL = "https://jdforrepam.com"

    /// 测试/默认基址（Dart 代码 HttpApi.baseUrl 默认值）
    public static let stagingBaseURL = "https://staging.letidi.com"

    /// 图片/视频 CDN（加密流）
    public static let imageCDNHost = "tp.spfcas.com"

    /// 网页版图片 CDN（含水印）
    public static let webCDNHost = "c0.jdbstatic.com"

    /// m3u8 分段 CDN
    public static let hlsSegmentHost = "u1.029xxj.com"

    /// App 版本标识
    public static let appVersionNumber = "1.9.35"

    /// 签名常量 STR1（native libsecurity.so 解密后的固定常量）
    public static let STR1 = "71cf27bb3c0bcdf207b64abecddc970098c7421ee7203b9cdae54478478a199e7d5a6e1a57691123c1a931c057842fb73ba3b3c83bcd69c17ccf174081e3d8aa"

    /// 签名常量 STR2
    public static let STR2 = "lpw6vgqzsp"

    /// 每个请求必带的 query 参数
    public static let baseQuery: [String: String] = [
        "platform": "android",
        "app_channel": "official",
        "app_version": "official",
        "app_version_number": "1.9.35",
        "system_version": "13",
    ]
}

/// 签名计算器
public enum JavDBSignature {
    /// 计算 jdsignature 头
    /// 格式：{timestamp}.lpw6vgqzsp.{md5(str(timestamp) + STR1)}
    public static func make(timestamp: Int = Int(Date().timeIntervalSince1970)) -> String {
        let ts = String(timestamp)
        let raw = ts + JavDBConstants.STR1
        let md5 = raw.md5Hex()
        return "\(ts).\(JavDBConstants.STR2).\(md5)"
    }

    /// 解密图片 CDN 返回的加密流（单字节 XOR）
    /// 格式：enc[0]=key(K)，enc[i]=plaintext[i-1] XOR K
    public static func decryptImage(_ enc: Data) -> Data {
        guard !enc.isEmpty, enc.count > 1 else { return Data() }
        let key = enc[enc.startIndex]
        var out = Data(capacity: enc.count - 1)
        for i in 1..<enc.count {
            out.append(enc[enc.startIndex + i] ^ key)
        }
        return out
    }
}

extension String {
    /// 计算字符串的 MD5 十六进制值（小写）
    func md5Hex() -> String {
        let digest = Insecure.MD5.hash(data: Data(self.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    /// 计算 Data 的 MD5 十六进制值（小写）
    func md5Hex() -> String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
