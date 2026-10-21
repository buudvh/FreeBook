import Foundation
import Security
import CryptoKit

/// RSA cho `java.createAsymmetricCrypto`, `java.createSign`, `Cipher`/`Signature` RSA (spec §14.3), trên Security.framework.
///
/// - Biến đổi: `RSA` ≡ `RSA/ECB/PKCS1Padding`; `…OAEP…` ⇒ OAEP (SHA-1, hoặc SHA-256 khi tên có `SHA-256`);
///   `…/NoPadding` ⇒ RSA thô; khác ⇒ lỗi.
/// - Khoá công khai: DER `SubjectPublicKeyInfo` hoặc PKCS#1; khoá riêng: DER PKCS#8 hoặc PKCS#1 (PEM đã bóc ở lớp gọi).
/// - "Giải bằng khoá công khai" (bên kia mã bằng khoá riêng) và "mã bằng khoá riêng": Security.framework không có sẵn ⇒
///   dùng phép RSA thô (`rsaEncryptionRaw`: mũ khoá công khai; giải thô bằng khoá riêng: mũ khoá riêng) + tự thêm/bỏ
///   đệm PKCS#1 v1.5 **kiểu 1**.
/// - Dữ liệu dài: giải theo khối `k` byte, mã theo khối `k − 11` (PKCS#1) / `k − 42` (OAEP SHA-1) (U59).
enum LegadoRSA {
    enum Padding {
        case pkcs1
        case oaepSHA1
        case oaepSHA256
        case none
    }

    static func padding(for transformation: String) throws -> Padding {
        let upper = transformation.uppercased().replacingOccurrences(of: " ", with: "")
        if upper.contains("OAEP") { return upper.contains("SHA-256") || upper.contains("SHA256") ? .oaepSHA256 : .oaepSHA1 }
        if upper == "RSA" || upper.contains("PKCS1") { return .pkcs1 }
        if upper.hasSuffix("NOPADDING") { return .none }
        throw LegadoJSNativeError.unsupported("biến đổi RSA \(transformation)")
    }

    // MARK: - Khoá

    static func publicKey(_ raw: Data) throws -> SecKey {
        try makeKey(LegadoDER.pkcs1PublicKey(raw), keyClass: kSecAttrKeyClassPublic)
    }

    static func privateKey(_ raw: Data) throws -> SecKey {
        try makeKey(LegadoDER.pkcs1PrivateKey(raw), keyClass: kSecAttrKeyClassPrivate)
    }

    private static func makeKey(_ data: Data, keyClass: CFString) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: keyClass
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "không rõ"
            throw LegadoJSNativeError("Khoá RSA không hợp lệ: \(reason)")
        }
        return key
    }

    // MARK: - Mã hoá / giải mã

    static func encrypt(_ data: Data, transformation: String, key: SecKey, isPublicKey: Bool) throws -> Data {
        let padding = try padding(for: transformation)
        let size = SecKeyGetBlockSize(key)
        guard size > 11 else { throw LegadoJSNativeError("Khoá RSA quá ngắn") }
        if !isPublicKey {
            // "Mã bằng khoá riêng": đệm kiểu 1 rồi mũ khoá riêng (giải thô).
            var output = Data()
            for chunk in chunks(data, size: size - 11) {
                let block = typeOnePadded(chunk, size: size)
                let piece = try run(SecKeyCreateDecryptedData, key, .rsaEncryptionRaw, block, size)
                output.append(piece)
            }
            return output
        }
        let algorithm: SecKeyAlgorithm
        let chunkSize: Int
        switch padding {
        case .pkcs1: algorithm = .rsaEncryptionPKCS1; chunkSize = size - 11
        case .oaepSHA1: algorithm = .rsaEncryptionOAEPSHA1; chunkSize = size - 42
        case .oaepSHA256: algorithm = .rsaEncryptionOAEPSHA256; chunkSize = size - 66
        case .none: algorithm = .rsaEncryptionRaw; chunkSize = size
        }
        guard chunkSize > 0 else { throw LegadoJSNativeError("Khoá RSA quá ngắn cho đệm này") }
        var output = Data()
        for chunk in chunks(data, size: chunkSize) {
            let block = padding == .none ? leftPadded(chunk, size: size) : chunk
            let piece = try run(SecKeyCreateEncryptedData, key, algorithm, block, nil)
            output.append(piece)
        }
        return output
    }

    static func decrypt(_ data: Data, transformation: String, key: SecKey, isPublicKey: Bool) throws -> Data {
        let padding = try padding(for: transformation)
        let size = SecKeyGetBlockSize(key)
        guard size > 0 else { throw LegadoJSNativeError("Khoá RSA không hợp lệ") }
        var output = Data()
        for chunk in chunks(data, size: size) {
            let block = leftPadded(chunk, size: size)
            if isPublicKey {
                // "Giải bằng khoá công khai": mũ khoá công khai (mã thô) rồi bỏ đệm kiểu 1.
                let raw = try run(SecKeyCreateEncryptedData, key, .rsaEncryptionRaw, block, size)
                output.append(padding == .none ? raw : stripPadding(raw))
                continue
            }
            let algorithm: SecKeyAlgorithm
            switch padding {
            case .pkcs1: algorithm = .rsaEncryptionPKCS1
            case .oaepSHA1: algorithm = .rsaEncryptionOAEPSHA1
            case .oaepSHA256: algorithm = .rsaEncryptionOAEPSHA256
            case .none: algorithm = .rsaEncryptionRaw
            }
            let piece = try run(SecKeyCreateDecryptedData, key, algorithm, block, nil)
            output.append(piece)
        }
        return output
    }

    // MARK: - Chữ ký

    static func sign(_ data: Data, algorithm name: String, key: SecKey) throws -> Data {
        let (algorithm, input) = try signatureInput(data, algorithm: name)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm, input as CFData, &error) else {
            throw LegadoJSNativeError("Ký RSA thất bại: \(error?.takeRetainedValue().localizedDescription ?? "không rõ")")
        }
        return signature as Data
    }

    static func verify(_ data: Data, signature: Data, algorithm name: String, key: SecKey) throws -> Bool {
        let (algorithm, input) = try signatureInput(data, algorithm: name)
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(key, algorithm, input as CFData, signature as CFData, &error)
    }

    /// `SHA256withRSA`, `SHA1withRSA`, `SHA384/512/224withRSA`; `MD5withRSA` tự dựng `DigestInfo` (Security.framework
    /// không có thuật toán MD5).
    private static func signatureInput(_ data: Data, algorithm name: String) throws -> (SecKeyAlgorithm, Data) {
        switch name.uppercased().replacingOccurrences(of: "-", with: "") {
        case "SHA256WITHRSA": return (.rsaSignatureMessagePKCS1v15SHA256, data)
        case "SHA1WITHRSA": return (.rsaSignatureMessagePKCS1v15SHA1, data)
        case "SHA384WITHRSA": return (.rsaSignatureMessagePKCS1v15SHA384, data)
        case "SHA512WITHRSA": return (.rsaSignatureMessagePKCS1v15SHA512, data)
        case "SHA224WITHRSA": return (.rsaSignatureMessagePKCS1v15SHA224, data)
        case "MD5WITHRSA":
            let prefix: [UInt8] = [0x30, 0x20, 0x30, 0x0C, 0x06, 0x08, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x02, 0x05,
                                   0x05, 0x00, 0x04, 0x10]
            var digestInfo = Data(prefix)
            digestInfo.append(contentsOf: Insecure.MD5.hash(data: data))
            return (.rsaSignatureDigestPKCS1v15Raw, digestInfo)
        default:
            throw LegadoJSNativeError.unsupported("thuật toán ký \(name)")
        }
    }

    // MARK: - Tiện ích

    private typealias Operation = (SecKey, SecKeyAlgorithm, CFData, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> CFData?

    private static func run(_ operation: Operation, _ key: SecKey, _ algorithm: SecKeyAlgorithm, _ input: Data,
                            _ outputSize: Int?) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let result = operation(key, algorithm, input as CFData, &error) else {
            throw LegadoJSNativeError("RSA thất bại: \(error?.takeRetainedValue().localizedDescription ?? "không rõ")")
        }
        let data = result as Data
        if let outputSize { return leftPadded(data, size: outputSize) }
        return data
    }

    static func chunks(_ data: Data, size: Int) -> [Data] {
        guard size > 0, !data.isEmpty else { return data.isEmpty ? [] : [data] }
        var output: [Data] = []
        var start = data.startIndex
        while start < data.endIndex {
            let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            output.append(Data(data[start..<end]))
            start = end
        }
        return output
    }

    private static func leftPadded(_ data: Data, size: Int) -> Data {
        guard data.count < size else { return data }
        return Data(repeating: 0, count: size - data.count) + data
    }

    /// `00 01 FF…FF 00 dữ-liệu` (đệm PKCS#1 v1.5 kiểu 1) dài đúng `size`.
    private static func typeOnePadded(_ chunk: Data, size: Int) -> Data {
        var block = Data([0x00, 0x01])
        block.append(Data(repeating: 0xFF, count: max(8, size - 3 - chunk.count)))
        block.append(0x00)
        block.append(chunk)
        return block
    }

    /// Bỏ đệm PKCS#1 v1.5 (kiểu 1 hoặc 2): dữ liệu nằm sau byte `00` đầu tiên kể từ vị trí 2.
    private static func stripPadding(_ block: Data) -> Data {
        let bytes = [UInt8](block)
        guard bytes.count > 2, bytes[0] == 0x00, bytes[1] == 0x01 || bytes[1] == 0x02,
              let separator = bytes[2...].firstIndex(of: 0x00) else { return block }
        return Data(bytes[(separator + 1)...])
    }
}
