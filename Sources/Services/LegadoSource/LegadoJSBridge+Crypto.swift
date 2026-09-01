import Foundation
import JavaScriptCore
import SwiftSoup

/// Phần còn lại của bridge `java.*`: băm, mã hoá/giải mã, biến, xử lý chuỗi, bóc tách và nhóm chưa
/// hỗ trợ. Tách file theo khuôn `X+Feature.swift` của repo để `LegadoJSBridge.swift` không phình.
extension LegadoJSBridge {

    // MARK: - Băm & mã hoá đối xứng

    internal static func installDigest(_ java: JSValue?, runtime: LegadoJSRuntime) {
        let md5: @convention(block) (String?) -> String = { input in
            guard let input else { return "" }
            return JSCrypto.md5(input)
        }
        java?.setObject(md5, forKeyedSubscript: "md5Encode" as NSCopying & NSObjectProtocol)

        let digestHex: @convention(block) (String?, String?) -> String = { input, algorithm in
            guard let input else { return "" }
            switch (algorithm ?? "md5").lowercased().replacingOccurrences(of: "-", with: "") {
            case "md5": return JSCrypto.md5(input)
            case "sha1": return JSCrypto.sha1(input)
            case "sha512": return JSCrypto.sha512(input)
            default: return JSCrypto.sha256(input)
            }
        }
        java?.setObject(digestHex, forKeyedSubscript: "digestHex" as NSCopying & NSObjectProtocol)

        let hmacHex: @convention(block) (String?, String?, String?) -> String = { input, algorithm, key in
            guard let input, let key else { return "" }
            switch (algorithm ?? "HmacSHA256").lowercased() {
            case let name where name.contains("sha1"): return JSCrypto.hmacSha1(input, key)
            case let name where name.contains("md5"): return JSCrypto.hmacMd5(input, key)
            default: return JSCrypto.hmacSha256(input, key)
            }
        }
        java?.setObject(hmacHex, forKeyedSubscript: "HMacHex" as NSCopying & NSObjectProtocol)

        /// `java.createSymmetricCrypto(transformation, key[, iv])` — object có `encryptBase64`,
        /// `decryptStr`, `encryptHex`.
        let createSymmetricCrypto: @convention(block) (String?, String?, String?) -> JSValue? = {
            transformation, key, iv in
            guard let context = java?.context else { return nil }
            let mode = LegadoCrypto.mode(from: transformation ?? "AES/CBC/PKCS5Padding")
            let keyData = (key ?? "").data(using: .utf8) ?? Data()
            let ivData = (iv?.isEmpty == false) ? iv?.data(using: .utf8) : nil
            return makeSymmetricCrypto(mode: mode, key: keyData, iv: ivData, in: context)
        }
        java?.setObject(
            createSymmetricCrypto,
            forKeyedSubscript: "createSymmetricCrypto" as NSCopying & NSObjectProtocol
        )

        let aesBase64DecodeToString: @convention(block) (String?, String?, String?, String?) -> String = {
            cipher, key, transformation, iv in
            guard let cipher, let data = Data(base64Encoded: cipher) else { return "" }
            let mode = LegadoCrypto.mode(from: transformation ?? "AES/CBC/PKCS5Padding")
            let keyData = (key ?? "").data(using: .utf8) ?? Data()
            let ivData = (iv?.isEmpty == false) ? iv?.data(using: .utf8) : nil
            guard let plain = LegadoCrypto.decrypt(data, key: keyData, iv: ivData, mode: mode) else {
                return ""
            }
            return String(data: plain, encoding: .utf8) ?? ""
        }
        java?.setObject(
            aesBase64DecodeToString,
            forKeyedSubscript: "aesBase64DecodeToString" as NSCopying & NSObjectProtocol
        )
        _ = runtime
    }

    private static func makeSymmetricCrypto(
        mode: LegadoCrypto.Mode,
        key: Data,
        iv: Data?,
        in context: JSContext
    ) -> JSValue? {
        let object = JSValue(newObjectIn: context)

        let encryptBase64: @convention(block) (String?) -> String = { plain in
            guard let plain, let data = plain.data(using: .utf8),
                  let cipher = LegadoCrypto.encrypt(data, key: key, iv: iv, mode: mode) else {
                return ""
            }
            return cipher.base64EncodedString()
        }
        object?.setObject(encryptBase64, forKeyedSubscript: "encryptBase64" as NSCopying & NSObjectProtocol)

        let encryptHex: @convention(block) (String?) -> String = { plain in
            guard let plain, let data = plain.data(using: .utf8),
                  let cipher = LegadoCrypto.encrypt(data, key: key, iv: iv, mode: mode) else {
                return ""
            }
            return LegadoCrypto.hexEncode(cipher)
        }
        object?.setObject(encryptHex, forKeyedSubscript: "encryptHex" as NSCopying & NSObjectProtocol)

        let decryptStr: @convention(block) (String?) -> String = { cipherText in
            guard let cipherText else { return "" }
            let data = Data(base64Encoded: cipherText) ?? LegadoCrypto.hexDecode(cipherText)
            guard let data,
                  let plain = LegadoCrypto.decrypt(data, key: key, iv: iv, mode: mode) else {
                return ""
            }
            return String(data: plain, encoding: .utf8) ?? ""
        }
        object?.setObject(decryptStr, forKeyedSubscript: "decryptStr" as NSCopying & NSObjectProtocol)
        return object
    }

    // MARK: - Base64 / hex / bytes

    internal static func installEncoding(_ java: JSValue?, runtime: LegadoJSRuntime) {
        let base64Decode: @convention(block) (String?, String?) -> String = { input, charset in
            guard let input, let data = Data(base64Encoded: paddedBase64(input)) else { return "" }
            return LegadoTextEncoding.decode(data, declaredCharset: charset)
        }
        java?.setObject(base64Decode, forKeyedSubscript: "base64Decode" as NSCopying & NSObjectProtocol)

        let base64Encode: @convention(block) (String?) -> String = { input in
            guard let input, let data = input.data(using: .utf8) else { return "" }
            return data.base64EncodedString()
        }
        java?.setObject(base64Encode, forKeyedSubscript: "base64Encode" as NSCopying & NSObjectProtocol)

        let hexDecodeToString: @convention(block) (String?) -> String = { input in
            guard let input, let data = LegadoCrypto.hexDecode(input) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        java?.setObject(hexDecodeToString, forKeyedSubscript: "hexDecodeToString" as NSCopying & NSObjectProtocol)

        let hexEncodeToString: @convention(block) (String?) -> String = { input in
            guard let input, let data = input.data(using: .utf8) else { return "" }
            return LegadoCrypto.hexEncode(data)
        }
        java?.setObject(hexEncodeToString, forKeyedSubscript: "hexEncodeToString" as NSCopying & NSObjectProtocol)

        let encodeURI: @convention(block) (String?, String?) -> String = { input, charset in
            guard let input else { return "" }
            return LegadoPercentEncoder.encode(input, charset: charset)
        }
        java?.setObject(encodeURI, forKeyedSubscript: "encodeURI" as NSCopying & NSObjectProtocol)

        let randomUUID: @convention(block) () -> String = {
            UUID().uuidString.lowercased()
        }
        java?.setObject(randomUUID, forKeyedSubscript: "randomUUID" as NSCopying & NSObjectProtocol)
        _ = runtime
    }

    /// Base64 trong nguồn hay thiếu `=` ở cuối; `Data(base64Encoded:)` thì bắt buộc đủ đệm.
    private static func paddedBase64(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "-", with: "+")
        text = text.replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder > 0 {
            text += String(repeating: "=", count: 4 - remainder)
        }
        return text
    }
}
