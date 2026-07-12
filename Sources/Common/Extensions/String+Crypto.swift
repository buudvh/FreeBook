import Foundation
import CryptoKit

extension String {
    /// Băm chuỗi theo thuật toán MD5 và trả về chuỗi Hex.
    public func md5() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Băm chuỗi theo thuật toán SHA-256 và trả về chuỗi Hex.
    public func sha256() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
