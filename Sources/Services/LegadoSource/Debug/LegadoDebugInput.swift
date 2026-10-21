import Foundation

/// Ô nhập của màn "Gỡ lỗi từng bước" (spec §12.3): chuỗi nhập quyết định bước bắt đầu.
///
/// | Nhập | Bước đầu |
/// |---|---|
/// | từ khoá | tìm kiếm |
/// | URL tuyệt đối | thông tin sách |
/// | `++` + URL | mục lục |
/// | `--` + URL | nội dung |
/// | `tên::url` | mục khám phá |
///
/// Thứ tự nhận dạng (spec, đề xuất): `++` → `--` → có `::` → bắt đầu `http(s)://` → còn lại là từ khoá. Tiền tố gõ
/// trong ô (`++`/`--`/`::`) thắng chip chế độ đang chọn; không có tiền tố thì theo chip, riêng chip "Từ khoá" mà ô là URL
/// `http(s)` thì thành "URL chi tiết". Ô trống ở chế độ từ khoá ⇒ `checkKeyWord` của nguồn (bản thân nó có thể mang
/// tiền tố), không có thì "我的".
struct LegadoDebugInput: Sendable, Equatable {
    enum Mode: String, Sendable, CaseIterable, Identifiable {
        case keyword
        case bookURL
        case toc
        case content
        case explore

        var id: String { rawValue }

        var label: String {
            switch self {
            case .keyword: return "Từ khoá"
            case .bookURL: return "URL chi tiết"
            case .toc: return "++ Mục lục"
            case .content: return "-- Nội dung"
            case .explore: return ":: Khám phá"
            }
        }

        var placeholder: String {
            switch self {
            case .keyword: return "Từ khoá (trống = checkKeyWord của nguồn)"
            case .bookURL: return "https://… (trang thông tin sách)"
            case .toc: return "https://… (trang mục lục)"
            case .content: return "https://… (trang nội dung chương)"
            case .explore: return "tên::https://… hoặc URL mục khám phá"
            }
        }
    }

    /// Lời nhắc khi ô nhập chưa chạy được.
    struct Issue: Error, Sendable, Equatable {
        let message: String
    }

    static let fallbackKeyword = "我的"

    let mode: Mode
    /// Từ khoá, hoặc rule URL (đã bỏ tiền tố / phần `tên::`).
    let value: String
    /// Tên mục khám phá (phần trước `::`), chỉ để hiển thị.
    let exploreTitle: String

    /// Chế độ do **tiền tố** trong chuỗi nhập quyết định (`++`, `--`, `::`); `nil` = không có tiền tố (theo chip).
    static func prefixMode(_ raw: String) -> Mode? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("++") { return .toc }
        if text.hasPrefix("--") { return .content }
        if text.contains("::") { return .explore }
        return nil
    }

    static func isHTTPURL(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
    }

    /// Dựng đầu vào chạy được từ ô nhập + chip; lỗi kèm lời nhắc khi thiếu từ khoá/URL.
    static func resolve(raw: String, selected: Mode, checkKeyWord: String) -> Result<LegadoDebugInput, Issue> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, selected == .keyword {
            text = checkKeyWord.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return .success(LegadoDebugInput(mode: .keyword, value: fallbackKeyword, exploreTitle: "")) }
        }
        var mode = prefixMode(text) ?? selected
        if mode == .keyword, isHTTPURL(text) { mode = .bookURL }
        var value = text
        var title = ""
        switch mode {
        case .toc, .content:
            if text.hasPrefix("++") || text.hasPrefix("--") {
                value = String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        case .explore:
            if let range = text.range(of: "::") {
                title = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        default:
            break
        }
        guard !value.isEmpty else {
            let message = mode == .keyword ? "Nhập từ khoá cần tìm." : "Nhập URL cho chế độ \"\(mode.label)\"."
            return .failure(Issue(message: message))
        }
        return .success(LegadoDebugInput(mode: mode, value: value, exploreTitle: title))
    }
}
