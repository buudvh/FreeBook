import Foundation
import JavaScriptCore

/// Phía Swift của `source.*` đăng nhập (spec §10.5–§10.6), form đăng nhập (`java.upLoginData`, `java.reLoginView`, §10.4),
/// ngữ cảnh `loginCheckJs` (`java.initUrl`, `getHeaderMap`, `getStrResponse`, §10.7) và trình duyệt/mã xác minh (§10.8).
extension LegadoJSRuntime {
    enum LoginCheckOutcome {
        case unchanged
        case body(String)
        case response(LegadoEngineJSON)
    }

    func nativeLogin(_ command: String, _ arguments: LegadoJSArguments, _ session: LegadoEngineSession) throws -> String? {
        let sourceKey = session.source.key
        switch command {
        case "loginInfoGet":
            return session.loginInfoText.map { LegadoEngineJSON.quoted($0) } ?? "null"
        case "loginInfoMap":
            return session.loginInfoObject.compactText
        case "loginInfoPut":
            session.storeLoginInfo(text(of: arguments[0]))
            return ""
        case "loginInfoRemove":
            session.storeLoginInfo(nil)
            return ""
        case "loginHeaderGet":
            return session.loginHeaderText.map { LegadoEngineJSON.quoted($0) } ?? "null"
        case "loginHeaderMap":
            let pairs = session.loginHeaderText.map { LegadoEngineSession.loginHeaderPairs($0) } ?? []
            return LegadoEngineJSON.object(pairs.map { (key: $0.name, value: LegadoEngineJSON.string($0.value)) }).compactText
        case "loginHeaderPut":
            LegadoLoginStore.shared.setValue(text(of: arguments[0]), item: .header, sourceKey: sourceKey)
            return ""
        case "loginHeaderRemove":
            LegadoLoginStore.shared.setValue(nil, item: .header, sourceKey: sourceKey)
            return ""
        case "sourceLogin":
            try session.runHeadlessLogin()
            return ""

        case "upLoginData":
            guard let form = session.loginForm else { throw LegadoJSNativeError("java.upLoginData chỉ có trong form đăng nhập") }
            if let values = stringMap(arguments[0]) {
                form.update(values)
            } else {
                form.requestCommit()
            }
            return ""
        case "reLoginView":
            session.loginForm?.requestReload()
            return ""

        case "lcInitUrl":
            try session.loginCheckInitURL()
            return ""
        case "lcHeaders":
            let headers = session.loginCheckContext?.request.headers ?? []
            return LegadoEngineJSON.object(headers.map { (key: $0.name, value: LegadoEngineJSON.string($0.value)) }).compactText
        case "lcResend":
            let headers = jsonObject(arguments[0]).map { LegadoHeaderParser.pairs(from: $0) }
            let response = try session.loginCheckResend(headers: headers, script: arguments.plainString(1),
                                                        sourceRegex: arguments.plainString(2))
            return Self.responseJSON(response).compactText

        case "startBrowser":
            session.jsStartBrowser(url: text(of: arguments[0]), title: text(of: arguments[1]))
            return ""
        case "startBrowserAwait":
            let response = try session.jsStartBrowserAwait(url: text(of: arguments[0]), title: text(of: arguments[1]),
                                                           refetch: arguments.isNull(2) ? true : arguments.bool(2),
                                                           html: arguments.plainString(3))
            return Self.responseJSON(response).compactText
        case "verificationCode":
            return try session.jsVerificationCode(imageURL: text(of: arguments[0]))
        default:
            return nil
        }
    }

    /// Map chuỗi từ đối số JS (object JS `{$json}`, chuỗi JSON object, map của bridge); `nil` khi không phải object.
    func stringMap(_ descriptor: LegadoEngineJSON) -> [String: String]? {
        guard let entries = jsonObject(descriptor)?.objectEntries else { return nil }
        return LegadoEngineSession.stringMap(entries)
    }

    /// Object JSON của một đối số (`{$json}`, chuỗi JSON object, hoặc object thường); `nil` khi không phải object.
    func jsonObject(_ descriptor: LegadoEngineJSON) -> LegadoEngineJSON? {
        var object: LegadoEngineJSON?
        if let json = descriptor["$json"] {
            object = json
        } else if case .string(let text) = descriptor {
            object = LegadoEngineJSONParser.parse(text, lenient: true)
        } else if descriptor.objectEntries != nil {
            object = descriptor
        }
        guard let object, object.objectEntries != nil else { return nil }
        return object
    }

    // MARK: - loginCheckJs

    func prepareLoginCheck(ruleUrl: String) {
        runQuietly("java.ruleUrl = \(LegadoEngineJSON.quoted(ruleUrl)); if (__lg.resetLoginCheck) { __lg.resetLoginCheck(); }")
    }

    func finishLoginCheck() {
        runQuietly("delete java.ruleUrl; if (__lg.resetLoginCheck) { __lg.resetLoginCheck(); }")
    }

    /// Phân loại giá trị trả của `loginCheckJs` (đối tượng phản hồi / chuỗi / khác).
    func classifyLoginCheck(_ value: JSValue?) -> LoginCheckOutcome {
        guard let value, let classify = context.objectForKeyedSubscript("__lgClassify"), !classify.isUndefined,
              let text = classify.call(withArguments: [value])?.toString(),
              let json = LegadoEngineJSONParser.parse(text) else { return .unchanged }
        switch json["k"]?.stringValue {
        case "resp":
            guard let response = json["r"] else { return .unchanged }
            return .response(response)
        case "str":
            return .body(json["s"]?.stringValue ?? "")
        default:
            return .unchanged
        }
    }

    // MARK: - Form đăng nhập

    /// Định nghĩa `java.upLoginData`/`java.reLoginView` cho phiên form đăng nhập (spec §10.4 mục 5). Ngoài form hai hàm
    /// này **không** tồn tại, để phép dò `typeof java.reLoginView == 'function'` của rule vẫn đi nhánh Android chính thức.
    func installLoginFormFunctions() {
        runQuietly("""
            java.upLoginData = function (m) { __lg.call('upLoginData', [m === undefined ? null : m]); };
            java.reLoginView = function () { __lg.call('reLoginView', []); };
            """)
    }
}
