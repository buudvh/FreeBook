import Foundation

/// Kiểu hiện phụ đề phim / lời bài hát khi dòng có bản dịch (`MediaCaptionTranslator`). Là việc của **View**: session cấp
/// cả chuỗi gốc lẫn bản dịch, View đọc kiểu qua `@AppStorage` (khoá riêng cho phim và nhạc) rồi chọn chuỗi để vẽ.
///
/// "Chuỗi gốc" = chữ **đã chuyển phồn → giản** khi phim / album bật phồn → giản (chạy cả khi tắt dịch —
/// `VideoSubtitleCue.displayText`, `AudioLyricLine.displayText`), không thì nguyên văn: Gốc = chữ đã chuyển, Song ngữ = chữ
/// đã chuyển + bản dịch.
///
/// Dòng không có bản dịch (không có chữ Hán, cổng dịch đang tắt, hoặc chưa dịch tới) ⇒ mọi kiểu đều chỉ hiện chuỗi gốc.
enum MediaCaptionDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case original
    case translated
    case bilingual

    /// Khoá `@AppStorage` của phụ đề phim (`VideoSubtitleOverlay`, menu phụ đề của thanh trên trình phát).
    static let videoDefaultsKey = "videoSubtitleDisplayMode"
    /// Khoá `@AppStorage` của lời bài hát (trang Lời, dòng lời ở trang Đĩa, ngăn kéo `…` của màn nghe).
    static let audioDefaultsKey = "audioLyricsDisplayMode"
    /// Anh Bửu chốt 2026-11-11: mặc định hiện bản dịch cho cả phim lẫn nhạc.
    static let defaultValue: MediaCaptionDisplayMode = .translated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Gốc"
        case .translated: return "Bản dịch"
        case .bilingual: return "Song ngữ"
        }
    }

    /// Chuỗi chính (to) và chuỗi phụ (nhỏ, mờ; `nil` = không vẽ dòng phụ) của một dòng theo kiểu này.
    /// - Gốc: chỉ chuỗi gốc.
    /// - Bản dịch: bản dịch, thiếu thì chuỗi gốc.
    /// - Song ngữ: bản dịch + chuỗi gốc làm dòng phụ; thiếu bản dịch thì chỉ chuỗi gốc (không vẽ dòng phụ rỗng).
    func lines(original: String, translation: String?) -> (primary: String, secondary: String?) {
        guard let translation, !translation.isEmpty, self != .original else { return (original, nil) }
        return self == .bilingual ? (translation, original) : (translation, nil)
    }
}
