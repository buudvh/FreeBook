import Foundation
import JavaScriptCore
import CryptoKit

/// Protocol định nghĩa các hàm mã hóa sẽ được export sang JavaScript.
/// Bằng cách kế thừa `JSExport`, JavaScriptCore sẽ tự động ánh xạ các phương thức tĩnh này
/// vào đối tượng toàn cục trong môi trường JS.
///
/// **Cách sử dụng trong JavaScript:**
/// ```javascript
/// var md5Hash = Crypto.md5("chuỗi_cần_băm");
/// var sha256Hash = Crypto.sha256("chuỗi_cần_băm");
/// var sha1Hash = Crypto.sha1("chuỗi_cần_băm");
/// ```
@objc protocol JSCryptoExport: JSExport {
    static func md5(_ input: String) -> String
    static func sha256(_ input: String) -> String
    static func sha1(_ input: String) -> String
    static func sha512(_ input: String) -> String
    static func base64Encode(_ input: String) -> String
    static func base64Decode(_ input: String) -> String
    static func hmacSha256(_ input: String, _ key: String) -> String
    static func hmacSha1(_ input: String, _ key: String) -> String
    static func hmacMd5(_ input: String, _ key: String) -> String
}

/// Lớp triển khai thực tế các hàm mã hóa native sử dụng `CryptoKit` của Apple (hiệu năng cao).
/// Lớp này được đăng ký trong `JSExecutor.swift` dưới tên biến toàn cục `"Crypto"`.
@objc public final class JSCrypto: NSObject, JSCryptoExport {
    
    /// Băm chuỗi đầu vào theo thuật toán MD5 và trả về chuỗi Hex.
    public static func md5(_ input: String) -> String {
        return input.md5()
    }
    
    /// Băm chuỗi đầu vào theo thuật toán SHA-256 và trả về chuỗi Hex.
    public static func sha256(_ input: String) -> String {
        return input.sha256()
    }

    /// Băm chuỗi đầu vào theo thuật toán SHA-1 và trả về chuỗi Hex.
    public static func sha1(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Băm chuỗi đầu vào theo thuật toán SHA-512 và trả về chuỗi Hex.
    public static func sha512(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = SHA512.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Mã hóa chuỗi sang định dạng Base64.
    public static func base64Encode(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        return data.base64EncodedString()
    }

    /// Giải mã chuỗi từ định dạng Base64.
    public static func base64Decode(_ input: String) -> String {
        guard let data = Data(base64Encoded: input) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Tính HMAC-SHA256 của chuỗi với khóa bí mật.
    public static func hmacSha256(_ input: String, _ key: String) -> String {
        guard let keyData = key.data(using: .utf8), let msgData = input.data(using: .utf8) else { return "" }
        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<SHA256>.authenticationCode(for: msgData, using: symmetricKey)
        return mac.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Tính HMAC-SHA1 của chuỗi với khóa bí mật.
    public static func hmacSha1(_ input: String, _ key: String) -> String {
        guard let keyData = key.data(using: .utf8), let msgData = input.data(using: .utf8) else { return "" }
        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: msgData, using: symmetricKey)
        return mac.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Tính HMAC-MD5 của chuỗi với khóa bí mật.
    public static func hmacMd5(_ input: String, _ key: String) -> String {
        guard let keyData = key.data(using: .utf8), let msgData = input.data(using: .utf8) else { return "" }
        let symmetricKey = SymmetricKey(data: keyData)
        let mac = HMAC<Insecure.MD5>.authenticationCode(for: msgData, using: symmetricKey)
        return mac.map { String(format: "%02hhx", $0) }.joined()
    }
}
