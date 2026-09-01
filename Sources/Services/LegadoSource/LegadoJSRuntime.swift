import Foundation
import JavaScriptCore

/// Runtime JavaScript cho rule `@js:` / `<js>` của nguồn Legado.
///
/// **Không** dùng lại `JSExecutor`: surface toàn cục của nó là của extension VBook (`Html`, `fetch`,
/// `Response`), khác hoàn toàn surface Legado (`java`, `source`, `book`, `result`). Mỗi tác vụ tạo một
/// runtime rồi giải phóng — cùng kỷ luật "không executor dùng chung" của `rules.md`; riêng vòng lặp
/// `nextContentUrl` trong **một** chương dùng lại một runtime vì tạo lại quá đắt.
public final class LegadoJSRuntime {

    private let context: JSContext
    private let variables: LegadoVariableBag
    private var scope: LegadoJSScope
    /// Cú pháp ngoài phạm vi mà script đã chạm tới, để báo lên báo cáo tương thích.
    public private(set) var unsupportedFeatures: Set<LegadoUnsupportedFeature> = []
    public private(set) var lastError: String?

    public init(scope: LegadoJSScope, variables: LegadoVariableBag) {
        self.context = JSContext()
        self.scope = scope
        self.variables = variables
        installGlobals()
    }

    public func updateScope(_ transform: (inout LegadoJSScope) -> Void) {
        transform(&scope)
        installScopeObjects()
    }

    // MARK: - Chạy script

    /// Chạy script với biến `result` là `input`. Trả `nil` khi script lỗi.
    public func evaluate(_ code: String, result input: Any?) -> JSValue? {
        context.exception = nil
        lastError = nil

        if let input {
            context.setObject(input, forKeyedSubscript: "result" as NSCopying & NSObjectProtocol)
        } else {
            context.evaluateScript("var result = null;")
        }
        context.setObject(scope.baseUrl, forKeyedSubscript: "baseUrl" as NSCopying & NSObjectProtocol)

        // Bọc trong hàm để `return` ở cấp ngoài cùng của script nguồn không phải lỗi cú pháp, và để
        // giá trị biểu thức cuối vẫn là giá trị trả về (giống Rhino).
        let value = context.evaluateScript(code)

        if let exception = context.exception {
            lastError = exception.toString()
            context.exception = nil
            AppLogger.shared.log("❌ [LegadoJS] \(lastError ?? "lỗi không rõ") — script: \(code.prefix(160))")
            return nil
        }
        return value
    }

    public func evaluateToString(_ code: String, result input: Any?) -> String? {
        guard let value = evaluate(code, result: input) else { return nil }
        if value.isUndefined || value.isNull { return nil }
        if value.isArray, let array = value.toArray() {
            let parts = array.compactMap { item -> String? in
                if let text = item as? String { return text }
                return LegadoJSON.string(item)
            }
            return parts.joined(separator: "\n")
        }
        if value.isObject, let dictionary = value.toDictionary() {
            return LegadoJSON.encode(dictionary)
        }
        return value.toString()
    }

    public func evaluateToStringList(_ code: String, result input: Any?) -> [String] {
        guard let value = evaluate(code, result: input) else { return [] }
        if value.isArray, let array = value.toArray() {
            return array.compactMap { item -> String? in
                if let text = item as? String { return text }
                return LegadoJSON.string(item)
            }
        }
        guard let text = value.toString(), !text.isEmpty, text != "undefined", text != "null" else {
            return []
        }
        return [text]
    }

    // MARK: - Cài globals

    private func installGlobals() {
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastError = exception?.toString()
        }
        LegadoJSBridge.install(on: context, runtime: self)
        installScopeObjects()
    }

    private func installScopeObjects() {
        let sourceObject = JSValue(newObjectIn: context)
        sourceObject?.setValue(scope.sourceUrl, forProperty: "bookSourceUrl")
        sourceObject?.setValue(scope.sourceName, forProperty: "bookSourceName")
        sourceObject?.setValue(scope.sourceComment ?? "", forProperty: "bookSourceComment")
        sourceObject?.setValue(scope.sourceHeader ?? "", forProperty: "header")
        sourceObject?.setValue(scope.sourceUrl, forProperty: "key")

        let getKey: @convention(block) () -> String = { [weak self] in
            self?.scope.sourceUrl ?? ""
        }
        sourceObject?.setObject(getKey, forKeyedSubscript: "getKey" as NSCopying & NSObjectProtocol)

        let getVariable: @convention(block) (String?) -> String = { [weak self] key in
            guard let self, let key else { return "" }
            return self.variables.get(key)
        }
        sourceObject?.setObject(getVariable, forKeyedSubscript: "getVariable" as NSCopying & NSObjectProtocol)
        sourceObject?.setObject(getVariable, forKeyedSubscript: "get" as NSCopying & NSObjectProtocol)

        let setVariable: @convention(block) (String?, String?) -> Bool = { [weak self] key, value in
            guard let self, let key, let value else { return false }
            self.variables.put(key, value)
            return true
        }
        sourceObject?.setObject(setVariable, forKeyedSubscript: "setVariable" as NSCopying & NSObjectProtocol)
        sourceObject?.setObject(setVariable, forKeyedSubscript: "put" as NSCopying & NSObjectProtocol)
        sourceObject?.setObject(setVariable, forKeyedSubscript: "putVariable" as NSCopying & NSObjectProtocol)

        // Đăng nhập ngoài phạm vi: trả rỗng thay vì undefined để script không nổ ở `JSON.parse`.
        let emptyString: @convention(block) () -> String = { [weak self] in
            self?.noteUnsupported(.login)
            return ""
        }
        for name in ["getLoginHeader", "getLoginInfo", "getLoginHeaderMap", "getLoginInfoMap"] {
            sourceObject?.setObject(emptyString, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
        }
        let ignoreOne: @convention(block) (String?) -> Bool = { [weak self] _ in
            self?.noteUnsupported(.login)
            return false
        }
        for name in ["putLoginHeader", "putLoginInfo"] {
            sourceObject?.setObject(ignoreOne, forKeyedSubscript: name as NSCopying & NSObjectProtocol)
        }
        context.setObject(sourceObject, forKeyedSubscript: "source" as NSCopying & NSObjectProtocol)

        installBookObject()
        installChapterObject()

        if let key = scope.searchKey {
            context.setObject(key, forKeyedSubscript: "key" as NSCopying & NSObjectProtocol)
        }
        if let page = scope.page {
            context.setObject(NSNumber(value: page), forKeyedSubscript: "page" as NSCopying & NSObjectProtocol)
        }
        if let title = scope.chapterTitle {
            context.setObject(title, forKeyedSubscript: "title" as NSCopying & NSObjectProtocol)
        }
        context.setObject(scope.baseUrl, forKeyedSubscript: "baseUrl" as NSCopying & NSObjectProtocol)
        context.setObject("", forKeyedSubscript: "cookie" as NSCopying & NSObjectProtocol)
        context.setObject("", forKeyedSubscript: "src" as NSCopying & NSObjectProtocol)
    }

    private func installBookObject() {
        let book = JSValue(newObjectIn: context)
        book?.setValue(scope.bookName ?? "", forProperty: "name")
        book?.setValue(scope.bookAuthor ?? "", forProperty: "author")
        book?.setValue(scope.bookUrl ?? "", forProperty: "bookUrl")
        book?.setValue(scope.bookTocUrl ?? "", forProperty: "tocUrl")
        book?.setValue(scope.bookKind ?? "", forProperty: "kind")
        book?.setValue(scope.bookIntro ?? "", forProperty: "intro")
        book?.setValue(scope.bookCoverUrl ?? "", forProperty: "coverUrl")

        let name: @convention(block) () -> String = { [weak self] in self?.scope.bookName ?? "" }
        book?.setObject(name, forKeyedSubscript: "getName" as NSCopying & NSObjectProtocol)
        let author: @convention(block) () -> String = { [weak self] in self?.scope.bookAuthor ?? "" }
        book?.setObject(author, forKeyedSubscript: "getAuthor" as NSCopying & NSObjectProtocol)
        let bookUrl: @convention(block) () -> String = { [weak self] in self?.scope.bookUrl ?? "" }
        book?.setObject(bookUrl, forKeyedSubscript: "getBookUrl" as NSCopying & NSObjectProtocol)
        let tocUrl: @convention(block) () -> String = { [weak self] in self?.scope.bookTocUrl ?? "" }
        book?.setObject(tocUrl, forKeyedSubscript: "getTocUrl" as NSCopying & NSObjectProtocol)
        let cover: @convention(block) () -> String = { [weak self] in self?.scope.bookCoverUrl ?? "" }
        book?.setObject(cover, forKeyedSubscript: "getCoverUrl" as NSCopying & NSObjectProtocol)

        let getVariable: @convention(block) (String?) -> String = { [weak self] key in
            guard let self, let key else { return "" }
            return self.variables.get(key)
        }
        book?.setObject(getVariable, forKeyedSubscript: "getVariable" as NSCopying & NSObjectProtocol)
        let putVariable: @convention(block) (String?, String?) -> Bool = { [weak self] key, value in
            guard let self, let key, let value else { return false }
            self.variables.put(key, value)
            return true
        }
        book?.setObject(putVariable, forKeyedSubscript: "putVariable" as NSCopying & NSObjectProtocol)
        let variableMap: @convention(block) () -> [String: String] = { [weak self] in
            self?.variables.bookSnapshot ?? [:]
        }
        book?.setObject(variableMap, forKeyedSubscript: "getVariableMap" as NSCopying & NSObjectProtocol)

        context.setObject(book, forKeyedSubscript: "book" as NSCopying & NSObjectProtocol)
    }

    private func installChapterObject() {
        let chapter = JSValue(newObjectIn: context)
        chapter?.setValue(scope.chapterTitle ?? "", forProperty: "title")
        chapter?.setValue(scope.chapterUrl ?? "", forProperty: "url")
        chapter?.setValue(NSNumber(value: scope.chapterIndex ?? 0), forProperty: "index")

        let title: @convention(block) () -> String = { [weak self] in self?.scope.chapterTitle ?? "" }
        chapter?.setObject(title, forKeyedSubscript: "getTitle" as NSCopying & NSObjectProtocol)
        let url: @convention(block) () -> String = { [weak self] in self?.scope.chapterUrl ?? "" }
        chapter?.setObject(url, forKeyedSubscript: "getUrl" as NSCopying & NSObjectProtocol)
        let index: @convention(block) () -> NSNumber = { [weak self] in
            NSNumber(value: self?.scope.chapterIndex ?? 0)
        }
        chapter?.setObject(index, forKeyedSubscript: "getIndex" as NSCopying & NSObjectProtocol)

        let getVariable: @convention(block) (String?) -> String = { [weak self] key in
            guard let self, let key else { return "" }
            return self.variables.get(key)
        }
        chapter?.setObject(getVariable, forKeyedSubscript: "getVariable" as NSCopying & NSObjectProtocol)
        let putVariable: @convention(block) (String?, String?) -> Bool = { [weak self] key, value in
            guard let self, let key, let value else { return false }
            self.variables.putChapterScoped(key, value)
            return true
        }
        chapter?.setObject(putVariable, forKeyedSubscript: "putVariable" as NSCopying & NSObjectProtocol)

        context.setObject(chapter, forKeyedSubscript: "chapter" as NSCopying & NSObjectProtocol)
    }

    // MARK: - Cho bridge dùng

    internal var jsContext: JSContext { context }
    internal var variableBag: LegadoVariableBag { variables }
    internal var currentScope: LegadoJSScope { scope }

    internal func noteUnsupported(_ feature: LegadoUnsupportedFeature) {
        unsupportedFeatures.insert(feature)
    }
}
