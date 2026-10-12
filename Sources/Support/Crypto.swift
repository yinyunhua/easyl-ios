import Foundation
import CommonCrypto

/// 脚本 kits.* 的原生实现（对应原版 QuickJS 绑定的加解密工具集）
enum Crypto {
    static func md5(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return hex(digest)
    }

    static func sha1(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA1(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return hex(digest)
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return hex(digest)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hex(_ input: String) -> String {
        hex([UInt8](input.utf8))
    }

    static func base64Encode(_ input: String) -> String {
        Data(input.utf8).base64EncodedString()
    }

    static func base64Decode(_ input: String) -> String {
        guard let data = Data(base64Encoded: input, options: [.ignoreUnknownCharacters]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// AES-CBC + PKCS7；加密返回 base64，解密输入 base64
    static func aes(encrypt: Bool, data: String, key: String, iv: String) -> String {
        let keyData = Data(key.utf8)
        guard [16, 24, 32].contains(keyData.count) else { return "" }

        var ivBytes = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let ivData = Data(iv.utf8)
        if ivData.count == kCCBlockSizeAES128 {
            ivBytes = [UInt8](ivData)
        }

        let inputData: Data
        if encrypt {
            inputData = Data(data.utf8)
        } else {
            guard let decoded = Data(base64Encoded: data, options: [.ignoreUnknownCharacters]) else { return "" }
            inputData = decoded
        }

        var output = [UInt8](repeating: 0, count: inputData.count + kCCBlockSizeAES128)
        var moved = 0

        let status: CCCryptorStatus = inputData.withUnsafeBytes { inBuffer in
            keyData.withUnsafeBytes { keyBuffer in
                ivBytes.withUnsafeBytes { ivBuffer in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, keyData.count,
                            ivBuffer.baseAddress,
                            inBuffer.baseAddress, inputData.count,
                            &output, output.count,
                            &moved)
                }
            }
        }

        guard status == kCCSuccess else { return "" }
        let result = Data(output.prefix(moved))
        return encrypt ? result.base64EncodedString() : (String(data: result, encoding: .utf8) ?? "")
    }
}
