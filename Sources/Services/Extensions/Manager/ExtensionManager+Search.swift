import Foundation
import JavaScriptCore

/// Script `search` — `execute(query, page)`. Theo hợp đồng tiện ích, `page` là token trang **mờ**: trang 1 gửi `"1"`
/// (tiện ích riêng của FreeBook có thể `parseInt(page)`), trang sau gửi **nguyên văn** token mà lượt trước trả ở đối số
/// thứ hai của `Response.success(data, next)`. Token rỗng / không có ⇒ hết trang.
extension ExtensionManager {
    // search: Gọi script JS tìm kiếm sách từ nguồn truyện — chỉ lấy kết quả của trang `page`, bỏ token trang kế.
    // Giữ cho bộ kiểm tra tiện ích, bộ nghiệm thu và "tìm mọi nguồn" (chỉ trang 1).
    public func search(localPath: String, downloadUrl: String = "", query: String, page: Int, configJson: String = "{}") async throws -> [ExtensionItemResult] {
        try await searchPage(localPath: localPath, downloadUrl: downloadUrl, query: query, pageToken: String(page), configJson: configJson).results
    }

    /// Một trang kết quả tìm kiếm [ExtensionItemResult] kèm token trang kế (`nil` ⇒ hết trang).
    public func searchPage(localPath: String, downloadUrl: String = "", query: String, pageToken: String, configJson: String = "{}") async throws -> (results: [ExtensionItemResult], nextPage: String?) {
        // Lấy đường dẫn file script JS tìm kiếm ("search")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "search")
        let scriptName = scriptUrl.lastPathComponent
        AppLogger.shared.log("🔍 [ExtensionManager][\(scriptName)]: arguments=[\(query), \(pageToken)], query=\(query), page=\(pageToken), configJson=\(configJson)")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)

        // Khởi tạo bộ thực thi Javascript (JSExecutor)
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        // Nạp và gộp các cấu hình của extension (mặc định + người dùng tuỳ chỉnh)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs) // Tiêm các hàm global (Html, fetch, Response, Console) vào JSContext

        do {
            // Chạy hàm "execute(query, page)" bất đồng bộ bên trong JS Engine
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [query, pageToken])
            // Token đọc trên object gốc: `verifyJSResponse` chỉ trả phần `data`.
            let nextPage = Self.searchNextPageToken(jsValue, executor: executor)
            let cleanVal = try verifyJSResponse(jsValue, extName: URL(fileURLWithPath: localPath).lastPathComponent, scriptName: "search")

            // Ép kiểu kết quả trả về của JS thành mảng bằng toDictionaryArray
            let jsArray = toDictionaryArray(cleanVal)

            // Ánh xạ sang `ExtensionItemResult` (đọc an toàn, bìa resolve theo host item → source): `+ItemParsing`.
            let sourceHost = ExtensionHostResolver.sourceUrl(localPath: localPath)
            let results = jsArray
                .map { Self.listItem(from: $0, sourceHost: sourceHost) }
                .filter { !$0.link.isEmpty }
            updateDiagnostics(action: "search", input: "query: \(query), page: \(pageToken)", status: "Success", details: "Parsed \(results.count) results, nextPage: \(nextPage ?? "nil")")
            return (results, nextPage)
        } catch {
            updateDiagnostics(action: "search", input: "query: \(query), page: \(pageToken)", status: "Error", details: error.localizedDescription)
            throw ExtensionLoadError.wrapping(error, executor: executor)
        }
    }

    /// Token trang kế: `next` của object script trả về (`Response.success(data, next)`); thiếu thì `Response.nextPage`
    /// toàn cục — giữ giá trị của lần gọi `Response.success` gần nhất. Chuỗi/số đều nhận; `null`, `"null"`,
    /// `"undefined"` và chuỗi rỗng ⇒ `nil`.
    private static func searchNextPageToken(_ raw: JSValue, executor: JSExecutor) -> String? {
        let own = raw.isObject ? JSValueReader.cleanString(raw.objectForKeyedSubscript("next")) : nil
        let token = own ?? JSValueReader.cleanString(
            executor.context.objectForKeyedSubscript("Response")?.objectForKeyedSubscript("nextPage")
        )
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return token
    }
}
