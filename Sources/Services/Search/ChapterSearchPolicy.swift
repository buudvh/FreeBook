import Foundation

/// Nguồn **duy nhất** cho cấu hình và hằng số của chỉ mục tìm toàn văn offline.
///
/// Chỉ mục **mặc định tắt**: FTS5 với tokenizer `trigram` phải lưu lại nội dung chương và sinh
/// một token cho mỗi cửa sổ 3 ký tự, nên dung lượng chỉ mục lớn hơn nhiều lần dung lượng text.
/// Đây là lựa chọn có ý thức — `unicode61` cho chỉ mục nhỏ hơn nhưng coi cả một đoạn chữ Hán
/// (không có khoảng trắng) là **một** token, tức không tra được cụm chữ Hán, mà phần lớn truyện
/// trong app là bản gốc tiếng Trung. Vì vậy người dùng phải tự bật và tự xây chỉ mục, và biết
/// trước cái giá phải trả bằng dung lượng.
///
/// Các hằng ở đây **không** được nhân bản sang database/actor/builder.
enum ChapterSearchPolicy {
    static let enabledKey = "chapterSearchIndexEnabled"

    /// `trigram` chỉ khớp được chuỗi từ **3 ký tự** trở lên; truy vấn ngắn hơn không bao giờ
    /// được đưa xuống SQLite.
    static let minimumQueryLength = 3

    /// Trần số chương trả về cho một lượt tìm. Mỗi hit phải đọc lại nội dung chương từ chỉ mục
    /// để định vị đoạn, nên trần này vừa là trần bộ nhớ tạm.
    static let maxResults = 60

    /// Số ký tự lấy thêm mỗi bên quanh vị trí khớp khi dựng đoạn xem trước.
    static let snippetRadius = 60

    /// Nhường thread sau mỗi bấy nhiêu chương khi xây lại chỉ mục.
    static let builderYieldInterval = 50

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Chuẩn hoá truy vấn người dùng nhập: bỏ khoảng trắng hai đầu và từ chối truy vấn quá ngắn.
    static func normalizedQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryLength else { return nil }
        return trimmed
    }

    /// Bọc truy vấn thành một *phrase* của FTS5 (`"..."`). Với `trigram`, phrase tương đương
    /// khớp chuỗi con, và mọi ký tự đặc biệt bên trong dấu nháy đôi đều là ký tự thường —
    /// chỉ cần nhân đôi dấu nháy đôi có sẵn trong truy vấn.
    static func matchExpression(for query: String) -> String {
        "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
