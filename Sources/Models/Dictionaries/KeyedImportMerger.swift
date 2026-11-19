import Foundation

/// Gộp dữ liệu nhập vào dữ liệu đang có theo một trong ba `DataImportMode` — hàm thuần, không I/O.
///
/// Một chỗ quyết định nghĩa của ba chế độ cho mọi màn nhập (phiên âm, thay thế ký tự TTS, lọc rác, công cụ tra cứu…)
/// để "Gộp" / "Chỉ thêm key mới" không lệch nhau giữa các màn như chữ "Gộp" cũ (xem `DataImportMode`):
/// - **Khoá** do chỗ gọi đưa vào (`key`) và đã chuẩn hoá sẵn (hạ chữ thường, gấp dấu…) — ở đây chỉ so `==`.
/// - Khoá lặp **trong file** ⇒ bản đứng **sau cùng** thắng, giữ vị trí lần xuất hiện đầu (đọc file từ trên xuống).
/// - `.replaceAll`: kết quả = các mục của file (đã bỏ lặp), theo thứ tự file.
/// - `.overwriteExisting`: giữ thứ tự bản trên máy; khoá trùng ⇒ thay **tại chỗ** bằng `overwrite(cũ, mới)` (mặc định
///   lấy bản mới — chỗ gọi dùng để giữ `id` cũ); khoá mới ⇒ nối cuối theo thứ tự file.
/// - `.keepExisting`: bản trên máy giữ nguyên; chỉ nối cuối khoá mới.
/// - Khoá lặp sẵn **trên máy** không bị gộp lại; khoá trùng trong file chỉ tác động lên mục đầu tiên mang khoá đó.
public enum KeyedImportMerger {

    /// Gộp hai danh sách có thứ tự. `isSameContent` phân biệt "cập nhật" với "trùng y hệt" khi đếm cho toast.
    public static func merge<Element, Key: Hashable>(
        existing: [Element],
        imported: [Element],
        mode: DataImportMode,
        key: (Element) -> Key,
        isSameContent: (Element, Element) -> Bool,
        overwrite: (_ existing: Element, _ incoming: Element) -> Element = { _, incoming in incoming }
    ) -> (elements: [Element], summary: KeyedImportSummary) {
        // Bỏ khoá lặp trong file: giữ vị trí đầu, lấy nội dung sau cùng.
        var incomingOrder: [Key] = []
        var incomingByKey: [Key: Element] = [:]
        for element in imported {
            let elementKey = key(element)
            if incomingByKey.updateValue(element, forKey: elementKey) == nil {
                incomingOrder.append(elementKey)
            }
        }
        let incoming = incomingOrder.compactMap { incomingByKey[$0] }

        if mode == .replaceAll {
            let summary = KeyedImportSummary(
                mode: mode,
                importedCount: incoming.count,
                previousCount: existing.count,
                totalCount: incoming.count
            )
            return (incoming, summary)
        }

        var result = existing
        var indexByKey: [Key: Int] = [:]
        for (index, element) in existing.enumerated() where indexByKey[key(element)] == nil {
            indexByKey[key(element)] = index
        }

        var added = 0, updated = 0, unchanged = 0, skipped = 0
        for element in incoming {
            let elementKey = key(element)
            guard let index = indexByKey[elementKey] else {
                result.append(element)
                added += 1
                continue
            }
            if mode == .keepExisting {
                skipped += 1
                continue
            }
            let replaced = overwrite(result[index], element)
            if isSameContent(result[index], replaced) {
                unchanged += 1
            } else {
                updated += 1
            }
            result[index] = replaced
        }

        let summary = KeyedImportSummary(
            mode: mode,
            importedCount: incoming.count,
            added: added,
            updated: updated,
            unchanged: unchanged,
            skipped: skipped,
            previousCount: existing.count,
            totalCount: result.count
        )
        return (result, summary)
    }

    /// Bản cho bảng khoá → giá trị (từ điển phiên âm). Khoá của `imported` đã chuẩn hoá nên không còn lặp.
    public static func merge<Key: Hashable, Value: Equatable>(
        existing: [Key: Value],
        imported: [Key: Value],
        mode: DataImportMode
    ) -> (values: [Key: Value], summary: KeyedImportSummary) {
        guard mode != .replaceAll else {
            let summary = KeyedImportSummary(
                mode: mode,
                importedCount: imported.count,
                previousCount: existing.count,
                totalCount: imported.count
            )
            return (imported, summary)
        }

        var result = existing
        var added = 0, updated = 0, unchanged = 0, skipped = 0
        for (entryKey, value) in imported {
            guard let current = result[entryKey] else {
                result[entryKey] = value
                added += 1
                continue
            }
            if mode == .keepExisting {
                skipped += 1
            } else if current == value {
                unchanged += 1
            } else {
                result[entryKey] = value
                updated += 1
            }
        }

        let summary = KeyedImportSummary(
            mode: mode,
            importedCount: imported.count,
            added: added,
            updated: updated,
            unchanged: unchanged,
            skipped: skipped,
            previousCount: existing.count,
            totalCount: result.count
        )
        return (result, summary)
    }

    /// Cấp `id` mới cho mục mang `id` đã gặp ở mục đứng trước — `ForEach` dựng theo `Identifiable` và các lệnh
    /// xoá / sửa đi theo `id`, hai mục cùng `id` là hỏng danh sách (file xuất từ máy này nhập lại sau khi đã sửa…).
    public static func uniquingIDs<Element, ID: Hashable>(
        _ elements: [Element],
        id: WritableKeyPath<Element, ID>,
        makeID: () -> ID
    ) -> [Element] {
        var seen = Set<ID>()
        return elements.map { element in
            var copy = element
            if !seen.insert(copy[keyPath: id]).inserted {
                var fresh = makeID()
                while seen.contains(fresh) { fresh = makeID() }
                copy[keyPath: id] = fresh
                seen.insert(fresh)
            }
            return copy
        }
    }
}
