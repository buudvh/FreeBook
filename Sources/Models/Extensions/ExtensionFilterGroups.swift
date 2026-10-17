import Foundation

/// Nhóm **thể loại** và **ngôn ngữ** của tiện ích cho bộ lọc kho, hàng chip Khám phá/Tìm kiếm và nhãn/cờ trên
/// từng dòng của kho.
///
/// Registry thật (trang danh mục tiện ích cộng đồng, 736 tiện ích) có nhiều biến thể chính tả cho cùng một ý: `zh_CN`/`zh-CN`,
/// `vi_VN`/`vi-VN`/`vi`/`vn_VI`, `novel`/`eng_novel`/`novel,comic`… So khớp giá trị thô làm mỗi biến thể thành
/// một chip riêng. Mọi chỗ cần gom phải đi qua hai hàm `typeGroup(for:)` / `localeGroup(for:)` dưới đây.
///
/// ## Bất biến
/// - Hàm nhóm **lũy đẳng**: `typeGroup(for: typeGroup(for: x)) == typeGroup(for: x)` (tương tự với ngôn ngữ).
///   `ExtensionFilterSelection.decode` ánh xạ lại lựa chọn đã lưu mỗi lần đọc, nên khoá nhóm phải tự ánh xạ
///   về chính nó.
/// - `novel`/`text` được xét **trước** `comic` để `"novel,comic"` thuộc nhóm truyện chữ.
/// - Ngôn ngữ so **tiền tố** sau khi chuẩn hoá (chữ thường, trim, `-` → `_`). trang danh mục cộng đồng so khớp đúng `ja`/`kr`
///   nên `ja_JP`/`kr_KR` của họ rơi vào "Khác"; ở đây sửa lỗi đó.
///
/// Màn Cấu hình tiện ích **không** dùng nhóm: nó vẫn chọn giá trị thô qua `ExtensionDisplayCatalog`.
enum ExtensionFilterGroups {
    // MARK: - Thể loại

    static let novelGroup = "novel"
    static let comicGroup = "comic"
    static let videoGroup = "video"
    static let otherGroup = "other"

    /// Thứ tự cố định của chip thể loại.
    static let typeGroupOrder = [novelGroup, comicGroup, videoGroup, "audio", "tts", "translate", "tool", "ai", otherGroup]

    /// Giá trị `type` thô → khoá nhóm. Rỗng ⇒ `novel` (hợp đồng extension coi thiếu `metadata.type` là novel).
    static func typeGroup(for rawType: String) -> String {
        let value = rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value.contains("novel") || value.contains("text") { return novelGroup }
        if value.contains("comic") || value.contains("image") { return comicGroup }
        if value.contains("video") || value == "phim" { return videoGroup }
        if value == "audio" || value == "music" { return "audio" }
        if value == "tts" { return "tts" }
        if value.contains("trans") || value.contains("dịch") { return "translate" }
        if value == "tool" || value == "tools" { return "tool" }
        if value == "ai" { return "ai" }
        return otherGroup
    }

    static func typeGroupLabel(_ group: String) -> String {
        switch group {
        case novelGroup: return "Truyện chữ"
        case comicGroup: return "Truyện tranh"
        case videoGroup: return "Phim/Video"
        case "audio": return "Âm thanh"
        case "tts": return "Giọng đọc (TTS)"
        case "translate": return "Dịch thuật"
        case "tool": return "Công cụ"
        case "ai": return "AI"
        default: return "Khác"
        }
    }

    /// SF Symbol đại diện nhóm — icon dự phòng của dòng tiện ích chưa có ảnh.
    static func typeGroupSymbol(_ group: String) -> String {
        switch group {
        case comicGroup: return "photo.on.rectangle"
        case videoGroup: return "play.rectangle"
        case "audio": return "music.note"
        case "tts": return "waveform"
        case "translate": return "character.bubble"
        case "tool": return "wrench.and.screwdriver"
        case "ai": return "sparkles"
        default: return "book.closed"
        }
    }

    // MARK: - Ngôn ngữ

    /// Thứ tự cố định của chip ngôn ngữ.
    static let localeGroupOrder = ["vi", "zh", "en", "ja", "ko", otherGroup]

    /// Mã `locale` thô → khoá nhóm.
    static func localeGroup(for rawLocale: String) -> String {
        let value = rawLocale
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        if value.hasPrefix("vi") || value.hasPrefix("vn") { return "vi" }
        if value.hasPrefix("zh") { return "zh" }
        if value.hasPrefix("en") || value == "global" { return "en" }
        if value.hasPrefix("ja") || value.hasPrefix("jp") { return "ja" }
        if value.hasPrefix("ko") || value.hasPrefix("kr") { return "ko" }
        return otherGroup
    }

    static func localeGroupLabel(_ group: String) -> String {
        switch group {
        case "vi": return "Tiếng Việt"
        case "zh": return "Tiếng Trung"
        case "en": return "Tiếng Anh"
        case "ja": return "Tiếng Nhật"
        case "ko": return "Tiếng Hàn"
        default: return "Khác"
        }
    }

    static func localeGroupFlag(_ group: String) -> String {
        switch group {
        case "vi": return "🇻🇳"
        case "zh": return "🇨🇳"
        case "en": return "🇺🇸"
        case "ja": return "🇯🇵"
        case "ko": return "🇰🇷"
        default: return "🌐"
        }
    }

    // MARK: - Đếm cho chip

    /// Số tiện ích theo từng nhóm thể loại.
    static func typeGroupCounts(_ extensions: [Extension]) -> [String: Int] {
        extensions.reduce(into: [:]) { counts, ext in counts[typeGroup(for: ext.type), default: 0] += 1 }
    }

    /// Số tiện ích theo từng nhóm ngôn ngữ.
    static func localeGroupCounts(_ extensions: [Extension]) -> [String: Int] {
        extensions.reduce(into: [:]) { counts, ext in counts[localeGroup(for: ext.locale), default: 0] += 1 }
    }

    /// Các khoá của `order` có ít nhất một tiện ích, giữ đúng thứ tự cố định.
    static func presentGroups(_ order: [String], counts: [String: Int]) -> [String] {
        order.filter { (counts[$0] ?? 0) > 0 }
    }
}
