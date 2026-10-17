import Foundation
import JavaScriptCore

/// Script `explore`: trang Khám phá dạng section theo hợp đồng extension (extension-api.md). Tiện ích khai cả
/// `explore` lẫn `home` thì **`explore` thắng** — `DiscoveryView` không gọi `home` nữa, tab `genre` giữ nguyên.
///
/// Quy tắc parse:
/// - Section: `type` không phân biệt hoa thường; rỗng/lạ ⇒ bỏ cả section. `id` rỗng ⇒ `<type>_<vị trí>` (vị trí
///   trong mảng gốc); `id` trùng ⇒ thêm hậu tố. `shape` thiếu/lạ ⇒ `book`. Section không còn item nào ⇒ bỏ.
/// - Item: đọc qua `listItem` (an toàn với `undefined`/`null`, bìa resolve host item → `source`); tên rỗng ⇒ bỏ.
///   **Không** lọc trùng — hợp đồng để việc đó cho script.
/// - Action (`more`, `action`): thiếu `type` ⇒ bỏ action; `type` lạ ⇒ `.unsupported`. `input` giữ nguyên văn
///   (với `detail` là URL item — khoá nhận diện sách).
extension ExtensionManager {
    func explore(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [ExploreSection] {
        do {
            let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "explore")
            let scriptName = scriptUrl.lastPathComponent
            AppLogger.shared.log("🔍 [ExtensionManager][\(scriptName)]: arguments=[], configJson=\(configJson)")
            let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)

            let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
            let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
            executor.injectGlobals(configs)

            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [])
            let cleanVal = try verifyJSResponse(jsValue, extName: URL(fileURLWithPath: localPath).lastPathComponent, scriptName: "explore")
            let sourceHost = ExtensionHostResolver.sourceUrl(localPath: localPath)
            // JSValue gắn với JSContext của executor: ánh xạ xong trong lúc executor còn sống.
            let sections = withExtendedLifetime(executor) {
                Self.exploreSections(from: cleanVal, sourceHost: sourceHost)
            }
            let itemCount = sections.reduce(0) { $0 + $1.items.count }
            updateDiagnostics(action: "explore", input: "localPath: \(localPath)", status: "Success", details: "Parsed \(sections.count) sections, \(itemCount) items")
            return sections
        } catch {
            if !(error is CancellationError) {
                AppLogger.shared.log("❌ [ExtensionManager] explore lỗi: \(error.localizedDescription)")
            }
            updateDiagnostics(action: "explore", input: "localPath: \(localPath)", status: "Error", details: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Parse

    /// Mảng section gốc → `[ExploreSection]`. Giá trị không phải mảng ⇒ `[]`.
    internal static func exploreSections(from value: JSValue, sourceHost: String?) -> [ExploreSection] {
        var sections: [ExploreSection] = []
        var usedIds = Set<String>()
        for (index, raw) in exploreElements(value).enumerated() where JSValueReader.isPlainObject(raw) {
            let rawType = exploreToken(raw.forProperty("type"))
            guard let kind = exploreSectionKind(rawType) else {
                if !rawType.isEmpty {
                    AppLogger.shared.log("⚠️ [ExtensionManager] explore: bỏ section kiểu lạ '\(rawType)'")
                }
                continue
            }
            let baseId = ExtensionHostResolver.nonEmpty(JSValueReader.cleanString(raw.forProperty("id"))) ?? "\(rawType)_\(index)"
            var id = baseId
            var suffix = 2
            while usedIds.contains(id) {
                id = "\(baseId)_\(suffix)"
                suffix += 1
            }
            usedIds.insert(id)

            let items = exploreItems(raw.forProperty("items"), sectionId: id, sourceHost: sourceHost)
            guard !items.isEmpty else { continue }
            sections.append(ExploreSection(
                id: id,
                title: exploreText(raw.forProperty("title")),
                subtitle: exploreText(raw.forProperty("subtitle")),
                kind: kind,
                shape: ExploreSection.Shape(rawValue: exploreToken(raw.forProperty("shape"))) ?? .book,
                items: items,
                more: exploreAction(raw.forProperty("more"))
            ))
        }
        return sections
    }

    /// Các item của một section; phần tử không phải object hoặc tên rỗng ⇒ bỏ.
    private static func exploreItems(_ value: JSValue?, sectionId: String, sourceHost: String?) -> [ExploreItem] {
        var items: [ExploreItem] = []
        for raw in exploreElements(value) where JSValueReader.isPlainObject(raw) {
            var dict: [String: JSValue] = [:]
            for key in JSValueReader.keys(raw) {
                dict[key] = raw.forProperty(key)
            }
            let base = listItem(from: dict, sourceHost: sourceHost)
            let name = base.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            items.append(ExploreItem(
                id: "\(sectionId)#\(items.count)",
                name: name,
                cover: base.cover,
                link: base.link,
                description: base.description.trimmingCharacters(in: .whitespacesAndNewlines),
                tag: base.tag,
                host: base.host,
                type: base.type.lowercased(),
                action: exploreAction(dict["action"])
            ))
        }
        return items
    }

    /// `more` của section / `action` của item. Không phải object hoặc thiếu `type` ⇒ `nil`.
    private static func exploreAction(_ value: JSValue?) -> ExploreAction? {
        guard let value, JSValueReader.isPlainObject(value) else { return nil }
        let rawType = exploreToken(value.forProperty("type"))
        guard !rawType.isEmpty else { return nil }
        return ExploreAction(
            kind: ExploreAction.Kind(rawValue: rawType) ?? .unsupported,
            rawType: rawType,
            name: exploreText(value.forProperty("name")),
            script: exploreText(value.forProperty("script")),
            input: JSValueReader.cleanString(value.forProperty("input")) ?? ""
        )
    }

    /// Phần tử của mảng JS. Nhận cả đối tượng giống mảng (có `length` là số) — cùng độ khoan dung với
    /// `toDictionaryArray` của các script danh sách; giá trị khác ⇒ `[]`.
    private static func exploreElements(_ value: JSValue?) -> [JSValue] {
        guard let value, JSValueReader.isPresent(value), value.isObject else { return [] }
        if value.isArray { return JSValueReader.array(value) }
        guard let lengthValue = value.forProperty("length"), lengthValue.isNumber else { return [] }
        let length = Int(lengthValue.toInt32())
        guard length > 0 else { return [] }
        return (0..<length).compactMap { index -> JSValue? in value.atIndex(index) }
    }

    /// `type` section → kiểu bố cục. Nhận thêm vài biến thể chính tả gặp ở script thực tế của `horizontal_list`.
    private static func exploreSectionKind(_ token: String) -> ExploreSection.Kind? {
        let key = token.replacingOccurrences(of: "-", with: "_")
        if let kind = ExploreSection.Kind(rawValue: key) { return kind }
        return ["horizontallist", "horizental_list"].contains(key) ? .horizontalList : nil
    }

    /// Chuỗi đã trim + chữ thường (`type`, `shape`); thiếu ⇒ `""`.
    private static func exploreToken(_ value: JSValue?) -> String {
        exploreText(value).lowercased()
    }

    /// Chuỗi hiển thị đã trim; thiếu/`undefined`/`null` ⇒ `""`.
    private static func exploreText(_ value: JSValue?) -> String {
        (JSValueReader.cleanString(value) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
