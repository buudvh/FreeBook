import Foundation

/// Chữ gõ ở ô địa chỉ của trình duyệt người dùng ⇒ URL để nạp: **link** thì mở thẳng, chữ thường thì tìm Google
/// (`BypassBrowserTabStore.webSearchURL(for:)`, cùng chỗ với mục "Tìm trên web" của menu bôi đen).
///
/// Coi là link khi: có `http://`/`https://` (và `URL` dựng được), hoặc không có khoảng trắng và tên máy là `localhost`,
/// địa chỉ IPv4, hoặc tên miền có dấu chấm với phần đuôi ≥ 2 chữ cái (`truyen.com`, `m.abc.vn/book/1`, `abc.com:8080`).
/// Ngược lại (`đấu phá thương khung`, `abc`, `1.5`) ⇒ tìm kiếm.
enum BrowserAddressInputMapper {
    static func url(for input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return addressURL(from: text) ?? BypassBrowserTabStore.webSearchURL(for: text)
    }

    /// URL khi `text` là link; `nil` khi nên tìm kiếm.
    static func addressURL(from text: String) -> URL? {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return URL(string: text)
        }
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: "https://" + text),
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host == "localhost" || isIPv4(host) || isDomainName(host) ? url : nil
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            guard let value = Int(part) else { return false }
            return (0...255).contains(value)
        }
    }

    private static func isDomainName(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let tld = labels.last else { return false }
        // Đuôi dạng punycode (`xn--…`) của tên miền quốc tế vẫn tính là tên miền.
        return tld.hasPrefix("xn--") || (tld.count >= 2 && tld.allSatisfy(\.isLetter))
    }
}
