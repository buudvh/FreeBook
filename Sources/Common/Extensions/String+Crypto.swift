import Foundation
import CryptoKit

extension String {
    /// Băm chuỗi theo thuật toán MD5 và trả về chuỗi Hex.
    public func md5() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        return Self.lowercaseHex(Insecure.MD5.hash(data: data))
    }
    
    /// Băm chuỗi theo thuật toán SHA-256 và trả về chuỗi Hex.
    public func sha256() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        return Self.lowercaseHex(SHA256.hash(data: data))
    }

    /// Bảng 16 chữ số hex thường cho `lowercaseHex`.
    private static let lowercaseHexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    /// Hex thường, 2 ký tự mỗi byte — giống từng byte với `String(format: "%02hhx")` nối lại, nhưng tra bảng
    /// thay vì định dạng NSString cho mỗi byte (md5 nằm trong khoá của các memo dịch nóng, chạy mỗi dòng chương).
    private static func lowercaseHex<Bytes: Sequence>(_ digest: Bytes) -> String where Bytes.Element == UInt8 {
        var hex: [UInt8] = []
        hex.reserveCapacity(64)
        for byte in digest {
            hex.append(lowercaseHexDigits[Int(byte >> 4)])
            hex.append(lowercaseHexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: hex, as: UTF8.self)
    }
}
