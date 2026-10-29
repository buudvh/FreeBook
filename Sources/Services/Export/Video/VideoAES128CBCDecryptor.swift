import CommonCrypto
import Foundation

/// Giải mã AES-128-CBC (đệm PKCS7) **theo luồng** bằng CommonCrypto cho một đoạn HLS: `update` từng khúc rồi `finish`.
/// Mỗi đoạn một instance (IV riêng) — không giữ cả đoạn trong RAM. `VideoHLSStreamWriter` dùng khi xuất video.
final class VideoAES128CBCDecryptor {
    enum CryptorError: LocalizedError {
        case invalidInput
        case failed(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidInput: return "Khoá hoặc IV giải mã không đủ 16 byte."
            case .failed(let status): return "Giải mã AES-128 thất bại (CCCryptor \(status)) — bản tải có thể đã hỏng."
            }
        }
    }

    private var cryptor: CCCryptorRef?

    init(key: Data, iv: Data) throws {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else { throw CryptorError.invalidInput }
        var reference: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBuffer -> CCCryptorStatus in
            iv.withUnsafeBytes { ivBuffer -> CCCryptorStatus in
                CCCryptorCreate(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    keyBuffer.baseAddress,
                    key.count,
                    ivBuffer.baseAddress,
                    &reference
                )
            }
        }
        guard status == kCCSuccess, let reference else { throw CryptorError.failed(Int32(status)) }
        cryptor = reference
    }

    deinit {
        if let cryptor {
            CCCryptorRelease(cryptor)
        }
    }

    /// Giải mã một khúc; khối cuối chưa đủ 16 byte được giữ lại cho lượt sau / `finish`.
    func update(_ input: Data) throws -> Data {
        guard let cryptor, !input.isEmpty else { return Data() }
        let capacity = CCCryptorGetOutputLength(cryptor, input.count, false)
        var output = Data(count: max(capacity, kCCBlockSizeAES128))
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBuffer -> CCCryptorStatus in
            input.withUnsafeBytes { inputBuffer -> CCCryptorStatus in
                CCCryptorUpdate(cryptor, inputBuffer.baseAddress, input.count, outputBuffer.baseAddress, outputBuffer.count, &moved)
            }
        }
        guard status == kCCSuccess else { throw CryptorError.failed(Int32(status)) }
        output.count = moved
        return output
    }

    /// Khối cuối + bỏ đệm PKCS7. Gọi đúng một lần sau `update` cuối cùng.
    func finish() throws -> Data {
        guard let cryptor else { return Data() }
        var output = Data(count: max(CCCryptorGetOutputLength(cryptor, 0, true), kCCBlockSizeAES128))
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBuffer -> CCCryptorStatus in
            CCCryptorFinal(cryptor, outputBuffer.baseAddress, outputBuffer.count, &moved)
        }
        guard status == kCCSuccess else { throw CryptorError.failed(Int32(status)) }
        output.count = moved
        return output
    }
}
