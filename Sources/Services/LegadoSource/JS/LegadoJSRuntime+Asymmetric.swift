import Foundation

/// Phía Swift của RSA / chữ ký (spec §14.3) và AES-GCM (§14.4) cho `java.createAsymmetricCrypto`, `java.createSign`,
/// `Cipher`/`Signature`/`GCMParameterSpec` giả lập. Byte qua ranh giới JS là hex.
extension LegadoJSRuntime {
    func nativeAsymmetric(_ command: String, _ arguments: LegadoJSArguments) throws -> String? {
        switch command {
        case "rsa":
            // [op 'enc'|'dec', biến-đổi, khoá-công-khai, khoá-riêng, dùng-khoá-công-khai, dữ-liệu, 'hex'|'str'|'b64']
            let transformation = text(of: arguments[1])
            var usePublic = arguments.bool(4)
            let publicData = rsaKeyData(arguments[2])
            let privateData = rsaKeyData(arguments[3])
            if usePublic, publicData == nil, privateData != nil { usePublic = false }
            if !usePublic, privateData == nil, publicData != nil { usePublic = true }
            guard let keyData = usePublic ? publicData : privateData else {
                throw LegadoJSNativeError("Chưa đặt khoá RSA")
            }
            let key = try usePublic ? LegadoRSA.publicKey(keyData) : LegadoRSA.privateKey(keyData)
            let output: Data
            if text(of: arguments[0]) == "enc" {
                output = try LegadoRSA.encrypt(bytes(of: arguments[5]) ?? Data(), transformation: transformation, key: key,
                                               isPublicKey: usePublic)
            } else {
                let input = isByteArray(arguments[5]) ? (bytes(of: arguments[5]) ?? Data())
                    : Self.decodeCipherText(text(of: arguments[5]))
                output = try LegadoRSA.decrypt(input, transformation: transformation, key: key, isPublicKey: usePublic)
            }
            return Self.encodeOutput(output, as: text(of: arguments[6]))
        case "rsaSign":
            guard let keyData = rsaKeyData(arguments[1]) else { throw LegadoJSNativeError("Chưa đặt khoá riêng để ký") }
            let signature = try LegadoRSA.sign(bytes(of: arguments[2]) ?? Data(), algorithm: text(of: arguments[0]),
                                               key: LegadoRSA.privateKey(keyData))
            return Self.hex(signature)
        case "rsaVerify":
            guard let keyData = rsaKeyData(arguments[1]) else { throw LegadoJSNativeError("Chưa đặt khoá công khai để kiểm") }
            let valid = try LegadoRSA.verify(bytes(of: arguments[2]) ?? Data(), signature: bytes(of: arguments[3]) ?? Data(),
                                             algorithm: text(of: arguments[0]), key: LegadoRSA.publicKey(keyData))
            return valid ? "1" : ""
        case "gcm":
            // [op, khoá, nonce, số-bit-thẻ, dữ-liệu]
            let key = bytes(of: arguments[1]) ?? Data()
            let nonce = bytes(of: arguments[2]) ?? Data()
            let tagBits = arguments.int(3) ?? 128
            let data = bytes(of: arguments[4]) ?? Data()
            let output: Data
            if text(of: arguments[0]) == "enc" {
                output = try LegadoAESGCM.encrypt(data, key: key, nonce: nonce, tagBits: tagBits)
            } else {
                output = try LegadoAESGCM.decrypt(data, key: key, nonce: nonce, tagBits: tagBits)
            }
            return Self.hex(output)
        default:
            return nil
        }
    }

    /// Khoá RSA từ đối số: mảng byte (DER) giữ nguyên; chuỗi PEM ⇒ bóc dòng `-----…` rồi giải base64; chuỗi trông như
    /// base64 ⇒ giải base64; còn lại ⇒ byte UTF-8 (U59). `null` ⇒ `nil`.
    func rsaKeyData(_ descriptor: LegadoEngineJSON) -> Data? {
        if descriptor.isNull { return nil }
        if isByteArray(descriptor) { return bytes(of: descriptor) }
        let text = text(of: descriptor).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("-----BEGIN") {
            let body = text.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
            return Self.base64Decode(body, flags: nil)
        }
        let compact = text.filter { !$0.isWhitespace }
        let base64Characters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
        if compact.unicodeScalars.allSatisfy({ base64Characters.contains($0) }) {
            let decoded = Self.base64Decode(compact, flags: nil)
            if !decoded.isEmpty { return decoded }
        }
        return Data(text.utf8)
    }

    static func encodeOutput(_ data: Data, as format: String) -> String {
        switch format {
        case "str": return String(decoding: data, as: UTF8.self)
        case "b64": return data.base64EncodedString()
        default: return hex(data)
        }
    }
}
