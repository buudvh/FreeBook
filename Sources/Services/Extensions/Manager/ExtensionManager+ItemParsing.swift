import Foundation
import JavaScriptCore

/// Đọc an toàn kết quả script (`search`, script tuỳ chọn, `detail`, `toc`, `genre`, `home`) theo hợp đồng
/// extension (extension-api.md).
///
/// - Mọi trường đọc qua `JSValueReader.cleanString`: `undefined`/`null`/`"null"`/`"undefined"` là **thiếu** —
///   `JSValue.toString()` từng biến chúng thành chữ "undefined" hiện lên giao diện.
/// - Chỉ resolve **bìa** (`resolveAssetURL`, host: host item → tham số host → `source`). `link`/`url` giữ nguyên
///   văn vì là khoá nhận diện sách/chương (đã lưu trên kệ, lịch sử, ChapterStore).
/// - `source` tra **một lần mỗi lượt gọi script** (`ExtensionHostResolver.sourceUrl(localPath:)`), không theo dòng.
extension ExtensionManager {
    /// Host dùng để resolve URL **tham số** của script (`detail`/`toc`/`page`/`chap`): host truyền vào (khác rỗng),
    /// không có thì `source` của tiện ích.
    internal static func scriptHost(_ host: String?, localPath: String) -> String? {
        ExtensionHostResolver.nonEmpty(host) ?? ExtensionHostResolver.sourceUrl(localPath: localPath)
    }

    /// Host ghép bìa: host của item → host dự phòng (tham số `host` của `detail`) → `source`.
    internal static func coverHost(itemHost: String?, fallbackHost: String? = nil, sourceHost: String?) -> String? {
        ExtensionHostResolver.nonEmpty(itemHost)
            ?? ExtensionHostResolver.nonEmpty(fallbackHost)
            ?? ExtensionHostResolver.nonEmpty(sourceHost)
    }

    /// Giá trị chuỗi đầu tiên **có mặt** theo thứ tự khoá (giá trị `""` vẫn tính là có mặt).
    internal static func firstString(_ dict: [String: JSValue], _ keys: [String]) -> String? {
        for key in keys {
            if let value = JSValueReader.cleanString(dict[key]) { return value }
        }
        return nil
    }

    /// Như `firstString` cho dictionary Foundation (`parseJSObject` của `detail`).
    internal static func foundationString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = JSValueReader.cleanString(any: dict[key]) { return value }
        }
        return nil
    }

    /// Một item danh sách. `nameKeys`: script tuỳ chọn (bình luận…) còn nhận `username`/`author` làm tên.
    internal static func listItem(
        from dict: [String: JSValue],
        nameKeys: [String] = ["name"],
        sourceHost: String?
    ) -> ExtensionItemResult {
        let host = JSValueReader.cleanString(dict["host"]) ?? ""
        let cover = firstString(dict, ["cover"]) ?? ""
        return ExtensionItemResult(
            name: firstString(dict, nameKeys) ?? "",
            author: firstString(dict, ["author"]) ?? "",
            description: firstString(dict, ["description", "desc"]) ?? "",
            content: firstString(dict, ["content"]) ?? "",
            cover: ExtensionURLFormatter.resolveAssetURL(cover, host: coverHost(itemHost: host, sourceHost: sourceHost)),
            link: firstString(dict, ["link", "url"]) ?? "",
            host: host,
            tag: (firstString(dict, ["tag"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            type: (firstString(dict, ["type"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Một dòng mục lục. Thiếu khoá `host` (hoặc `undefined`/`null`) ⇒ `source`; `host: ""` ⇒ giữ `""`.
    /// `flagsSections` (truyện tranh/video): dòng `type: "section"` được giữ và gắn `isSection`; truyện chữ giữ
    /// dòng đó như chương thường (hành vi cũ, chỉ số chương đã lưu không lệch).
    internal static func chapterItem(from dict: [String: JSValue], sourceHost: String?, flagsSections: Bool) -> ChapterResult {
        let isSection = flagsSections && JSValueReader.cleanString(dict["type"])?.lowercased() == "section"
        return ChapterResult(
            name: firstString(dict, ["name"]) ?? "",
            url: firstString(dict, ["url", "link"]) ?? "",
            host: JSValueReader.cleanString(dict["host"]) ?? (sourceHost ?? ""),
            isSection: isSection
        )
    }

    /// Tab `home` / thể loại `genre`: `{title, input, script}`, dạng cũ `{name, link}`. Khoá `input` có mặt mà
    /// `null` ⇒ `""` (script của tab thường bỏ qua input); thiếu tên hoặc thiếu cả `input` lẫn `link` ⇒ bỏ.
    internal static func categoryItems(from jsArray: [[String: JSValue]]) -> [CategoryResult] {
        jsArray.compactMap { dict -> CategoryResult? in
            guard let title = firstString(dict, ["title", "name"]) else { return nil }
            let input: String? = dict["input"] != nil
                ? (JSValueReader.cleanString(dict["input"]) ?? "")
                : firstString(dict, ["link"])
            guard let input else { return nil }
            let script = ExtensionHostResolver.nonEmpty(firstString(dict, ["script"])) ?? "search.js"
            return CategoryResult(title: title, input: input, script: script)
        }
    }

    /// `genres`/`suggests`/`comments` của `detail` (mảng `{title, input, script}`); thiếu `title`/`input` ⇒ bỏ.
    internal static func detailCategories(_ value: Any?, defaultScript: String) -> [CategoryResult] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item -> CategoryResult? in
            guard let title = foundationString(item, ["title"]), !title.isEmpty,
                  let input = foundationString(item, ["input"]), !input.isEmpty else { return nil }
            let script = ExtensionHostResolver.nonEmpty(foundationString(item, ["script"])) ?? defaultScript
            return CategoryResult(title: title, input: input, script: script)
        }
    }
}
