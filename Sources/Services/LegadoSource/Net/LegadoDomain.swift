import Foundation

/// "Tên miền gốc" (gần đúng eTLD+1) để quyết định có gắn header đăng nhập cho một request không (spec §10.6, U42).
///
/// Không có danh sách hậu tố công cộng trong app nên dùng luật gần đúng: hai nhãn cuối, hoặc ba nhãn cuối khi TLD là mã
/// quốc gia hai chữ và nhãn kế cuối là hậu tố cấp hai phổ biến (`com.cn`, `co.uk`, `com.tw`, `ne.jp`…). Địa chỉ IP và
/// host một nhãn giữ nguyên.
enum LegadoDomain {
    private static let secondLevelSuffixes: Set<String> = [
        "com", "net", "org", "gov", "edu", "co", "ac", "ne", "or", "go", "mil", "info", "biz", "nom", "gen", "ltd", "plc"
    ]

    static func registrable(_ host: String) -> String {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        if trimmed.hasPrefix("[") || trimmed.allSatisfy({ $0.isNumber || $0 == "." }) { return trimmed }
        let labels = trimmed.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return trimmed }
        let tld = labels[labels.count - 1]
        let second = labels[labels.count - 2]
        let keep = tld.count == 2 && secondLevelSuffixes.contains(second) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }

    /// Hai URL có cùng tên miền gốc không (`false` khi một trong hai không có host).
    static func sameSite(_ first: String, _ second: String) -> Bool {
        guard let left = LegadoURLResolver.host(of: first), let right = LegadoURLResolver.host(of: second) else {
            return false
        }
        return registrable(left) == registrable(right)
    }
}
