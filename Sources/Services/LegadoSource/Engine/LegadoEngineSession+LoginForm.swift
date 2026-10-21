import Foundation
import JavaScriptCore

/// Dựng form đăng nhập từ `loginUi` (spec §10.3) và chạy nút/đăng nhập của form (§10.4) trong một phiên.
extension LegadoEngineSession {
    /// Các mục của form. `loginUi` là mảng JSON (lenient) hoặc JS (`@js:`/`<js>`) trả mảng/chuỗi JSON; đánh giá lại mỗi lần
    /// mở form. Giá trị khởi đầu: `savedValues[name]` → `default` → phần tử đầu `chars` (select/toggle).
    func loginFormFields(savedValues: [String: String]) throws -> [LegadoLoginField] {
        let raw = sourceField("loginUi").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let lower = raw.lowercased()
        let items: [LegadoEngineJSON]
        if lower.hasPrefix("@js:") || lower.hasPrefix("<js>") {
            let value = try evaluateScript(Self.strippedScript(raw), result: nil, baseUrl: sourceBase, src: nil)
            items = Self.jsonItems(from: value)
        } else {
            items = LegadoEngineJSONParser.parse(raw, lenient: true)?.arrayValue ?? []
            if items.isEmpty { diagnostics.record(.ruleSyntax, "loginUi không đọc được thành mảng") }
        }
        var fields: [LegadoLoginField] = []
        for (index, item) in items.enumerated() where item.objectEntries != nil {
            let name = item["name"]?.scalarString ?? ""
            let actionText = item["action"]?.scalarString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let action: String? = actionText.isEmpty ? nil : actionText
            guard let kind = Self.loginFieldKind(item["type"]?.scalarString ?? "", hasAction: action != nil) else { continue }
            let chars = item["chars"]?.arrayValue?.map { $0.scalarString } ?? []
            let defaultValue = item["default"].flatMap { $0.isNull ? nil : $0.scalarString }
            let hintValue = item["hint"] ?? item["placeholder"]
            var value = savedValues[name] ?? defaultValue ?? ""
            if kind == .select || kind == .toggle, !chars.isEmpty, !chars.contains(value) {
                value = defaultValue.flatMap { chars.contains($0) ? $0 : nil } ?? chars[0]
            }
            let label = try viewNameLabel(item["viewName"], fallback: name)
            fields.append(LegadoLoginField(
                id: index, name: name, label: label, kind: kind,
                action: action, chars: chars, defaultValue: defaultValue, hint: hintValue.map { $0.scalarString },
                style: LegadoFlexStyle.parse(item["style"]), value: value
            ))
        }
        return fields
    }

    /// `type` của mục → kiểu hiển thị; kiểu lạ có `action` ⇒ nút, không ⇒ bỏ (`nil`).
    static func loginFieldKind(_ raw: String, hasAction: Bool) -> LegadoLoginField.Kind? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "text", "input": return .text
        case "password": return .password
        case "select": return .select
        case "toggle": return .toggle
        case "button": return .button
        case "title": return .title
        default: return hasAction ? .button : nil
        }
    }

    /// `viewName` là **biểu thức JS** cho nhãn (`"'密码'"`, IIFE đọc trạng thái); lỗi/rỗng ⇒ `fallback`.
    func viewNameLabel(_ raw: LegadoEngineJSON?, fallback: String) throws -> String {
        let code = raw?.scalarString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !code.isEmpty else { return fallback }
        let value = try evaluateScript("(" + code + "\n)", result: nil, baseUrl: sourceBase, src: nil).finalString
        return value.isEmpty ? fallback : value
    }

    /// Kết quả JS → các phần tử mảng JSON (mảng, object đơn, chuỗi JSON, danh sách).
    static func jsonItems(from value: LegadoContentNode) -> [LegadoEngineJSON] {
        switch value {
        case .json(let json):
            return json.arrayValue ?? [json]
        case .string(let text):
            let parsed = LegadoEngineJSONParser.parse(text, lenient: true)
            return parsed?.arrayValue ?? parsed.map { [$0] } ?? []
        case .list(let items):
            return items.compactMap { item -> LegadoEngineJSON? in
                switch item {
                case .json(let json): return json
                case .string(let text): return LegadoEngineJSONParser.parse(text, lenient: true)
                default: return nil
                }
            }
        default:
            return []
        }
    }

    // MARK: - Nút & đăng nhập của form

    /// Nút trong form (§10.4 bước 2): chạy toàn bộ `loginUrl` (định nghĩa hàm), `result` = map giá trị **hiện tại** trên
    /// form (`result.get(k)` lẫn `result[k]`), rồi chạy `action` như một đoạn JS. Trả thông báo lỗi JS nếu có.
    func runLoginFormAction(_ action: String, values: [String: String]) throws -> String? {
        let form = LegadoLoginFormState(values: values)
        loginForm = form
        runtime.installLoginFormFunctions()
        if let script = loginScript {
            _ = try runtime.evaluateRaw(script, bindings: jsBindings(result: nil, baseUrl: sourceBase, src: nil))
        }
        var bindings = jsBindings(result: nil, baseUrl: sourceBase, src: nil)
        bindings.mapResult = values
        let outcome = try runtime.evaluateRaw(action, bindings: bindings)
        return outcome.error
    }

    /// Nút "Đăng nhập" (§10.4 bước 3): giá trị mọi mục mang dữ liệu thành thông tin đăng nhập **tạm**, chạy `loginUrl`
    /// rồi `login()`. Thành công ⇒ trả thông tin cuối (có thể đã bị `putLoginInfo` sửa) để lớp gọi lưu bền.
    func runLoginFormSubmit(values: [String: String]) throws -> (success: Bool, info: [String: String], error: String?) {
        guard let script = loginScript else {
            return (false, values, "Nguồn không có hàm đăng nhập (loginUrl không phải JS)")
        }
        loginForm = LegadoLoginFormState(values: values)
        runtime.installLoginFormFunctions()
        pendingLoginInfo = values
        let errorsBefore = diagnostics.count(of: .javaScript)
        let success = try runLoginFunction(script: script)
        let info = pendingLoginInfo ?? values
        pendingLoginInfo = nil
        var message: String?
        if !success {
            let errors = diagnostics.entries.filter { $0.kind == .javaScript }
            message = errors.count > errorsBefore ? errors.last?.message : "login() trả về false"
        }
        return (success, info, message)
    }
}
