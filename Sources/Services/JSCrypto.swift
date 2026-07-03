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
/// ```
@objc protocol JSCryptoExport: JSExport {
    static func md5(_ input: String) -> String
    static func sha256(_ input: String) -> String
}

/// Lớp triển khai thực tế các hàm mã hóa native sử dụng `CryptoKit` của Apple (hiệu năng cao).
/// Lớp này được đăng ký trong `JSExecutor.swift` dưới tên biến toàn cục `"Crypto"`.
@objc public final class JSCrypto: NSObject, JSCryptoExport {
    
    /// Băm chuỗi đầu vào theo thuật toán MD5 và trả về chuỗi Hex.
    public static func md5(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Băm chuỗi đầu vào theo thuật toán SHA-256 và trả về chuỗi Hex.
    public static func sha256(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

