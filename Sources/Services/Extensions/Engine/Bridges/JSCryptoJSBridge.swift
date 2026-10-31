import Foundation
import JavaScriptCore
import CryptoKit
import CommonCrypto
import Security

/// Phần native cho CryptoJS của tiện ích (hợp đồng chuẩn, mục "Crypto"): số ngẫu nhiên an toàn, AES-GCM, PBKDF2.
/// JS bổ sung ở `JSCryptoJSBootstrapScript`; thư viện CryptoJS ở `JSBuiltInLibrary`.
///
/// Dữ liệu qua lại với JS đều là chuỗi hex, nên WordArray có byte ≥ 0x80 vẫn đúng (app gốc đổi WordArray ra chuỗi nên
/// chỉ đúng với byte < 0x80). Kết quả dạng `"ok:…"` / `"err:<lý do>"` để JS phân biệt lỗi với dữ liệu rỗng.
enum JSCryptoJSBridge {
    /// Trần một lần lấy byte ngẫu nhiên (`WordArray.random`); `crypto.getRandomValues` tự giới hạn 65 536 byte như Web Crypto.
    static let maxRandomBytes = 1 << 20
    /// Trần độ dài khoá PBKDF2 (byte) — quá thì JS tự chạy bản thuần JS.
    static let maxDerivedKeyBytes = 4096

    /// Cài các block `_native*` rồi `crypto.getRandomValues` vào `context`. Gọi một lần cho mỗi `JSExecutor`.
    static func install(in context: JSContext) {
        let randomBlock: @convention(block) (Double) -> [NSNumber] = { count in
            guard count.isFinite, count >= 1 else { return [] }
            return Self.randomBytes(count: Int(min(count, Double(Self.maxRandomBytes)))).map { NSNumber(value: $0) }
        }
        context.setObject(randomBlock, forKeyedSubscript: "_nativeRandomBytes" as NSCopying & NSObjectProtocol)

        let gcmSealBlock: @convention(block) (String, String, String, String) -> String = { key, iv, aad, plain in
            Self.aesGcmSeal(keyHex: key, ivHex: iv, aadHex: aad, plainHex: plain)
        }
        context.setObject(gcmSealBlock, forKeyedSubscript: "_nativeAesGcmSeal" as NSCopying & NSObjectProtocol)

        let gcmOpenBlock: @convention(block) (String, String, String, String, String) -> String = { key, iv, aad, cipher, tag in
            Self.aesGcmOpen(keyHex: key, ivHex: iv, aadHex: aad, cipherHex: cipher, tagHex: tag)
        }
        context.setObject(gcmOpenBlock, forKeyedSubscript: "_nativeAesGcmOpen" as NSCopying & NSObjectProtocol)

        let pbkdf2Block: @convention(block) (String, String, Double, Double, String) -> String = { password, salt, iterations, keyBytes, hasher in
            Self.pbkdf2(passwordHex: password, saltHex: salt, iterations: iterations, keyBytes: keyBytes, hasher: hasher)
        }
        context.setObject(pbkdf2Block, forKeyedSubscript: "_nativePbkdf2" as NSCopying & NSObjectProtocol)

        context.evaluateScript(JSCryptoJSBootstrapScript.randomPolyfill)
    }

    // MARK: - Số ngẫu nhiên

    static func randomBytes(count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            // `SystemRandomNumberGenerator` cũng lấy từ nguồn ngẫu nhiên an toàn của hệ điều hành.
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes
    }

    // MARK: - AES-GCM

    /// `"ok:<ciphertext hex>:<tag hex>"`. Khoá: byte đã giải (hex 16/24/32 byte hoặc passphrase, đệm 0 / cắt ở đây);
    /// IV rỗng = 12 byte 0; thẻ 128 bit.
    static func aesGcmSeal(keyHex: String, ivHex: String, aadHex: String, plainHex: String) -> String {
        guard let key = bytes(fromHex: keyHex), let iv = bytes(fromHex: ivHex), let aad = bytes(fromHex: aadHex),
              let plain = bytes(fromHex: plainHex) else { return "err:dữ liệu hex không hợp lệ" }
        do {
            let box = try AES.GCM.seal(plain, using: SymmetricKey(data: fittedKey(key)), nonce: nonce(iv), authenticating: aad)
            return "ok:\(hex(box.ciphertext)):\(hex(box.tag))"
        } catch {
            return "err:\(failureReason(iv: iv))"
        }
    }

    /// `"ok:<plaintext hex>"`; sai thẻ / sai khoá / dữ liệu hỏng ⇒ `"err:…"` (JS trả WordArray rỗng).
    static func aesGcmOpen(keyHex: String, ivHex: String, aadHex: String, cipherHex: String, tagHex: String) -> String {
        guard let key = bytes(fromHex: keyHex), let iv = bytes(fromHex: ivHex), let aad = bytes(fromHex: aadHex),
              let cipher = bytes(fromHex: cipherHex), let tag = bytes(fromHex: tagHex) else { return "err:dữ liệu hex không hợp lệ" }
        do {
            let box = try AES.GCM.SealedBox(nonce: nonce(iv), ciphertext: cipher, tag: tag)
            let plain = try AES.GCM.open(box, using: SymmetricKey(data: fittedKey(key)), authenticating: aad)
            return "ok:" + hex(plain)
        } catch {
            let reason = failureReason(iv: iv)
            AppLogger.shared.log("❌ [CryptoJS] AES-GCM giải mã thất bại: \(reason)")
            return "err:\(reason)"
        }
    }

    private static func nonce(_ iv: [UInt8]) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: iv.isEmpty ? [UInt8](repeating: 0, count: 12) : iv)
    }

    private static func failureReason(iv: [UInt8]) -> String {
        if !iv.isEmpty && iv.count < 12 { return "IV phải dài ít nhất 12 byte (đang \(iv.count))" }
        return "khoá, IV, AAD hoặc thẻ xác thực không khớp"
    }

    /// Khoá AES đệm 0 / cắt về 16, 24 hoặc 32 byte (cùng quy ước `LegadoAESGCM`).
    private static func fittedKey(_ key: [UInt8]) -> [UInt8] {
        let sizes = [16, 24, 32]
        if sizes.contains(key.count) { return key }
        let target = sizes.first(where: { $0 >= key.count }) ?? 32
        if key.count > target { return Array(key.prefix(target)) }
        return key + [UInt8](repeating: 0, count: target - key.count)
    }

    // MARK: - PBKDF2

    /// Hex khoá dẫn xuất; `""` khi hasher không hỗ trợ hoặc CommonCrypto từ chối (JS tự chạy bản thuần JS).
    static func pbkdf2(passwordHex: String, saltHex: String, iterations: Double, keyBytes: Double, hasher: String) -> String {
        guard let password = bytes(fromHex: passwordHex), let salt = bytes(fromHex: saltHex),
              let prf = pseudoRandomAlgorithm(hasher), keyBytes.isFinite, keyBytes >= 1,
              keyBytes <= Double(maxDerivedKeyBytes), keyBytes == keyBytes.rounded() else { return "" }
        // CryptoJS coi 0 hay số âm như 1 vòng.
        let rounds = iterations.isFinite ? UInt32(min(max(iterations.rounded(.down), 1), Double(UInt32.max))) : 1
        let passwordChars = password.map { CChar(bitPattern: $0) }
        var derived = [UInt8](repeating: 0, count: Int(keyBytes))
        let status = derived.withUnsafeMutableBufferPointer { output in
            salt.withUnsafeBufferPointer { saltBuffer in
                passwordChars.withUnsafeBufferPointer { passwordBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordBuffer.baseAddress, passwordBuffer.count,
                                         saltBuffer.baseAddress, saltBuffer.count, prf, rounds,
                                         output.baseAddress, output.count)
                }
            }
        }
        return status == kCCSuccess ? hex(derived) : ""
    }

    private static func pseudoRandomAlgorithm(_ hasher: String) -> CCPseudoRandomAlgorithm? {
        switch hasher {
        case "SHA1": return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
        case "SHA224": return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA224)
        case "SHA256": return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
        case "SHA384": return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
        case "SHA512": return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
        default: return nil
        }
    }

    // MARK: - Hex

    private static func bytes(fromHex text: String) -> [UInt8]? {
        let digits = Array(text.utf8)
        guard digits.count % 2 == 0 else { return nil }
        var output = [UInt8]()
        output.reserveCapacity(digits.count / 2)
        var index = 0
        while index < digits.count {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            output.append(high << 4 | low)
            index += 2
        }
        return output
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case 48...57: return digit - 48
        case 65...70: return digit - 55
        case 97...102: return digit - 87
        default: return nil
        }
    }

    private static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        let alphabet = Array("0123456789abcdef".utf8)
        var output = [UInt8]()
        for byte in bytes {
            output.append(alphabet[Int(byte >> 4)])
            output.append(alphabet[Int(byte & 0x0f)])
        }
        return String(decoding: output, as: UTF8.self)
    }
}
