import Foundation

/// Nhãn hiển thị + bộ lựa chọn cho **giá trị thô** `type` và `locale` của tiện ích (màn Cấu hình tiện ích).
///
/// Bộ lọc kho, hàng chip Khám phá/Tìm kiếm và nhãn/cờ trên dòng kho **không** dùng type này mà dùng nhóm
/// `ExtensionFilterGroups` (gom các biến thể chính tả như `zh_CN`/`zh-CN`).
///
/// Một chỗ duy nhất cho các chuỗi nhãn: trước 1.3.476 chúng nằm trong `FilterSheet.translateType` /
/// `translateLocale`, còn màn Cấu hình tiện ích cần **đúng** bộ nhãn đó cho hai select `type`/`locale` — hai
/// bản sao là hai chỗ để trôi khỏi nhau.
///
/// ## Bộ lựa chọn **không** bằng toàn bộ hằng của `ExtensionType`
/// Màn cấu hình chỉ cho chọn `novel` và `chinese_novel` (chủ dự án chốt 2026-10-07), nhưng file `plugin.json`
/// của tiện ích đã cài vẫn có thể mang `comic`, `video`, `tts`, `en_US`. Vì vậy:
/// - nhãn **phải** có nhánh dự phòng (`label(forType:)` / `label(forLocale:)` trả nguyên văn);
/// - `options(including:)` **phải** giữ lại giá trị lạ của file — nếu không, mở một tiện ích `type: "tts"`
///   sẽ thấy select không có mục nào khớp, và lần lưu kế tiếp là ghi đè mất giá trị thật.
///
/// `ExtensionType` là `enum` **không** `CaseIterable` (chỉ các hằng `static let` trong `ExtensionType.swift`)
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
        case ExtensionType.video: return "Phim/Video (Video)"
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
