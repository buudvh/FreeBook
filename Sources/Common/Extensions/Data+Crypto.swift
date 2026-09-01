import CryptoKit
import Foundation

extension Data {
    /// Băm dữ liệu nhị phân theo SHA-256 và trả về chuỗi Hex chữ thường.
    ///
    /// Tách khỏi `String.sha256()` vì snapshot nháp gửi qua debug server là **byte**, không phải chuỗi
    /// UTF-8: encode lại sang String trước khi băm sẽ làm hỏng checksum của file nhị phân.
    public func sha256Hex() -> String {
        SHA256.hash(data: self).map { String(format: "%02hhx", $0) }.joined()
    }
}
