import Foundation
import JavaScriptCore
import SwiftSoup

/// Nhóm `java.*` còn lại: túi biến, xử lý chuỗi, bóc tách lồng nhau, và các hàm ngoài phạm vi.
extension LegadoJSBridge {

    // MARK: - Túi biến

    internal static func installVariables(_ java: JSValue?, runtime: LegadoJSRuntime) {
        let put: @convention(block) (String?, JSValue?) -> String = { key, value in
            guard let key else { return "" }
            let text = stringify(value)
            runtime.variableBag.put(key, text)
            return text
        }
        java?.setObject(put, forKeyedSubscript: "put" as NSCopying & NSObjectProtocol)

        let get: @convention(block) (String?) -> String = { key in
            guard let key else { return "" }
            return runtime.variableBag.get(key)
        }
        java?.setObject(get, forKeyedSubscript: "get" as NSCopying & NSObjectProtocol)
    }

    // MARK: - Xử lý chuỗi

    internal static func installText(_ java: JSValue?, runtime: LegadoJSRuntime) {
        let log: @convention(block) (JSValue?) -> Void = { value in
            let text = stringify(value)
            guard !text.isEmpty else { return }
            AppLogger.shared.log("📜 [LegadoJS] \(text.prefix(500))")
        }
        for name in ["log", "logType", "toast", "longToast"] {
            java?.setObject(log, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
        }

        let t2s: @convention(block) (String?) -> String = { input in
            guard let input else { return "" }
            return transform(input, name: "Traditional-Simplified", reverse: false)
        }
        java?.setObject(t2s, forKeyedSubscript: "t2s" as NSCopying & NSObjectProtocol)

        let s2t: @convention(block) (String?) -> String = { input in
            guard let input else { return "" }
            return transform(input, name: "Traditional-Simplified", reverse: true)
        }
        java?.setObject(s2t, forKeyedSubscript: "s2t" as NSCopying & NSObjectProtocol)

        /// `java.htmlFormat` — đổi HTML thành text nhiều dòng, giữ ngắt đoạn.
        let htmlFormat: @convention(block) (String?) -> String = { input in
            guard let input else { return "" }
            var text = input
            text = text.replacingOccurrences(
                of: "<br\\s*/?>|</p>|</div>",
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            let lines = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return lines.joined(separator: "\n")
        }
        java?.setObject(htmlFormat, forKeyedSubscript: "htmlFormat" as NSCopying & NSObjectProtocol)

        let timeFormat: @convention(block) (JSValue?) -> String = { value in
            let milliseconds = value?.toDouble() ?? 0
            guard milliseconds > 0 else { return "" }
            let date = Date(timeIntervalSince1970: milliseconds / 1000)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.string(from: date)
        }
        java?.setObject(timeFormat, forKeyedSubscript: "timeFormat" as NSCopying & NSObjectProtocol)

        let timeFormatUTC: @convention(block) (JSValue?, String?, JSValue?) -> String = { value, format, offset in
            let milliseconds = value?.toDouble() ?? 0
            guard milliseconds > 0 else { return "" }
            let date = Date(timeIntervalSince1970: milliseconds / 1000)
            let formatter = DateFormatter()
            formatter.dateFormat = (format?.isEmpty == false) ? format! : "yyyy-MM-dd HH:mm:ss"
            let hours = Int(offset?.toDouble() ?? 0)
            formatter.timeZone = TimeZone(secondsFromGMT: hours * 3600) ?? TimeZone(identifier: "UTC")
            return formatter.string(from: date)
        }
        java?.setObject(timeFormatUTC, forKeyedSubscript: "timeFormatUTC" as NSCopying & NSObjectProtocol)

        /// `java.toNumChapter` — đổi số Hán trong tên chương thành số Ả Rập.
        let toNumChapter: @convention(block) (String?) -> String = { input in
            guard let input else { return "" }
            return LegadoChapterNumber.normalize(input)
        }
        java?.setObject(toNumChapter, forKeyedSubscript: "toNumChapter" as NSCopying & NSObjectProtocol)

        let strToBytes: @convention(block) (String?, String?) -> [NSNumber] = { input, charset in
            guard let input,
                  let data = LegadoPercentEncoder.encodeToData(input, charset: charset) else { return [] }
            return data.map { NSNumber(value: $0) }
        }
        java?.setObject(strToBytes, forKeyedSubscript: "strToBytes" as NSCopying & NSObjectProtocol)

        let bytesToStr: @convention(block) (JSValue?, String?) -> String = { value, charset in
            guard let array = value?.toArray() else { return "" }
            let bytes = array.compactMap { ($0 as? NSNumber)?.uint8Value }
            return LegadoTextEncoding.decode(Data(bytes), declaredCharset: charset)
        }
        java?.setObject(bytesToStr, forKeyedSubscript: "bytesToStr" as NSCopying & NSObjectProtocol)

        let getWebViewUA: @convention(block) () -> String = {
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
                + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }
        java?.setObject(getWebViewUA, forKeyedSubscript: "getWebViewUA" as NSCopying & NSObjectProtocol)

        let androidId: @convention(block) () -> String = {
            // Không có Android ID trên iOS. Trả một chuỗi hex ổn định theo lần cài app để nguồn dùng
            // làm khoá thiết bị (một số API yêu cầu tham số này khác rỗng và không đổi giữa các lần gọi).
            let key = "legadoPseudoAndroidId"
            if let existing = UserDefaults.standard.string(forKey: key), existing.count == 16 {
                return existing
            }
            let generated = UUID().uuidString
                .replacingOccurrences(of: "-", with: "")
                .lowercased()
                .prefix(16)
            UserDefaults.standard.set(String(generated), forKey: key)
            return String(generated)
        }
        java?.setObject(androidId, forKeyedSubscript: "androidId" as NSCopying & NSObjectProtocol)
        _ = runtime
    }

    // MARK: - Bóc tách lồng nhau

    /// `java.getString(rule)`, `getStringList`, `getElement`, `getElements` — script gọi **lại** engine
    /// rule trên `result` hiện tại. Đây là lý do bridge phải nằm cùng tầng với evaluator.
    internal static func installParsing(_ java: JSValue?, runtime: LegadoJSRuntime) {
        let getString: @convention(block) (JSValue?, String?) -> String = { target, rule in
            guard let rule else { return "" }
            let html = stringify(target)
            guard let document = try? SwiftSoup.parse(html) else { return "" }
            return LegadoJsoupEngine.string(rule: rule, on: document) ?? ""
        }
        java?.setObject(getString, forKeyedSubscript: "getString" as NSCopying & NSObjectProtocol)

        let getStringList: @convention(block) (JSValue?, String?) -> [String] = { target, rule in
            guard let rule else { return [] }
            let html = stringify(target)
            guard let document = try? SwiftSoup.parse(html) else { return [] }
            return LegadoJsoupEngine.stringList(rule: rule, on: document)
        }
        java?.setObject(getStringList, forKeyedSubscript: "getStringList" as NSCopying & NSObjectProtocol)

        let getElement: @convention(block) (JSValue?, String?) -> String = { target, rule in
            guard let rule else { return "" }
            let html = stringify(target)
            guard let document = try? SwiftSoup.parse(html) else { return "" }
            let found = LegadoJsoupEngine.elements(rule: rule, on: document)
            guard let first = found.first else { return "" }
            return (try? first.outerHtml()) ?? ""
        }
        java?.setObject(getElement, forKeyedSubscript: "getElement" as NSCopying & NSObjectProtocol)

        let getElements: @convention(block) (JSValue?, String?) -> [String] = { target, rule in
            guard let rule else { return [] }
            let html = stringify(target)
            guard let document = try? SwiftSoup.parse(html) else { return [] }
            return LegadoJsoupEngine.elements(rule: rule, on: document)
                .compactMap { try? $0.outerHtml() }
        }
        java?.setObject(getElements, forKeyedSubscript: "getElements" as NSCopying & NSObjectProtocol)
        _ = runtime
    }

    // MARK: - Ngoài phạm vi

    internal static func installUnsupported(_ java: JSValue?, runtime: LegadoJSRuntime) {
        let webViewFamily: @convention(block) (JSValue?, JSValue?, JSValue?) -> String = { _, _, _ in
            runtime.noteUnsupported(.webViewRule)
            AppLogger.shared.log("⚠️ [LegadoJS] Nguồn gọi hàm WebView — chưa hỗ trợ, trả rỗng.")
            return ""
        }
        for name in [
            "webView", "webViewGetSource", "webViewGetOverrideUrl",
            "startBrowser", "startBrowserAwait", "getVerificationCode"
        ] {
            java?.setObject(webViewFamily, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
        }

        let fontFamily: @convention(block) (JSValue?, JSValue?, JSValue?) -> String = { _, _, _ in
            runtime.noteUnsupported(.fontDecode)
            return ""
        }
        for name in ["queryTTF", "queryBase64TTF", "replaceFont"] {
            java?.setObject(fontFamily, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
        }

        let noop: @convention(block) (JSValue?, JSValue?) -> String = { _, _ in "" }
        for name in [
            "importScript", "cacheFile", "downloadFile", "getFile", "readFile", "readTxtFile",
            "deleteFile", "unzipFile", "un7zFile", "unrarFile", "unArchiveFile", "getTxtInFolder",
            "openUrl", "openVideoPlayer", "refreshExplore", "toURL", "getReadBookConfig",
            "getThemeMode", "getThemeConfig"
        ] {
            java?.setObject(noop, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
        }
    }

    // MARK: - Tiện ích

    internal static func stringify(_ value: JSValue?) -> String {
        guard let value, !value.isUndefined, !value.isNull else { return "" }
        if value.isString { return value.toString() ?? "" }
        if value.isArray, let array = value.toArray() {
            return array.compactMap { LegadoJSON.string($0) }.joined(separator: "\n")
        }
        if value.isObject, let dictionary = value.toDictionary(),
           let encoded = LegadoJSON.encode(dictionary) {
            return encoded
        }
        return value.toString() ?? ""
    }

    private static func transform(_ input: String, name: String, reverse: Bool) -> String {
        let transform = StringTransform(rawValue: name)
        return input.applyingTransform(transform, reverse: reverse) ?? input
    }
}
