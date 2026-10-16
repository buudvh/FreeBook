import SwiftUI

/// Lựa chọn của bộ lọc **chọn nhiều** ở tab "Tất cả tiện ích", lưu `@AppStorage` dạng JSON `[String]`.
///
/// Khoá mới `extFilterTypes` / `extFilterLocales` / `extFilterAuthors`. Khoá chưa từng được ghi (chuỗi rỗng —
/// giá trị mặc định của `@AppStorage`) thì đọc khoá một-giá-trị cũ `extFilterType` / `extFilterLocale` /
/// `extFilterAuthor` (`"all"` ⇒ rỗng, giá trị khác ⇒ `[giá trị]`), nên người dùng giữ nguyên bộ lọc sau khi
/// cập nhật app. Lần ghi đầu tiên (kể cả "Đặt lại" ⇒ `"[]"`) chốt khoá mới và khoá cũ không còn được đọc.
enum ExtensionFilterSelection {
    static let typesKey = "extFilterTypes"
    static let localesKey = "extFilterLocales"
    static let authorsKey = "extFilterAuthors"

    static let legacyTypeKey = "extFilterType"
    static let legacyLocaleKey = "extFilterLocale"
    static let legacyAuthorKey = "extFilterAuthor"

    static func decode(_ json: String, legacyKey: String) -> Set<String> {
        guard !json.isEmpty else {
            let legacy = UserDefaults.standard.string(forKey: legacyKey) ?? "all"
            return legacy.isEmpty || legacy == "all" ? [] : [legacy]
        }
        guard let data = json.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }

    static func encode(_ values: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(values.sorted()),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    /// Binding `Set<String>` cho `FilterSheet`, đọc/ghi qua chuỗi JSON của `@AppStorage`.
    static func binding(_ json: Binding<String>, legacyKey: String) -> Binding<Set<String>> {
        Binding(
            get: { decode(json.wrappedValue, legacyKey: legacyKey) },
            set: { json.wrappedValue = encode($0) }
        )
    }
}
