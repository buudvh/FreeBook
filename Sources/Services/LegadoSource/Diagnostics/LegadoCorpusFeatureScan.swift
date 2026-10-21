import Foundation

/// Quét tĩnh `source.json` tìm hàm/tính năng mà bản này **chưa** hỗ trợ — chỉ để gợi ý trong báo cáo.
///
/// Vì sao cần: facade chỉ nâng lỗi "mềm" của engine (`session.diagnostics`) thành lỗi ném ra khi **bước đó ra rỗng**,
/// và chỉ một lý do. Stub chưa hỗ trợ gọi ở bước trước (vd biến `@put` không được ghi) vẫn chỉ hiện ra là "rule khớp 0" ở
/// bước sau. Gợi ý ở đây giúp đọc báo cáo: nguồn thất bại mà có gợi ý thì nhiều khả năng hỏng vì tính năng hoãn.
/// Danh sách lấy theo bảng hoãn của spec §6.11, §3.11 (`data:`) và §7.1. **Không** gồm các hàm cố ý không định
/// nghĩa ở §6.10 (`java.qread`, `java.deviceID`, `java.getUserAgent`): nguồn dò chúng trong `try` và đi nhánh khác,
/// nên chúng không phải dấu hiệu hỏng. Không đổi lớp lỗi chính.
enum LegadoCorpusFeatureScan {
    /// Đợt 2 + 3 đã cài phần lớn bảng hoãn cũ; còn lại: hàm cố ý không định nghĩa / stub (spec §13.11, §14.5),
    /// định dạng nén chưa hỗ trợ, shim Java chưa có, và các hàm chỉ chạy khi có người dùng (bộ chạy không tương tác).
    private static let tokens: [String] = [
        "java.startBrowser", "java.getVerificationCode", "java.reLoginView",
        "java.open(", "java.openVideoPlayer", "java.addBook", "java.showBrowser", "java.showReadingBrowser",
        "java.readFile", "Jsoup.connect", "unrarFile", "un7zFile", "android.graphics", "Inflater", "java.net.URL"
    ]
    private static let maxHints = 12

    static func hints(in source: LegadoBookSource) -> [String] {
        let raw = source.rawJSONString
        var found = tokens.filter { raw.contains($0) }
        if isFilled(source.loginCheckJs) { found.append("loginCheckJs") }
        if source.needsLogin { found.append("loginUrl") }
        return Array(found.prefix(maxHints))
    }

    private static func isFilled(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
