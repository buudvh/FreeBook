import Foundation
import CommonCrypto

/// Mã hoá đối xứng cho `java.createSymmetricCrypto` / `java.aesBase64DecodeToString` (spec §6.4.3), trên CommonCrypto.
///
/// Biến đổi `Thuật-toán/Chế-độ/Đệm` so không phân biệt hoa thường: AES, DES, DESede (3DES); CBC, ECB; PKCS5 ≡ PKCS7,
/// ZeroPadding, NoPadding. Thiếu IV ở CBC ⇒ IV toàn 0. Khoá AES ngắn/dài được đệm 0/cắt về 16/24/32 byte.
struct LegadoSymmetricCipher {
    enum Padding {
        case pkcs7
        case zero
        case none
    }

    let algorithm: CCAlgorithm
    let blockSize: Int
    let keySizes: [Int]
    let ecb: Bool
    let padding: Padding

    init(transformation: String) throws {
        let parts = transformation.uppercased().split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.first ?? "AES"
        switch name {
        case "AES":
            algorithm = CCAlgorithm(kCCAlgorithmAES)
            blockSize = kCCBlockSizeAES128
            keySizes = [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256]
        case "DES":
            algorithm = CCAlgorithm(kCCAlgorithmDES)
            blockSize = kCCBlockSizeDES
            keySizes = [kCCKeySizeDES]
        case "DESEDE", "TRIPLEDES", "3DES":
            algorithm = CCAlgorithm(kCCAlgorithm3DES)
            blockSize = kCCBlockSize3DES
            keySizes = [kCCKeySize3DES]
        default:
            throw LegadoJSNativeError.unsupported("thuật toán \(name)")
        }
        let mode = parts.count > 1 ? parts[1] : "ECB"
        guard mode == "CBC" || mode == "ECB" else { throw LegadoJSNativeError.unsupported("chế độ \(mode)") }
        ecb = mode == "ECB"
        let paddingName = parts.count > 2 ? parts[2] : "PKCS5PADDING"
        switch paddingName {
        case "PKCS5PADDING", "PKCS7PADDING": padding = .pkcs7
        case "ZEROPADDING", "ZEROBYTEPADDING": padding = .zero
        case "NOPADDING": padding = .none
        default: throw LegadoJSNativeError.unsupported("đệm \(paddingName)")
        }
    }

    func encrypt(_ data: Data, key: Data, iv: Data?) throws -> Data {
        var input = data
        if padding == .zero {
            let remainder = input.count % blockSize
            if remainder != 0 || input.isEmpty { input.append(contentsOf: [UInt8](repeating: 0, count: blockSize - remainder)) }
        }
        return try run(CCOperation(kCCEncrypt), input, key: key, iv: iv)
    }

    func decrypt(_ data: Data, key: Data, iv: Data?) throws -> Data {
        var output = try run(CCOperation(kCCDecrypt), data, key: key, iv: iv)
        if padding == .zero {
            while let last = output.last, last == 0 { output.removeLast() }
        }
        return output
    }

    private func run(_ operation: CCOperation, _ input: Data, key rawKey: Data, iv rawIV: Data?) throws -> Data {
        let key = fittedKey(rawKey)
        var options = CCOptions(0)
        if padding == .pkcs7 { options |= CCOptions(kCCOptionPKCS7Padding) }
        if ecb { options |= CCOptions(kCCOptionECBMode) }
        var iv = rawIV ?? Data()
        if iv.count < blockSize { iv.append(contentsOf: [UInt8](repeating: 0, count: blockSize - iv.count)) }
        if iv.count > blockSize { iv = iv.prefix(blockSize) }

        var output = Data(count: input.count + blockSize)
        var moved = 0
        let outputCapacity = output.count
        let status = output.withUnsafeMutableBytes { outputBuffer -> CCCryptorStatus in
            input.withUnsafeBytes { inputBuffer -> CCCryptorStatus in
                key.withUnsafeBytes { keyBuffer -> CCCryptorStatus in
                    iv.withUnsafeBytes { ivBuffer -> CCCryptorStatus in
                        CCCrypt(
                            operation,
                            algorithm,
                            options,
                            keyBuffer.baseAddress,
                            key.count,
                            ecb ? nil : ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            input.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw LegadoJSNativeError("Mã hoá đối xứng thất bại (CCCrypt \(status))")
        }
        output.removeSubrange(moved..<output.count)
        return output
    }

    /// Khoá được đệm 0 / cắt về kích thước hợp lệ gần nhất.
    private func fittedKey(_ key: Data) -> Data {
        if keySizes.contains(key.count) { return key }
        let target = keySizes.first(where: { $0 >= key.count }) ?? keySizes.last ?? key.count
        if key.count > target { return key.prefix(target) }
        var padded = key
        padded.append(contentsOf: [UInt8](repeating: 0, count: target - key.count))
        return padded
    }
}
