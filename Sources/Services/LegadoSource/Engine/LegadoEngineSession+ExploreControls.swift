import Foundation
import JavaScriptCore

/// Khám phá động (spec §11): danh sách mục **có kiểu**, `infoMap` theo nguồn, `action` của điều khiển.
extension LegadoEngineSession {
    /// Mọi mục khám phá có kiểu: ô bấm, tiêu đề nhóm và điều khiển; điều khiển có `value` = giá trị hiện tại trong
    /// `infoMap`. Bật ngữ cảnh `infoMap` cho phiên; sau khi dựng danh sách, ghi `default` của `select`/`toggle`/`text` vào
    /// `infoMap` **nếu khoá chưa có** (§11.3 mục 2; `select`/`toggle` không có `default` ⇒ phần tử đầu của `chars`).
    func exploreEntries(_ exploreUrl: String) throws -> [LegadoEngineExploreItem] {
        activateExploreInfo()
        var items = try exploreEntriesIncludingControls(exploreUrl)
        for index in items.indices where items[index].isControl && items[index].kind != .button {
            let title = items[index].title
            if exploreInfo?[title] == nil {
                let fallback = items[index].kind == .text ? nil : items[index].chars.first
                if let seed = items[index].defaultValue ?? fallback {
                    setExploreInfoValue(seed, forKey: title)
                }
            }
            items[index].value = exploreInfo?[title]
        }
        return items
    }

    /// Bật `infoMap` của nguồn cho phiên (nạp từ kho bền nếu chưa).
    func activateExploreInfo() {
        if exploreInfo == nil { exploreInfo = store.exploreInfo(sourceKey: source.key) }
    }

    /// Ghi một giá trị `infoMap` (bền ngay, U46); `nil` ⇒ xoá. Ngoài ngữ cảnh khám phá ⇒ bỏ qua (map chỉ đọc).
    func setExploreInfoValue(_ value: String?, forKey key: String) {
        guard var info = exploreInfo else { return }
        info[key] = value
        exploreInfo = info
        store.setExploreValue(value, forKey: key, sourceKey: source.key)
    }

    /// `action` của điều khiển khám phá (spec §11.4): ngữ cảnh JS có `infoMap`, đã nạp `jsLib`; **không** chạy lại
    /// `exploreUrl` trước. Gặp `ReferenceError` (hàm chưa định nghĩa — U47) ⇒ chạy `exploreUrl` (dạng JS) trong cùng
    /// ngữ cảnh rồi thử `action` lần hai. Trả thông báo lỗi JS (nếu có).
    func runExploreAction(_ action: String, exploreUrl: String) throws -> String? {
        activateExploreInfo()
        let code = Self.strippedScript(action)
        let bindings = jsBindings(result: nil, baseUrl: sourceBase, src: nil)
        let first = try runtime.evaluateRaw(code, bindings: bindings)
        guard let error = first.error else { return nil }
        let lower = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard error.contains("ReferenceError"), lower.hasPrefix("@js:") || lower.hasPrefix("<js>") else { return error }
        _ = try runtime.evaluateRaw(Self.strippedScript(exploreUrl), bindings: bindings)
        return try runtime.evaluateRaw(code, bindings: bindings).error
    }
}
