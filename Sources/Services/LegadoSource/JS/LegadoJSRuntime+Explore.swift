import Foundation
import UIKit

/// `infoMap` (spec §11.3), `java.refreshExplore`/`source.refreshExplore` (§11.5), `java.searchBook` (§11.6) và các hàm
/// UI nhỏ (`java.openUrl`, `java.copyText`, `refreshContent`, §14.5) — đều phát qua `LegadoPresentationEventCenter`.
extension LegadoJSRuntime {
    func nativeExplore(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        switch command {
        case "infoGet":
            guard let value = session.exploreInfo?[text(of: arguments[0])] else { return "null" }
            return LegadoEngineJSON.quoted(value)
        case "infoSet":
            let key = text(of: arguments[0])
            session.setExploreInfoValue(arguments.isNull(1) ? nil : text(of: arguments[1]), forKey: key)
            return ""
        case "infoKeys":
            return Self.jsonArray((session.exploreInfo ?? [:]).keys.sorted())
        case "infoAll":
            let entries = (session.exploreInfo ?? [:]).sorted { $0.key < $1.key }
                .map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) }
            return LegadoEngineJSON.object(entries).compactText
        case "refreshExplore":
            // Sự kiện cho UI chỉ phát khi có người dùng — kiểm tra hàng loạt / tải nền không được tự bật màn hình.
            guard session.allowsUserInteraction else { return "" }
            LegadoPresentationEventCenter.shared.scheduleExploreRefresh(sourceKey: session.source.key)
            return ""
        case "searchBook":
            let keyword = text(of: arguments[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty, session.allowsUserInteraction else { return "" }
            let scope = arguments.plainString(1)
            LegadoPresentationEventCenter.shared.send(.searchBook(keyword: keyword, sourceKey: Self.searchScope(scope)))
            return ""
        case "openUrl":
            let url = text(of: arguments[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return "" }
            if session.allowsUserInteraction {
                LegadoPresentationEventCenter.shared.send(.openURL(url: url, sourceKey: session.source.key))
            } else {
                session.diagnostics.record(.info, "java.openUrl bỏ qua (không có người dùng): \(url.prefix(160))")
            }
            return ""
        case "copyText":
            let value = text(of: arguments[0])
            guard session.allowsUserInteraction else { return "" }
            Task { @MainActor in UIPasteboard.general.string = value }
            return ""
        case "refreshContent":
            guard session.allowsUserInteraction else { return "" }
            LegadoPresentationEventCenter.shared.send(.refreshContent(sourceKey: session.source.key))
            return ""
        default:
            return nil
        }
    }

    /// Tham số 2 của `java.searchBook`: `bookSourceUrl` (JS đã đổi đối tượng `source` thành khoá), hoặc chuỗi
    /// `tên::khoá` (lấy phần sau `::`); rỗng ⇒ mọi nguồn đang bật.
    static func searchScope(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let separator = raw.range(of: "::") {
            let key = String(raw[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        }
        return raw
    }
}
