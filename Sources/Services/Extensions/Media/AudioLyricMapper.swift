import Foundation
import JavaScriptCore

/// Ánh xạ lời bài hát trong kết quả `track.js` của tiện ích loại `audio` — hàm thuần (hợp đồng tiện ích, trường `lyrics`).
///
/// - `lyrics`: mảng `{data, type, label, language}` (alias `url`/`link` cho `data`, `name`/`title` cho `label`, `lang` cho
///   `language`) hoặc phần tử chuỗi trần. Một object đơn / một chuỗi đơn cũng nhận (lỏng hơn hợp đồng, vô hại).
/// - `lyrics` không ra nguồn nào ⇒ trường đơn `lyric` (chuỗi) + `lyricType`.
/// - Bỏ nguồn `data` rỗng / `"null"`, khử trùng theo `data` (bản trim, giữ nguồn đầu). `data` giữ nguyên văn.
enum AudioLyricMapper {
    static func sources(of track: JSValue) -> [AudioLyricSource] {
        let raw = track.forProperty("lyrics")
        let items: [JSValue]
        if let raw, raw.isString || JSValueReader.isPlainObject(raw) {
            items = [raw]
        } else {
            items = JSValueReader.array(raw)
        }
        var drafts = items.compactMap { draft(from: $0) }
        if drafts.isEmpty, let single = JSValueReader.cleanString(track.forProperty("lyric")), !isBlank(single) {
            drafts = [Draft(data: single, type: JSValueReader.nonEmptyString(track.forProperty("lyricType")), label: nil, language: nil)]
        }
        var seen = Set<String>()
        let unique = drafts.filter { seen.insert($0.data.trimmingCharacters(in: .whitespacesAndNewlines)).inserted }
        return unique.enumerated().map { offset, draft in
            AudioLyricSource(id: offset, data: draft.data, type: draft.type, label: draft.label, language: draft.language)
        }
    }

    // MARK: - Nội bộ

    private struct Draft {
        let data: String
        let type: String?
        let label: String?
        let language: String?
    }

    private static func draft(from item: JSValue) -> Draft? {
        if item.isString {
            guard let data = JSValueReader.cleanString(item), !isBlank(data) else { return nil }
            return Draft(data: data, type: nil, label: nil, language: nil)
        }
        guard JSValueReader.isPlainObject(item),
              let data = JSValueReader.cleanString(firstPresent(item, keys: ["data", "url", "link"])),
              !isBlank(data) else { return nil }
        return Draft(
            data: data,
            type: JSValueReader.nonEmptyString(item.forProperty("type")),
            label: JSValueReader.nonEmptyString(firstPresent(item, keys: ["label", "name", "title"])),
            language: JSValueReader.nonEmptyString(firstPresent(item, keys: ["language", "lang"]))
        )
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Thuộc tính đầu tiên có mặt (không undefined/null) theo thứ tự `keys`.
    private static func firstPresent(_ object: JSValue, keys: [String]) -> JSValue? {
        for key in keys {
            let candidate = object.forProperty(key)
            if JSValueReader.isPresent(candidate) { return candidate }
        }
        return nil
    }
}
