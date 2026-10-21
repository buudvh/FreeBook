import Foundation
import CryptoKit

/// AES-GCM (spec §14.4: `GCMParameterSpec`, `AES/GCM/NoPadding`) qua CryptoKit. Thẻ xác thực nằm **cuối** dữ liệu như
/// quy ước nền tảng Java; CryptoKit chỉ hỗ trợ thẻ 128 bit.
enum LegadoAESGCM {
    static func isGCM(_ transformation: String) -> Bool {
        transformation.uppercased().contains("/GCM")
    }

    static func encrypt(_ data: Data, key: Data, nonce: Data, tagBits: Int = 128) throws -> Data {
        try checkTag(tagBits)
        do {
            let box = try AES.GCM.seal(data, using: SymmetricKey(data: fitted(key)), nonce: AES.GCM.Nonce(data: nonce))
            return box.ciphertext + box.tag
        } catch {
            throw LegadoJSNativeError("AES-GCM mã hoá thất bại: \(error.localizedDescription)")
        }
    }

    static func decrypt(_ data: Data, key: Data, nonce: Data, tagBits: Int = 128) throws -> Data {
        try checkTag(tagBits)
        guard data.count >= 16 else { throw LegadoJSNativeError("AES-GCM: dữ liệu ngắn hơn thẻ xác thực") }
        do {
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: data.prefix(data.count - 16),
                                            tag: data.suffix(16))
            return try AES.GCM.open(box, using: SymmetricKey(data: fitted(key)))
        } catch {
            throw LegadoJSNativeError("AES-GCM giải mã thất bại: \(error.localizedDescription)")
        }
    }

    private static func checkTag(_ bits: Int) throws {
        guard bits == 128 else { throw LegadoJSNativeError.unsupported("AES-GCM thẻ \(bits) bit") }
    }

    /// Khoá AES đệm 0 / cắt về 16, 24 hoặc 32 byte (như lõi đối xứng).
    private static func fitted(_ key: Data) -> Data {
        let sizes = [16, 24, 32]
        if sizes.contains(key.count) { return key }
        let target = sizes.first(where: { $0 >= key.count }) ?? 32
        if key.count > target { return key.prefix(target) }
        return key + Data(repeating: 0, count: target - key.count)
    }
}
