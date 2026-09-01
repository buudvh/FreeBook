import Foundation
import CommonCrypto

/// Mã hoá đối xứng cho bridge JS của nguồn Legado (`java.createSymmetricCrypto`,
/// `java.aesBase64DecodeToString`…).
///
/// `JSCrypto` của repo đã có MD5/SHA/HMAC/Base64 nhưng **không có AES**, mà đo trên corpus thì
/// `createSymmetricCrypto` xuất hiện 44 lần và `aesBase64DecodeToString` 29 lần. Chỉ làm AES-CBC và
/// AES-ECB với PKCS#7 — hai biến thể duy nhất nguồn truyện dùng.
public enum LegadoCrypto {

    public enum Mode {
        case cbc
        case ecb
    }

    /// Phân tích chuỗi kiểu Java `AES/CBC/PKCS5Padding` → chế độ.
    public static func mode(from transformation: String) -> Mode {
        transformation.uppercased().contains("ECB") ? .ecb : .cbc
    }

    public static func encrypt(
        _ plain: Data,
        key: Data,
        iv: Data?,
        mode: Mode
    ) -> Data? {
        crypt(plain, key: key, iv: iv, mode: mode, operation: CCOperation(kCCEncrypt))
    }

    public static func decrypt(
        _ cipher: Data,
        key: Data,
        iv: Data?,
        mode: Mode
    ) -> Data? {
        crypt(cipher, key: key, iv: iv, mode: mode, operation: CCOperation(kCCDecrypt))
    }

    private static func crypt(
        _ input: Data,
        key: Data,
        iv: Data?,
        mode: Mode,
        operation: CCOperation
    ) -> Data? {
        guard !input.isEmpty, [16, 24, 32].contains(key.count) else { return nil }
        // IV phải được giữ sống trong suốt lời gọi `CCCrypt`, nên nó bọc ngoài cùng thay vì lấy
        // `baseAddress` rồi trả ra khỏi closure (con trỏ đó sẽ treo).
        if mode == .cbc, let iv, iv.count == kCCBlockSizeAES128 {
            return iv.withUnsafeBytes { ivBytes in
                run(input, key: key, ivPointer: ivBytes.baseAddress, mode: mode, operation: operation)
            }
        }
        return run(input, key: key, ivPointer: nil, mode: mode, operation: operation)
    }

    private static func run(
        _ input: Data,
        key: Data,
        ivPointer: UnsafeRawPointer?,
        mode: Mode,
        operation: CCOperation
    ) -> Data? {
        let options: CCOptions = mode == .ecb
            ? CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode)
            : CCOptions(kCCOptionPKCS7Padding)

        let capacity = input.count + kCCBlockSizeAES128
        var output = Data(count: capacity)
        var moved = 0

        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        options,
                        keyBytes.baseAddress,
                        key.count,
                        ivPointer,
                        inputBytes.baseAddress,
                        input.count,
                        outputBytes.baseAddress,
                        capacity,
                        &moved
                    )
                }
            }
        }

        guard status == kCCSuccess, moved <= capacity else { return nil }
        output.removeSubrange(moved..<output.count)
        return output
    }

    // MARK: - Tiện ích chuỗi

    public static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    public static func hexDecode(_ text: String) -> Data? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
