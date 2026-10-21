import Foundation
import JavaScriptCore

/// Đăng nhập trong phiên (spec §10.4–§10.6): khoá phụ của nguồn, thông tin/header đăng nhập, gắn header đăng nhập vào
/// request, `source.login()` không giao diện.
extension LegadoEngineSession {
    // MARK: - Khoá phụ của nguồn

    /// Giá trị chuỗi nguyên văn của một khoá trong JSON gốc của nguồn (`""` khi vắng/`null`).
    func sourceField(_ name: String) -> String {
        guard let value = rawSourceJSON[name], !value.isNull else { return "" }
        return value.scalarString
    }

    /// Bóc tiền tố `@js:` / khối `<js>…</js>` ở đầu chuỗi (nếu có).
    static func strippedScript(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("@js:") { return String(trimmed.dropFirst(4)) }
        if lower.hasPrefix("<js>") {
            var code = String(trimmed.dropFirst(4))
            if let close = code.range(of: "</js>", options: [.caseInsensitive, .backwards]) {
                code = String(code[..<close.lowerBound])
            }
            return code
        }
        return trimmed
    }

    /// `loginCheckJs` của nguồn (đã bóc tiền tố), `nil` khi rỗng.
    var loginCheckScript: String? {
        let code = Self.strippedScript(sourceField("loginCheckJs"))
        return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : code
    }

    /// `loginUrl` khi là JS (spec §10.2), đã bóc tiền tố; URL/rác ⇒ `nil`.
    var loginScript: String? {
        let raw = sourceField("loginUrl").trimmingCharacters(in: .whitespacesAndNewlines)
        guard LegadoLoginMode.isScript(raw) else { return nil }
        return Self.strippedScript(raw)
    }

    // MARK: - Thông tin đăng nhập (§10.5)

    /// Chuỗi JSON của thông tin đăng nhập: thông tin tạm của form đang gửi, không có thì bản đã lưu; chưa có ⇒ `nil`.
    var loginInfoText: String? {
        if let pending = pendingLoginInfo { return Self.jsonText(pending) }
        return LegadoLoginStore.shared.loginInfo(sourceKey: source.key)
    }

    /// Object JSON của thông tin đăng nhập (rỗng khi chưa có hoặc không phải object).
    var loginInfoObject: LegadoEngineJSON {
        guard let text = loginInfoText, let json = LegadoEngineJSONParser.parse(text, lenient: true),
              json.objectEntries != nil else { return .object([]) }
        return json
    }

    /// `source.putLoginInfo(json)` / `putLoginInfoMap(json)`; `nil` ⇒ `removeLoginInfo()`.
    func storeLoginInfo(_ text: String?) {
        LegadoLoginStore.shared.setValue(text, item: .info, sourceKey: source.key)
        guard pendingLoginInfo != nil else { return }
        if let text, let entries = LegadoEngineJSONParser.parse(text, lenient: true)?.objectEntries {
            pendingLoginInfo = Self.stringMap(entries)
        } else if text == nil {
            pendingLoginInfo = [:]
        }
    }

    static func jsonText(_ map: [String: String]) -> String {
        LegadoEngineJSON.object(map.sorted { $0.key < $1.key }.map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) })
            .compactText
    }

    static func stringMap(_ entries: [(key: String, value: LegadoEngineJSON)]) -> [String: String] {
        var output: [String: String] = [:]
        for entry in entries { output[entry.key] = entry.value.scalarString }
        return output
    }

    // MARK: - Header đăng nhập (§10.6)

    var loginHeaderText: String? {
        LegadoLoginStore.shared.loginHeader(sourceKey: source.key)
    }

    /// Chuỗi header đăng nhập → cặp header: object JSON ⇒ từng khoá; dạng `k=v; k2=v2` ⇒ header `Cookie` (U41);
    /// dạng khác ⇒ bỏ (nhưng `getLoginHeader()` vẫn trả nguyên văn).
    static func loginHeaderPairs(_ text: String) -> [(name: String, value: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("{") {
            guard let json = LegadoEngineJSONParser.parse(trimmed, lenient: true), json.objectEntries != nil else { return [] }
            return LegadoHeaderParser.pairs(from: json)
        }
        if trimmed.contains("=") { return [(name: "Cookie", value: trimmed)] }
        return []
    }

    /// Header đăng nhập cho request tới `url` (U42): chỉ khi tên miền gốc của đích trùng `bookSourceUrl` hoặc trang đang
    /// phân tích — tránh gửi token sang CDN/bên thứ ba. Bỏ vì khác tên miền ⇒ ghi chẩn đoán (mỗi host một lần).
    func loginHeaders(forURL url: String, pageURL: String?) -> [(name: String, value: String)] {
        guard let text = loginHeaderText else { return [] }
        let pairs = Self.loginHeaderPairs(text)
        guard !pairs.isEmpty else { return [] }
        if LegadoDomain.sameSite(url, source.baseURL) { return pairs }
        if let pageURL, LegadoDomain.sameSite(url, pageURL) { return pairs }
        if let host = LegadoURLResolver.host(of: url), reportedForeignLoginHosts.insert(host).inserted {
            diagnostics.record(.info, "Không gắn header đăng nhập cho tên miền khác: \(host)")
        }
        return []
    }

    // MARK: - source.login() (§10.4 mục 7)

    /// Đăng nhập **không giao diện** bằng thông tin đã lưu: chạy `loginUrl` rồi `login()`. `loginUrl` là URL ⇒ không làm
    /// gì. Gọi lồng trong chính `login()` ⇒ bỏ qua. Trả `true` khi `login()` chạy xong không lỗi và không trả `false`.
    @discardableResult
    func runHeadlessLogin() throws -> Bool {
        guard !isRunningLogin, let script = loginScript else { return false }
        return try runLoginFunction(script: script)
    }

    /// Chạy `loginUrl` (định nghĩa hàm) rồi `login()`; luật thành công §10.4 bước 3 (U37: trả `false` là thất bại).
    func runLoginFunction(script: String) throws -> Bool {
        isRunningLogin = true
        defer { isRunningLogin = false }
        let definition = try runtime.evaluateRaw(script, bindings: jsBindings(result: nil, baseUrl: sourceBase, src: nil))
        if definition.error != nil { return false }
        let outcome = try runtime.evaluateRaw("login()", bindings: jsBindings(result: nil, baseUrl: sourceBase, src: nil))
        guard outcome.error == nil else { return false }
        if let value = outcome.value, value.isBoolean, !value.toBool() { return false }
        return true
    }
}
