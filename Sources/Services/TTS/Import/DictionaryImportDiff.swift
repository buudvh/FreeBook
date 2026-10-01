import Foundation

/// So khớp một file từ điển **vừa nhập** với từ điển **đang có**, để màn "Trộn" hỏi người dùng từng mục
/// trùng khoá nhưng khác nghĩa.
///
/// Tách khỏi View vì hai lý do: (1) phép so khớp chạy **ngoài `MainActor`** (từ điển NghiTTS ~30k mục),
/// (2) hai màn từ điển dùng chung đúng **một** định nghĩa "trùng khoá khác nghĩa" — để trong View thì hai
/// bên dễ hiểu khác nhau.
enum DictionaryImportDiff {

    /// Một mục **trùng khoá nhưng khác nghĩa** — đơn vị để người dùng chọn/bỏ chọn.
    struct Conflict: Identifiable, Hashable, Sendable {
        let key: String
        let currentValue: String
        let importedValue: String

        var id: String { key }
    }

    /// Kết quả so khớp. Ba nhóm **không** cần hỏi được đếm riêng để màn hình nói rõ chuyện gì sẽ xảy ra:
    /// `newKeys` luôn được thêm, `sameCount` thay hay không cũng như nhau, `keptCount` giữ nguyên.
    struct Summary: Sendable {
        let conflicts: [Conflict]
        let newKeys: [String]
        let sameCount: Int
        let keptCount: Int
    }

    /// So khớp sau khi **chuẩn hoá khoá** và **`trim` giá trị** ở cả hai vế; khoá rỗng / giá trị rỗng bị bỏ
    /// qua, đúng như đường nhập hiện tại.
    ///
    /// - Parameter normalizedKey: closure chuẩn hoá của **đúng từ điển đang nhập** — VieNeu gấp dấu phụ,
    ///   NghiTTS chỉ hạ chữ thường (xem `RephoneticizeService.normalizedKey`).
    static func diff(
        imported: [String: String],
        current: [String: String],
        normalizedKey: (String) -> String
    ) -> Summary {
        var conflicts: [Conflict] = []
        var newKeys: [String] = []
        var sameCount = 0
        var importedKeys = Set<String>()

        for (rawKey, rawValue) in imported {
            let key = normalizedKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            importedKeys.insert(key)

            guard let existing = current[key] else {
                newKeys.append(key)
                continue
            }
            if existing == value {
                sameCount += 1
            } else {
                conflicts.append(Conflict(key: key, currentValue: existing, importedValue: value))
            }
        }

        // Sắp theo khoá để danh sách ổn định giữa các lần mở (thứ tự `Dictionary` là ngẫu nhiên).
        conflicts.sort { $0.key < $1.key }
        newKeys.sort()

        // Khoá chỉ có ở máy — đếm trên **khoá đã chuẩn hoá** để khớp với cách `merged` dựng bảng cuối.
        var keptCount = 0
        for key in current.keys where !importedKeys.contains(normalizedKey(key)) {
            keptCount += 1
        }

        return Summary(conflicts: conflicts, newKeys: newKeys, sameCount: sameCount, keptCount: keptCount)
    }

    /// Dựng bảng cuối: giữ `current`, thêm mục mới, và với mỗi mục trùng khoá **được chọn** thì ghi giá trị
    /// vừa nhập. Mục bị **bỏ chọn** giữ nguyên giá trị đang có trên máy.
    static func merged(
        current: [String: String],
        imported: [String: String],
        selection: Set<String>,
        normalizedKey: (String) -> String
    ) -> [String: String] {
        var result = current
        for (rawKey, rawValue) in imported {
            let key = normalizedKey(rawKey)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            // Không trùng khoá ⇒ thêm mới luôn; trùng ⇒ chỉ ghi khi mục đó được chọn.
            if result[key] == nil || selection.contains(key) {
                result[key] = value
            }
        }
        return result
    }
}
