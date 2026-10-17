import Foundation
import JavaScriptCore

/// Ánh xạ kết quả `chap.js` (danh sách server) và `track.js` (nguồn phát) của tiện ích **video** — hàm thuần.
///
/// Luật bất biến: chuỗi `data` của server/track là **opaque** — giữ nguyên văn từng byte (không trim, không
/// encode, không `cleanAndResolveUrl`). Nếu script trả `data` là object/mảng thì dùng `JSON.stringify` phía JS
/// (giữ thứ tự khoá và cách escape của JS) để `track.js`/resolver parse lại.
enum VideoTrackMapper {
    /// Lỗi ánh xạ track — thông báo tiếng Việt cho người dùng, log `❌` (luôn ghi dù công tắc log tắt).
    static func mappingError(_ message: String) -> ExtensionManagerError {
        AppLogger.shared.log("❌ [VideoTrackMapper] \(message)")
        return ExtensionManagerError.sourceResponse(message: message)
    }

    // MARK: - Servers (`chap.js`)

    /// Nhận: mảng server; wrapper `{tracks: […]}` / `{data: […]}`; một object server đơn; hoặc một chuỗi đơn.
    /// Alias: `url`/`link` → `data`, `name`/`label` → `title`. Title rỗng ⇒ "Server N"; trùng ⇒ thêm " (2)"…
    static func servers(from value: JSValue) -> [VideoServer] {
        let items: [JSValue]
        if value.isArray {
            items = JSValueReader.array(value)
        } else if JSValueReader.isPlainObject(value) {
            let tracks = value.forProperty("tracks")
            let wrappedData = value.forProperty("data")
            if let tracks, tracks.isArray {
                items = JSValueReader.array(tracks)
            } else if let wrappedData, wrappedData.isArray {
                items = JSValueReader.array(wrappedData)
            } else {
                items = [value]
            }
        } else if value.isString {
            items = [value]
        } else {
            items = []
        }

        var servers: [VideoServer] = []
        var usedTitles: [String: Int] = [:]
        for item in items {
            guard let raw = rawServer(from: item) else { continue }
            let baseTitle = raw.title.isEmpty ? "Server \(servers.count + 1)" : raw.title
            servers.append(VideoServer(title: uniqueTitle(baseTitle, used: &usedTitles), data: raw.data))
        }
        return servers
    }

    private static func rawServer(from item: JSValue) -> (title: String, data: String)? {
        if item.isString {
            guard let data = item.toString(), !data.isEmpty else { return nil }
            return ("", data)
        }
        guard JSValueReader.isPlainObject(item) else { return nil }
        let dataValue = firstPresent(item, keys: ["data", "url", "link"])
        guard let data = JSValueReader.opaqueString(dataValue), !data.isEmpty else { return nil }
        let title = JSValueReader.nonEmptyString(firstPresent(item, keys: ["title", "name", "label"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (title, data)
    }

    /// "A", "A" ⇒ "A", "A (2)". `used` đếm số lần mỗi title gốc đã xuất hiện; vòng lặp tránh đụng title
    /// gốc vốn đã có dạng "A (2)".
    private static func uniqueTitle(_ base: String, used: inout [String: Int]) -> String {
        guard used[base] != nil else {
            used[base] = 1
            return base
        }
        var counter = (used[base] ?? 1) + 1
        var candidate = "\(base) (\(counter))"
        while used[candidate] != nil {
            counter += 1
            candidate = "\(base) (\(counter))"
        }
        used[base] = counter
        used[candidate] = 1
        return candidate
    }

    // MARK: - Track (`track.js`)

    /// `{type, data, host?, mimeType?, headers?, timeSkip?, subtitles?}`.
    ///
    /// - `type` so chữ thường; `iframe` ⇒ `webview`; thiếu/rỗng ⇒ `native` (dự phòng mềm, có log);
    ///   giá trị lạ ⇒ ném lỗi.
    /// - `data` bắt buộc là chuỗi (object được `JSON.stringify`, cho dạng `{"data":…,"host":…}` của `webview`).
    static func track(from value: JSValue) throws -> VideoTrack {
        guard JSValueReader.isPlainObject(value) else {
            throw mappingError("Kết quả track của tiện ích không phải object hợp lệ")
        }

        let kind = try trackKind(JSValueReader.string(value.forProperty("type")))

        let dataValue = value.forProperty("data")
        guard let data = JSValueReader.opaqueString(dataValue), !data.isEmpty,
              dataValue?.isString == true || JSValueReader.isPlainObject(dataValue) || dataValue?.isArray == true else {
            throw mappingError("Track không có dữ liệu phát (data phải là chuỗi)")
        }

        let host = JSValueReader.nonEmptyString(value.forProperty("host"))
        let mimeType = JSValueReader.nonEmptyString(firstPresent(value, keys: ["mimeType", "mime_type", "mime"]))

        return VideoTrack(
            kind: kind,
            data: data,
            host: host,
            mimeType: mimeType,
            headers: JSValueReader.stringDictionary(value.forProperty("headers")),
            timeSkips: timeSkips(from: firstPresent(value, keys: ["timeSkip", "timeSkips", "timeskip"])),
            subtitles: subtitles(from: firstPresent(value, keys: ["subtitles", "subtitle"]))
        )
    }

    static func trackKind(_ rawType: String?) throws -> VideoTrackKind {
        let type = (rawType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch type {
        case "":
            AppLogger.shared.log("⚠️ [VideoTrackMapper] Track thiếu type — coi như native")
            return .native
        case "native":
            return .native
        case "auto":
            return .auto
        case "webview", "iframe":
            return .webview
        default:
            throw mappingError("Kiểu track không được hỗ trợ: \(type)")
        }
    }

    private static func timeSkips(from value: JSValue?) -> [VideoTimeSkip] {
        JSValueReader.array(value).compactMap { (item: JSValue) -> VideoTimeSkip? in
            guard JSValueReader.isPlainObject(item),
                  let from = JSValueReader.int(firstPresent(item, keys: ["fromTime", "from"])),
                  let to = JSValueReader.int(firstPresent(item, keys: ["toTime", "to"])),
                  from >= 0, to > from else { return nil }
            return VideoTimeSkip(fromMs: from, toMs: to)
        }
    }

    private static func subtitles(from value: JSValue?) -> [VideoSubtitleTrack] {
        JSValueReader.array(value).compactMap { (item: JSValue) -> VideoSubtitleTrack? in
            guard JSValueReader.isPlainObject(item),
                  let data = JSValueReader.nonEmptyString(firstPresent(item, keys: ["data", "url", "link"])) else { return nil }
            return VideoSubtitleTrack(
                data: data,
                type: JSValueReader.nonEmptyString(item.forProperty("type")),
                label: JSValueReader.nonEmptyString(firstPresent(item, keys: ["label", "name", "title"])),
                language: JSValueReader.nonEmptyString(firstPresent(item, keys: ["language", "lang"]))
            )
        }
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
