import Foundation

/// Nhãn hiển thị + bộ lựa chọn dùng chung cho `type` và `locale` của tiện ích.
///
/// Một chỗ duy nhất cho các chuỗi nhãn: trước 1.3.476 chúng nằm trong `FilterSheet.translateType` /
/// `translateLocale`, còn màn Cấu hình tiện ích cần **đúng** bộ nhãn đó cho hai select `type`/`locale` — hai
/// bản sao là hai chỗ để trôi khỏi nhau.
///
/// ## Bộ lựa chọn **không** bằng toàn bộ hằng của `ExtensionType`
/// Màn cấu hình chỉ cho chọn `novel` và `chinese_novel` (chủ dự án chốt 2026-10-07), nhưng `FilterSheet` liệt
/// kê theo tiện ích **đang cài** nên vẫn gặp `comic`, `tts`, `en_US`. Vì vậy:
/// - nhãn **phải** có nhánh dự phòng (`label(forType:)` / `label(forLocale:)` trả nguyên văn);
/// - `options(including:)` **phải** giữ lại giá trị lạ của file — nếu không, mở một tiện ích `type: "tts"`
///   sẽ thấy select không có mục nào khớp, và lần lưu kế tiếp là ghi đè mất giá trị thật.
///
/// `ExtensionType` là `enum` **không** `CaseIterable` (chỉ 4 hằng `static let`, `ExtensionType.swift:3-8`)
/// nên không có `allCases` để duyệt.
enum ExtensionDisplayCatalog {
    /// Bộ chọn ở màn Cấu hình tiện ích.
    static let typeOptions = [ExtensionType.novel, ExtensionType.chineseNovel]
    static let localeOptions = ["vi_VN", "zh_CN"]

    static func label(forType type: String) -> String {
        switch type {
        case ExtensionType.novel: return "Truyện chữ (Novel)"
        case ExtensionType.chineseNovel: return "Truyện Trung Quốc (Chinese)"
        case ExtensionType.comic: return "Truyện tranh (Comic)"
        case ExtensionType.tts: return "Giọng đọc (TTS)"
        default: return type.isEmpty ? "—" : type.capitalized
        }
    }

    static func label(forLocale locale: String) -> String {
        switch locale {
        case "vi_VN": return "Tiếng Việt"
        case "zh_CN": return "Tiếng Trung"
        case "en_US": return "Tiếng Anh"
        default: return locale.isEmpty ? "—" : locale
        }
    }

    /// Bộ lựa chọn, **cộng** `current` nếu nó chưa nằm trong bộ — để giá trị đang có trong file luôn chọn
    /// lại được, không bao giờ bị ghi mất chỉ vì nó không thuộc bộ mặc định.
    static func options(including current: String, from options: [String]) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !options.contains(trimmed) else { return options }
        return options + [trimmed]
    }
}
