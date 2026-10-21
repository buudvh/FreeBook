import Foundation

/// API khám phá động cho UI (spec §11). Hàm `async` chạy engine trên thread nền (không chặn main), trong ngữ cảnh **có
/// người dùng** (`action` có thể mở trình duyệt). Danh sách mở ra từ ô bấm vẫn đi luồng cũ
/// (`SourceRuntime.executeCustomScript(scriptFileName: legadoExploreScriptName, input: item.url, …)`).
///
/// Vòng đời điều khiển: UI đổi `select`/`toggle`/`text` ⇒ `setValue(_:forTitle:source:)` (ghi `infoMap` bền ngay) ⇒ nếu
/// điều khiển có `action` thì `runAction` ⇒ JS thường gọi `java.refreshExplore()` ⇒ UI nhận
/// `LegadoPresentationEvent.refreshExplore(sourceKey:)` và gọi lại `items(for:)`.
enum LegadoExploreService {
    /// `exploreUrl` thô của nguồn (từ JSON gốc).
    static func exploreUrl(of source: LegadoEngineSource) -> String {
        guard let value = LegadoEngineJSONParser.parse(source.rawJSON, lenient: true)?["exploreUrl"], !value.isNull else {
            return ""
        }
        return value.scalarString
    }

    /// Mọi mục có kiểu (ô bấm, tiêu đề nhóm, điều khiển kèm giá trị hiện tại). `exploreUrl` rỗng ⇒ `[]`.
    static func items(for source: LegadoEngineSource) async throws -> [LegadoEngineExploreItem] {
        let rule = exploreUrl(of: source)
        guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try await LegadoInteraction.$isInteractive.withValue(true) {
            try await LegadoEngineSession.run(source: source) { session in
                try session.exploreEntries(rule)
            }
        }
    }

    /// `infoMap` hiện tại của nguồn.
    static func values(for source: LegadoEngineSource) -> [String: String] {
        LegadoFileStateStore.shared.exploreInfo(sourceKey: source.key)
    }

    /// Ghi giá trị người dùng chọn/nhập cho điều khiển `title` (bền ngay); `nil` ⇒ xoá.
    static func setValue(_ value: String?, forTitle title: String, source: LegadoEngineSource) {
        LegadoFileStateStore.shared.setExploreValue(value, forKey: title, sourceKey: source.key)
    }

    /// Chạy `action` của điều khiển (§11.4). Trả thông báo lỗi JS (UI hiện toast "Lỗi: …"), `nil` khi thành công.
    static func runAction(_ action: String, source: LegadoEngineSource) async throws -> String? {
        let rule = exploreUrl(of: source)
        return try await LegadoInteraction.$isInteractive.withValue(true) {
            try await LegadoEngineSession.run(source: source) { session in
                try session.runExploreAction(action, exploreUrl: rule)
            }
        }
    }
}
