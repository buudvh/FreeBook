import Foundation

/// Công tắc "DNS mã hoá" + máy chủ đã chọn (Cài đặt › Chung › Mạng & DNS, 1.3.825), mặc định **bật** với Cloudflare.
///
/// Một nguồn cho khoá + giá trị mặc định như `VideoAutoNextPolicy`: View đọc bằng
/// `@AppStorage(EncryptedDNSPolicy.enabledKey)` với `= EncryptedDNSPolicy.defaultEnabled` (và `resolverKey` với
/// `defaultResolver`), tầng nền đọc `isEnabled` / `resolver` (`UserDefaults.bool` trả `false` cho khoá chưa ghi).
/// Khoá không có dấu chấm (`@AppStorage` theo dõi bằng KVO). Người áp lên mạng là `EncryptedDNSRepository`.
enum EncryptedDNSPolicy {
    static let enabledKey = "encryptedDnsEnabled"
    static let defaultEnabled = true
    static let resolverKey = "encryptedDnsResolver"
    static let defaultResolver = EncryptedDNSResolver.cloudflare
    /// Lượt dò gần nhất lỗi (đã lùi về DNS thường) ⇒ lần mở app sau khởi động bằng DNS thường, dò xong mới bật —
    /// mạng chặn DoH (Wi-Fi công ty…) khỏi làm hỏng các request đầu tiên của mỗi lần mở app.
    static let lastProbeFailedKey = "encryptedDnsLastProbeFailed"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled
    }

    static var resolver: EncryptedDNSResolver {
        UserDefaults.standard.string(forKey: resolverKey).flatMap(EncryptedDNSResolver.init(rawValue:)) ?? defaultResolver
    }

    static var lastProbeFailed: Bool {
        get { UserDefaults.standard.bool(forKey: lastProbeFailedKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastProbeFailedKey) }
    }
}
