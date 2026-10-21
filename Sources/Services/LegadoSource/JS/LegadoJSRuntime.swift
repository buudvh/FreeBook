import Foundation
import JavaScriptCore
import SwiftSoup

/// Runtime JavaScriptCore **riêng** của một phiên engine nguồn Legado (spec §6.1): `JSContext` mới, không dùng
/// `JSExecutor`. Chỉ chạy trên thread engine của phiên — mọi hàm bridge (`java.ajax`…) đồng bộ đối với script, nên
/// không bao giờ chạy trên main thread.
///
/// Ranh giới Swift↔JS hẹp: một block `__lgNative(lệnh, JSON) -> String` (xem `LegadoJSRuntime+Dispatch`), mọi đối
/// tượng nguồn dựng bằng JS (`LegadoJSBootstrap`). Phần tử HTML trao qua handle số nguyên (`elementHandles`), dọn khi
/// runtime giải phóng. Block chỉ giữ `weak self`; không lưu `JSValue` vào thuộc tính.
final class LegadoJSRuntime {
    weak var session: LegadoEngineSession?
    let context: JSContext
    var elementHandles: [Element] = []
    /// Font đã nạp bằng `java.queryTTF`/`queryBase64TTF` (JS giữ chỉ số), giải phóng cùng runtime.
    var fontHandles: [LegadoFont] = []
    private var capturedError: String?

    init(session: LegadoEngineSession) {
        self.session = session
        context = JSContext()
        context.name = "Legado: \(session.source.name)"
        context.exceptionHandler = { [weak self] _, exception in
            self?.capturedError = Self.describe(exception)
        }
        let native: @convention(block) (String, String) -> String = { [weak self] command, arguments in
            guard let self else { return "" }
            return self.dispatchNative(command, arguments)
        }
        context.setObject(native, forKeyedSubscript: "__lgNative" as NSCopying & NSObjectProtocol)
        for script in LegadoJSBootstrap.scripts {
            capturedError = nil
            context.evaluateScript(script)
            if let error = capturedError {
                AppLogger.shared.log("❌ [Legado] Lỗi nạp bootstrap JS: \(error)")
                session.diagnostics.record(.javaScript, "bootstrap: \(error)")
            }
        }
        capturedError = nil
    }

    // MARK: - Chạy mã

    /// Chạy một đoạn JS; giá trị trả = giá trị hoàn tất của câu lệnh cuối, hoặc `result` nếu đoạn mã gán lại `result`
    /// mà giá trị hoàn tất là `undefined` (§6.1). Lỗi JS ⇒ `.null` + ghi chẩn đoán; chỉ ném `CancellationError`.
    /// Gọi lồng (JS → `java.getString` → rule → JS) an toàn: biến môi trường được lưu và khôi phục quanh mỗi lần chạy.
    func evaluate(_ code: String, bindings: LegadoJSBindings) throws -> LegadoContentNode {
        let outcome = try evaluateRaw(code, bindings: bindings)
        guard outcome.error == nil else { return .null }
        return export(outcome.value)
    }

    /// Như `evaluate` nhưng trả **giá trị JS thô** và thông báo lỗi (lỗi đã được ghi chẩn đoán). Dùng khi cần phân biệt
    /// "JS ném lỗi" với "JS trả `undefined`" (`login()`, `loginCheckJs`, `imageDecode`).
    func evaluateRaw(_ code: String, bindings: LegadoJSBindings) throws -> (value: JSValue?, error: String?) {
        guard let session else { throw CancellationError() }
        try session.checkCancellation()
        let saved = LegadoJSBindings.names.map { context.objectForKeyedSubscript($0) }
        defer {
            for (index, name) in LegadoJSBindings.names.enumerated() {
                context.setObject(saved[index], forKeyedSubscript: name as NSCopying & NSObjectProtocol)
            }
        }
        apply(bindings)
        let resultBefore = context.objectForKeyedSubscript("result")
        let outerError = capturedError
        capturedError = nil
        defer { capturedError = outerError }

        var value: JSValue? = context.evaluateScript(code)
        if let error = capturedError, error.contains("Return statements are only valid inside functions") {
            capturedError = nil
            value = context.evaluateScript("(function(){\n" + code + "\n}).call(this)")
        }
        try session.checkCancellation()
        if let error = capturedError {
            capturedError = nil
            session.diagnostics.record(.javaScript, error)
            return (nil, error)
        }
        if value?.isUndefined ?? true, let after = context.objectForKeyedSubscript("result"),
           let before = resultBefore, !after.isEqual(to: before) {
            value = after
        }
        return (value, nil)
    }

    /// Option `js` của URL (§3.6): `java.url` = URL hiện tại, `java.headerMap` = header hiện tại; JS sửa chúng.
    /// Giá trị trả là chuỗi không rỗng ⇒ dùng làm URL (U11), ngược lại dùng `java.url`.
    func evaluateOptionScript(_ code: String, url: String, headers: [(name: String, value: String)],
                              bindings: LegadoJSBindings) throws -> (url: String, headers: [(name: String, value: String)]) {
        let headerObject = LegadoEngineJSON.object(headers.map { (key: $0.name, value: LegadoEngineJSON.string($0.value)) })
        runQuietly("java.url = \(LegadoEngineJSON.quoted(url)); java.headerMap = __lg.map(\(headerObject.compactText));")
        var arguments = bindings
        arguments.result = .string(url)
        let returned = try evaluate(code, bindings: arguments)
        let state = runQuietly("JSON.stringify({u: String(java.url), h: java.headerMap || {}})")
        runQuietly("delete java.url; delete java.headerMap;")

        var finalURL = url
        var finalHeaders = headers
        if let text = state, let json = LegadoEngineJSONParser.parse(text) {
            finalURL = json["u"]?.stringValue ?? url
            if let mapped = json["h"] { finalHeaders = LegadoHeaderParser.pairs(from: mapped) }
        }
        if case .string(let text) = returned, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalURL = text
        }
        return (finalURL, finalHeaders)
    }

    /// Nạp `jsLib` (§5.8): mã JS, hoặc object JSON `{tên: url}` (tải mỗi URL một lần, đệm bền theo URL).
    /// Lỗi khi nạp chỉ ghi chẩn đoán; rule vẫn chạy (lỗi sẽ hiện ở chỗ gọi hàm thiếu).
    func loadLibrary(_ jsLib: String) {
        guard let session else { return }
        let trimmed = jsLib.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bindContexts()
        if trimmed.hasPrefix("{"), let entries = LegadoEngineJSONParser.parse(trimmed, lenient: true)?.objectEntries,
           !entries.isEmpty, entries.allSatisfy({ LegadoURLResolver.hasHTTPScheme($0.value.scalarString) }) {
            for entry in entries {
                guard let script = session.libraryScript(url: entry.value.scalarString) else {
                    session.diagnostics.record(.javaScript, "jsLib: không tải được \(entry.key)")
                    continue
                }
                runLibrary(script, name: entry.key)
            }
            return
        }
        runLibrary(trimmed, name: "jsLib")
    }

    private func runLibrary(_ code: String, name: String) {
        let outer = capturedError
        capturedError = nil
        context.evaluateScript(code)
        if let error = capturedError {
            session?.diagnostics.record(.javaScript, "\(name): \(error)")
        }
        capturedError = outer
    }

    /// Chạy mã nội bộ, bỏ qua lỗi; trả chuỗi kết quả (nếu có).
    @discardableResult
    func runQuietly(_ code: String) -> String? {
        let outer = capturedError
        capturedError = nil
        let value = context.evaluateScript(code)
        let failed = capturedError != nil
        capturedError = outer
        guard !failed, let value, !value.isUndefined, !value.isNull else { return nil }
        return value.toString()
    }

    // MARK: - Biến môi trường

    private func apply(_ bindings: LegadoJSBindings) {
        if let response = bindings.responseResult {
            setGlobal("result", callHelper("__lgMakeResponse", response.compactText))
        } else if let map = bindings.mapResult {
            let object = LegadoEngineJSON.object(map.sorted { $0.key < $1.key }
                .map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) })
            setGlobal("result", callHelper("__lgMakeMap", object.compactText))
        } else if let bytes = bindings.bytesResult {
            setGlobal("result", callHelper("__lgMakeBytes", Self.hex(bytes)))
        } else {
            setGlobal("result", bindings.result.map { importValue($0) } ?? undefinedValue)
        }
        setGlobal("baseUrl", jsString(bindings.baseUrl))
        setGlobal("src", jsString(bindings.src))
        setGlobal("key", jsString(bindings.key))
        if let page = bindings.page, let value = JSValue(int32: Int32(clamping: page), in: context) {
            setGlobal("page", value)
        } else {
            setGlobal("page", undefinedValue)
        }
        setGlobal("title", jsString(bindings.title))
        setGlobal("nextChapterUrl", jsString(bindings.nextChapterUrl))
        bindContexts()
    }

    /// Gắn `book`/`chapter` theo ngữ cảnh hiện tại của phiên (không có ⇒ `null`).
    func bindContexts() {
        var bookId: Any = NSNull()
        var chapterId: Any = NSNull()
        if let book = session?.book { bookId = String(ObjectIdentifier(book).hashValue) }
        if let chapter = session?.chapter { chapterId = String(ObjectIdentifier(chapter).hashValue) }
        _ = context.objectForKeyedSubscript("__lgBindContexts")?.call(withArguments: [bookId, chapterId])
    }

    private func setGlobal(_ name: String, _ value: JSValue) {
        context.setObject(value, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
    }

    /// Gọi một hàm dựng của bootstrap (`__lgMakeResponse`…) với một chuỗi; lỗi ⇒ `undefined`.
    func callHelper(_ name: String, _ argument: String) -> JSValue {
        guard let function = context.objectForKeyedSubscript(name), !function.isUndefined,
              let value = function.call(withArguments: [argument]) else { return undefinedValue }
        return value
    }

    var undefinedValue: JSValue {
        JSValue(undefinedIn: context)
    }

    private func jsString(_ text: String?) -> JSValue {
        guard let text, let value = JSValue(object: text, in: context) else { return undefinedValue }
        return value
    }

    // MARK: - Lỗi

    private static func describe(_ exception: JSValue?) -> String {
        guard let exception else { return "Lỗi JS không rõ" }
        let message = exception.toString() ?? "Lỗi JS không rõ"
        if let line = exception.objectForKeyedSubscript("line"), line.isNumber {
            return "\(message) (dòng \(line.toInt32()))"
        }
        return message
    }

    func raise(_ message: String) {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
    }
}
