import Foundation
import CryptoKit

/// Băm, base64, hex, byte↔chuỗi, `encodeURI`, mã hoá đối xứng (spec §6.4.3). Byte qua ranh giới JS là hex.
extension LegadoJSRuntime {
    func nativeCrypto(_ command: String, _ arguments: LegadoJSArguments) throws -> String? {
        switch command {
        case "md5":
            return Self.hex(Data(Insecure.MD5.hash(data: bytes(of: arguments[0]) ?? Data())))
        case "md5_16":
            let full = Self.hex(Data(Insecure.MD5.hash(data: bytes(of: arguments[0]) ?? Data())))
            let start = full.index(full.startIndex, offsetBy: 8)
            let end = full.index(start, offsetBy: 16)
            return String(full[start..<end])
        case "b64enc":
            return Self.base64Encode(bytes(of: arguments[0]) ?? Data(), flags: arguments.int(1))
        case "b64dec":
            let data = Self.base64Decode(text(of: arguments[0]), flags: arguments.int(1))
            let charset = arguments.number(1) == nil ? arguments.plainString(1) : nil
            return LegadoCharset.string(from: data, encoding: LegadoCharset.encoding(named: charset) ?? .utf8)
        case "b64decBytes":
            return Self.hex(Self.base64Decode(text(of: arguments[0]), flags: arguments.int(1)))
        case "hexDecStr":
            return String(decoding: Self.bytes(fromHex: text(of: arguments[0])), as: UTF8.self)
        case "hexEnc":
            return Self.hex(bytes(of: arguments[0]) ?? Data())
        case "strToBytes":
            let encoding = LegadoCharset.encoding(named: arguments.plainString(1)) ?? .utf8
            return Self.hex(Data(LegadoCharset.bytes(of: text(of: arguments[0]), encoding: encoding)))
        case "bytesToStr":
            let encoding = LegadoCharset.encoding(named: arguments.plainString(1)) ?? .utf8
            return LegadoCharset.string(from: bytes(of: arguments[0]) ?? Data(), encoding: encoding)
        case "encodeURI":
            let encoding = LegadoCharset.requestEncoding(named: arguments.plainString(1))
            return LegadoURLEncoder.encodeComponent(text(of: arguments[0]), encoding: encoding)
        case "digest":
            let digest = try Self.digest(bytes(of: arguments[0]) ?? Data(), algorithm: text(of: arguments[1]))
            return text(of: arguments[2]) == "b64" ? digest.base64EncodedString() : Self.hex(digest)
        case "hmac":
            let mac = try Self.hmac(bytes(of: arguments[0]) ?? Data(), algorithm: text(of: arguments[1]),
                                    key: bytes(of: arguments[2]) ?? Data())
            return text(of: arguments[3]) == "b64" ? mac.base64EncodedString() : Self.hex(mac)
        case "sym":
            return try symmetric(arguments)
        default:
            return nil
        }
    }

    /// `['enc'|'dec', biến-đổi, khoá, iv, dữ-liệu, 'hex'|'str'|'b64']`.
    private func symmetric(_ arguments: LegadoJSArguments) throws -> String {
        let transformation = text(of: arguments[1])
        let key = bytes(of: arguments[2]) ?? Data()
        let iv = arguments.isNull(3) ? nil : bytes(of: arguments[3])
        let isEncrypt = text(of: arguments[0]) == "enc"
        let input: Data
        if isEncrypt || isByteArray(arguments[4]) {
            input = bytes(of: arguments[4]) ?? Data()
        } else {
            input = Self.decodeCipherText(text(of: arguments[4]))
        }
        let output: Data
        if LegadoAESGCM.isGCM(transformation) {
            // AES/GCM (spec §14.4): IV là nonce, thẻ 128 bit nằm cuối dữ liệu.
            let nonce = iv ?? Data()
            if isEncrypt {
                output = try LegadoAESGCM.encrypt(input, key: key, nonce: nonce)
            } else {
                output = try LegadoAESGCM.decrypt(input, key: key, nonce: nonce)
            }
        } else {
            let cipher = try LegadoSymmetricCipher(transformation: transformation)
            if isEncrypt {
                output = try cipher.encrypt(input, key: key, iv: iv)
            } else {
                output = try cipher.decrypt(input, key: key, iv: iv)
            }
        }
        switch text(of: arguments[5]) {
        case "str": return String(decoding: output, as: UTF8.self)
        case "b64": return output.base64EncodedString()
        default: return Self.hex(output)
        }
    }

    /// Dữ liệu giải mã dạng chuỗi: chỉ gồm ký tự hex và độ dài chẵn ⇒ hex, còn lại base64 (U25).
    static func decodeCipherText(_ text: String) -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.count % 2 == 0, trimmed.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) {
            return Data(bytes(fromHex: trimmed))
        }
        return base64Decode(trimmed, flags: nil)
    }

    // MARK: - Base64 (cờ kiểu Android: NO_PADDING 1, NO_WRAP 2, CRLF 4, URL_SAFE 8)

    static func base64Encode(_ data: Data, flags: Int?) -> String {
        var text = data.base64EncodedString()
        guard let flags else { return text }
        if flags & 8 != 0 {
            text = text.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        if flags & 1 != 0 {
            while text.hasSuffix("=") { text.removeLast() }
        }
        if flags & 2 == 0 {
            let separator = flags & 4 != 0 ? "\r\n" : "\n"
            var lines: [String] = []
            var remaining = Substring(text)
            while !remaining.isEmpty {
                lines.append(String(remaining.prefix(76)))
                remaining = remaining.dropFirst(76)
            }
            text = lines.joined(separator: separator) + separator
        }
        return text
    }

    /// Giải base64 khoan dung: bỏ khoảng trắng, nhận cả bảng chữ URL-safe, tự thêm `=`.
    static func base64Decode(_ text: String, flags: Int?) -> Data {
        var cleaned = text.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while cleaned.hasSuffix("=") { cleaned.removeLast() }
        let remainder = cleaned.count % 4
        if remainder == 1 { cleaned.removeLast() }
        if remainder > 1 { cleaned += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: cleaned) ?? Data()
    }

    // MARK: - Băm

    static func digest(_ data: Data, algorithm: String) throws -> Data {
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "MD5": return Data(Insecure.MD5.hash(data: data))
        case "SHA1", "SHA": return Data(Insecure.SHA1.hash(data: data))
        case "SHA256": return Data(SHA256.hash(data: data))
        case "SHA384": return Data(SHA384.hash(data: data))
        case "SHA512": return Data(SHA512.hash(data: data))
        default: throw LegadoJSNativeError.unsupported("thuật toán băm \(algorithm)")
        }
    }

    static func hmac(_ data: Data, algorithm: String, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch algorithm.uppercased().replacingOccurrences(of: "-", with: "") {
        case "HMACMD5": return Data(HMAC<Insecure.MD5>.authenticationCode(for: data, using: symmetricKey))
        case "HMACSHA1": return Data(HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symmetricKey))
        case "HMACSHA256": return Data(HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        case "HMACSHA384": return Data(HMAC<SHA384>.authenticationCode(for: data, using: symmetricKey))
        case "HMACSHA512": return Data(HMAC<SHA512>.authenticationCode(for: data, using: symmetricKey))
        default: throw LegadoJSNativeError.unsupported("HMAC \(algorithm)")
        }
    }
}
