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
///
/// **Bộ nhớ**: API ObjC của JavaScriptCore đưa mọi `JSValue` vào autorelease pool hiện hành và giữ giá trị JS của nó khỏi
/// GC tới khi `JSValue` được nhả. Thread engine không có pool riêng, nên mọi điểm vào chạy JS (`evaluate`, `evaluateRaw`,
/// `runQuietly`, `callHelper`…) tự bọc `autoreleasepool`: hàng nghìn lần chạy rule trong một bước (mục lục 7.000 chương)
/// không dồn bộ nhớ tới khi hệ điều hành giết app.
final class LegadoJSRuntime {
    weak var session: LegadoEngineSession?
    let context: JSContext
    var elementHandles: [Element] = []
    /// Handle của từng node đã đăng ký (`register`): cùng node ⇒ cùng handle. An toàn vì `elementHandles` giữ mạnh mọi node
    /// nên `ObjectIdentifier` không bị tái dùng; ai cắt bớt `elementHandles` thì phải cắt cả bảng này.
    var elementHandleIndex: [ObjectIdentifier: Int] = [:]
    /// Font đã nạp bằng `java.queryTTF`/`queryBase64TTF` (JS giữ chỉ số), giải phóng cùng runtime.
    var fontHandles: [LegadoFont] = []
    private var capturedError: String?
    /// Dòng của ngoại lệ vừa ghi vào `capturedError` (≤ 0 = không có dòng dùng được).
    private var capturedErrorLine: Int32 = 0
    /// Số lần `evaluateRaw` đang chạy lồng nhau (JS → `java.getString` → rule → JS). Chỉ lần chạy lồng mới lưu/khôi phục
    /// biến môi trường.
    private var evaluationDepth = 0
    /// Bản Swift của chuỗi trang đang nằm ở `__lgSrcCache` bên JS (`pageValue`); `nil` = chưa có. Giá trị JS ở lại phía JS,
    /// không giữ `JSValue` ở đây.
    private var cachedPageText: String?

    init(session: LegadoEngineSession) {
        self.session = session
        context = JSContext()
        context.name = "Legado: \(session.source.name)"
        context.exceptionHandler = { [weak self] _, exception in
            self?.capturedError = Self.describe(exception)
            self?.capturedErrorLine = exception.map { Self.lineNumber(of: $0) } ?? 0
        }
        // Giữ `eval` gốc trước khi chạy bất kỳ mã nào (bootstrap, `jsLib`, rule): rule chạy bằng eval gián tiếp qua bản
        // này (`globalEval`), nên nguồn gán lại `eval` không ảnh hưởng. Thuộc tính ẩn, không ghi/xoá được.
        context.evaluateScript("Object.defineProperty(this, '\(Self.globalEvalName)', { value: eval });")
        // Ô ẩn giữ chuỗi trang lớn gần nhất (`pageValue`): chép vào JS một lần mỗi trang thay vì mỗi lần chạy rule.
        context.evaluateScript("Object.defineProperty(this, '\(Self.pageCacheName)', "
            + "{ value: undefined, writable: true, enumerable: false, configurable: false });")
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
    /// Gọi lồng (JS → `java.getString` → rule → JS) an toàn: lần chạy lồng lưu và khôi phục biến môi trường của lần ngoài.
    /// Cả lần chạy lẫn bước đổi kết quả (`__lgExport`) nằm trong một `autoreleasepool`.
    func evaluate(_ code: String, bindings: LegadoJSBindings) throws -> LegadoContentNode {
        try autoreleasepool { () throws -> LegadoContentNode in
            let outcome = try evaluateRaw(code, bindings: bindings)
            guard outcome.error == nil else { return .null }
            return export(outcome.value)
        }
    }

    /// Như `evaluate` nhưng trả **giá trị JS thô** và thông báo lỗi (lỗi đã được ghi chẩn đoán). Dùng khi cần phân biệt
    /// "JS ném lỗi" với "JS trả `undefined`" (`login()`, `loginCheckJs`, `imageDecode`).
    ///
    /// Rule chạy bằng **eval gián tiếp ở global** (§6.1, `globalEval`). `var`/`function` lên global và mọi `function`
    /// có ngay từ trước câu lệnh đầu, nên đoạn ném lỗi giữa chừng vẫn để lại hàm cho lần sau (luồng `loginUrl` →
    /// `login()`, nút form đăng nhập, `action` khám phá dựa vào điều này). `let`/`const`/`class` ở cấp ngoài cùng nằm
    /// trong phạm vi riêng của lần chạy nên không rò sang lần sau (hết lỗi `Can't create duplicate variable`, không che
    /// biến môi trường của lần sau). Giá trị trả = giá trị hoàn tất; số dòng lỗi theo code gốc. Khác chạy thẳng: code
    /// mở đầu bằng `"use strict"` thì `var`/`function` chỉ sống trong lần chạy đó. `return` ở cấp ngoài cùng ⇒ chạy
    /// code **gốc** trong hàm nhận biến môi trường làm tham số (`returnWrapperHead`).
    ///
    /// Mỗi lần chạy nằm trong một `autoreleasepool` (giá trị trả vẫn sống vì Swift giữ tham chiếu mạnh). Chỉ lần chạy
    /// **lồng** mới lưu và khôi phục 7 biến môi trường: lần ngoài cùng không cần, vì `apply` của lần sau gán lại cả 7.
    func evaluateRaw(_ code: String, bindings: LegadoJSBindings) throws -> (value: JSValue?, error: String?) {
        try autoreleasepool { () throws -> (value: JSValue?, error: String?) in
            guard let session else { throw CancellationError() }
            try session.checkCancellation()
            let isNested = evaluationDepth > 0
            evaluationDepth += 1
            defer { evaluationDepth -= 1 }
            var saved: [JSValue?] = []
            if isNested {
                saved = LegadoJSBindings.names.map { context.objectForKeyedSubscript($0) }
            }
            defer {
                if isNested {
                    for (index, name) in LegadoJSBindings.names.enumerated() {
                        context.setObject(saved[index], forKeyedSubscript: name as NSCopying & NSObjectProtocol)
                    }
                }
            }
            apply(bindings)
            let resultBefore = context.objectForKeyedSubscript("result")
            let outerError = capturedError
            capturedError = nil
            capturedErrorLine = 0
            defer { capturedError = outerError }

            var value: JSValue? = globalEval(code)
            if let error = capturedError, error.contains("Return statements") {
                capturedError = nil
                value = context.evaluateScript(Self.returnWrapperHead + code + Self.returnWrapperTail)
            } else if let error = capturedError, error.hasPrefix("SyntaxError"), capturedErrorLine <= 0,
                      let located = syntaxErrorWithLine(code) {
                // Eval gián tiếp báo lỗi cú pháp không kèm dòng: lấy dòng bằng cách phân tích lại (không chạy).
                capturedError = located
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
    }

    /// Tên thuộc tính ẩn trên global giữ `eval` gốc (gắn trong `init`, trước bootstrap).
    private static let globalEvalName = "__lgEval"

    /// Eval **gián tiếp**: gọi `eval` gốc như một hàm (không phải cú pháp `eval(…)` trong JS) ⇒ chạy ở phạm vi global
    /// với môi trường lexical riêng cho mỗi lần. Lỗi đi qua `exceptionHandler` như `evaluateScript`. Thiếu `eval` gốc
    /// (không xảy ra) ⇒ chạy thẳng `evaluateScript`.
    private func globalEval(_ code: String) -> JSValue? {
        guard let evaluator = context.objectForKeyedSubscript(Self.globalEvalName), evaluator.isObject else {
            return context.evaluateScript(code)
        }
        return evaluator.call(withArguments: [code])
    }

    /// Dạng dự phòng khi rule có `return` ở cấp ngoài cùng: `(function(result, baseUrl, …){{<code>\n}}).call(this, …)`.
    /// Biến môi trường (`LegadoJSBindings.names`) thành tham số nên `var src = src.trim()` đọc được giá trị cũ; khối
    /// bên trong cho phép `let`/`const` trùng tên tham số. Đối số đọc bằng `typeof` nên tên chưa có trên global không
    /// ném `ReferenceError`. Đường này trả giá trị bằng `return`; gán `result` chỉ đổi tham số nên không được phát
    /// hiện.
    private static let returnWrapperHead: String =
        "(function(" + LegadoJSBindings.names.joined(separator: ", ") + "){{"
    private static let returnWrapperTail: String = "\n}}).call(this, "
        + LegadoJSBindings.names.map { "typeof \($0) === 'undefined' ? undefined : \($0)" }.joined(separator: ", ")
        + ")"

    /// Option `js` của URL (§3.6): `java.url` = URL hiện tại, `java.headerMap` = header hiện tại; JS sửa chúng.
    /// Giá trị trả là chuỗi không rỗng ⇒ dùng làm URL (U11), ngược lại dùng `java.url`.
    func evaluateOptionScript(_ code: String, url: String, headers: [(name: String, value: String)],
                              bindings: LegadoJSBindings) throws -> (url: String, headers: [(name: String, value: String)]) {
        try autoreleasepool { () throws -> (url: String, headers: [(name: String, value: String)]) in
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
        autoreleasepool {
            let outer = capturedError
            capturedError = nil
            context.evaluateScript(code)
            if let error = capturedError {
                session?.diagnostics.record(.javaScript, "\(name): \(error)")
            }
            capturedError = outer
        }
    }

    /// Chạy mã nội bộ, bỏ qua lỗi; trả chuỗi kết quả (nếu có).
    @discardableResult
    func runQuietly(_ code: String) -> String? {
        autoreleasepool { () -> String? in
            let outer = capturedError
            capturedError = nil
            let value = context.evaluateScript(code)
            let failed = capturedError != nil
            capturedError = outer
            guard !failed, let value, !value.isUndefined, !value.isNull else { return nil }
            return value.toString()
        }
    }

    // MARK: - Biến môi trường

    /// Gán 7 biến môi trường. `src` (trước, để điền ô đệm) và `result` là chuỗi trang thì dùng lại chuỗi JS đã chép
    /// (`pageValue`, `cachedPageValue`) thay vì chép lại mấy MB mỗi lần chạy rule của từng mục.
    private func apply(_ bindings: LegadoJSBindings) {
        let srcValue = pageValue(bindings.src)
        if let response = bindings.responseResult {
            setGlobal("result", callHelper("__lgMakeResponse", response.compactText))
        } else if let map = bindings.mapResult {
            let object = LegadoEngineJSON.object(map.sorted { $0.key < $1.key }
                .map { (key: $0.key, value: LegadoEngineJSON.string($0.value)) })
            setGlobal("result", callHelper("__lgMakeMap", object.compactText))
        } else if let bytes = bindings.bytesResult {
            setGlobal("result", callHelper("__lgMakeBytes", Self.hex(bytes)))
        } else if case .string(let text)? = bindings.result, let cached = cachedPageValue(for: text) {
            setGlobal("result", cached)
        } else {
            setGlobal("result", bindings.result.map { importValue($0) } ?? undefinedValue)
        }
        setGlobal("baseUrl", jsString(bindings.baseUrl))
        setGlobal("src", srcValue)
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
        autoreleasepool { () -> JSValue in
            guard let function = context.objectForKeyedSubscript(name), !function.isUndefined,
                  let value = function.call(withArguments: [argument]) else { return undefinedValue }
            return value
        }
    }

    var undefinedValue: JSValue {
        JSValue(undefinedIn: context)
    }

    private func jsString(_ text: String?) -> JSValue {
        guard let text, let value = JSValue(object: text, in: context) else { return undefinedValue }
        return value
    }

    // MARK: - Chuỗi trang

    /// Tên thuộc tính ẩn trên global giữ chuỗi JS của trang lớn gần nhất (gắn trong `init`, không liệt kê, không xoá).
    private static let pageCacheName = "__lgSrcCache"
    /// Chuỗi từ chừng này byte UTF-8 trở lên mới vào ô đệm; chuỗi nhỏ chép thẳng.
    private static let pageCacheMinimumBytes = 16 * 1024

    /// Giá trị JS của `src`. Trùng chuỗi trang đang đệm ⇒ dùng lại chuỗi JS sẵn có (không chép); khác ⇒ chép một lần,
    /// và nếu đủ lớn thì thay ô đệm. Analyzer truyền **cùng một** `String` cho mọi mục của trang nên phép `==` đi đường
    /// tắt (cùng vùng nhớ).
    private func pageValue(_ text: String?) -> JSValue {
        guard let text else { return undefinedValue }
        if let cached = cachedPageValue(for: text) { return cached }
        let value = jsString(text)
        if text.utf8.count >= Self.pageCacheMinimumBytes, value.isString {
            context.setObject(value, forKeyedSubscript: Self.pageCacheName as NSCopying & NSObjectProtocol)
            cachedPageText = text
        }
        return value
    }

    /// Chuỗi JS đang đệm nếu `text` trùng chuỗi trang đã đệm; chỉ đọc, không điền ô đệm (dùng cho `result`, để một
    /// `result` lớn khác trang không đẩy trang ra rồi bắt chép lại ở lần sau).
    private func cachedPageValue(for text: String) -> JSValue? {
        guard let cachedPageText, text == cachedPageText,
              let cached = context.objectForKeyedSubscript(Self.pageCacheName), cached.isString else { return nil }
        return cached
    }

    // MARK: - Lỗi

    private static func describe(_ exception: JSValue?) -> String {
        guard let exception else { return "Lỗi JS không rõ" }
        let message = exception.toString() ?? "Lỗi JS không rõ"
        let line = lineNumber(of: exception)
        return line > 0 ? "\(message) (dòng \(line))" : message
    }

    /// Dòng của một ngoại lệ JS; không có hoặc không phải số ⇒ 0.
    private static func lineNumber(of exception: JSValue) -> Int32 {
        guard let line = exception.objectForKeyedSubscript("line"), line.isNumber else { return 0 }
        return line.toInt32()
    }

    /// Lỗi cú pháp của `code` kèm số dòng, theo định dạng `describe`. Eval gián tiếp của JSC báo `SyntaxError` không có
    /// dòng dùng được, nên phân tích lại mã gốc bằng `JSCheckScriptSyntax` — **chỉ phân tích, không chạy** (không dùng
    /// `evaluateScript`). Không có lỗi hoặc vẫn không có dòng > 0 ⇒ `nil`.
    private func syntaxErrorWithLine(_ code: String) -> String? {
        guard let script = JSStringCreateWithCFString(code as CFString) else { return nil }
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        guard !JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception), let exception,
              let error = JSValue(jsValueRef: exception, in: context), Self.lineNumber(of: error) > 0 else { return nil }
        return Self.describe(error)
    }

    func raise(_ message: String) {
        context.exception = JSValue(newErrorFromMessage: message, in: context)
    }
}
