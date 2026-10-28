import Foundation
import JavaScriptCore

/// Tầng tĩnh của Kiểm tra tiện ích: với **mọi** khoá trong mục `script` của `plugin.json`, kiểm (không mạng, không chạy
/// script) rằng giá trị là tên file, file có ở gốc tiện ích hoặc `src/` (cùng thứ tự `ExtensionManager.getScriptPath`),
/// đọc được UTF-8, đúng cú pháp, có hàm `execute`, và mọi `load("x")` chữ cố định trỏ tới file có thật.
///
/// Cú pháp kiểm bằng `JSCheckScriptSyntax` — chỉ phân tích, **không** thực thi (khác `JSExecutor.validateSyntax` vốn
/// `evaluateScript` cả file, chạy luôn code top-level). Engine chạy script thật cũng `evaluateScript` nguyên văn
/// (`JSExecutor.prepareScript`, không biến đổi trước) nên cùng một bộ phân tích cú pháp.
enum ExtensionScriptStaticCheck {
    struct Entry: Sendable {
        let key: String
        /// Tên file như khai; rỗng khi giá trị không phải chuỗi.
        let fileName: String
        /// `nil` ⇒ tĩnh đạt.
        let issue: String?
    }

    struct Scan: Sendable {
        let entries: [Entry]
        let manifestIssue: String?
    }

    /// Thứ tự hiển thị các khoá của hợp đồng extension; khoá lạ xếp sau theo tên.
    static let knownKeyOrder = [
        "home", "explore", "genre", "search", "detail", "page", "toc", "chap", "track",
        "voice", "tts", "config", "action", "language", "model", "style", "translate", "chatStream"
    ]

    private static let loadCallRegex = try? NSRegularExpression(pattern: #"load\(\s*['"]([^'"]{1,200})['"]\s*\)"#)

    /// Bốn cách khai `execute` hay gặp: `function execute(`, `async function execute(`, `execute = function` /
    /// `execute: function`, `execute = (` / `execute = async (`.
    private static let executeRegex = try? NSRegularExpression(
        pattern: #"(?:\bfunction\s+execute\s*\()|(?:\bexecute\s*[:=]\s*(?:async\s+)?(?:function\b|\())"#
    )

    static func scan(localPath: String) -> Scan {
        let pluginURL = URL(fileURLWithPath: localPath).appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: pluginURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Scan(entries: [], manifestIssue: "Không đọc được plugin.json")
        }
        guard let map = json["script"] as? [String: Any], !map.isEmpty else {
            return Scan(entries: [], manifestIssue: "plugin.json không có mục \"script\"")
        }
        let context: JSContext? = JSContext()
        let entries = map.keys.sorted(by: orderedBefore).map { key -> Entry in
            guard let raw = map[key] as? String else {
                return Entry(key: key, fileName: "", issue: "Giá trị của khoá không phải tên file")
            }
            let fileName = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty else {
                return Entry(key: key, fileName: "", issue: "Tên file rỗng")
            }
            return Entry(key: key, fileName: fileName, issue: fileIssue(fileName, localPath: localPath, context: context))
        }
        return Scan(entries: entries, manifestIssue: nil)
    }

    /// Lỗi tĩnh của một file script tìm theo tên (gốc rồi `src/`); `nil` ⇒ đạt. Dùng cả cho script phụ của tab/thể loại.
    static func fileIssue(_ fileName: String, localPath: String, context: JSContext? = nil) -> String? {
        guard let url = resolve(fileName, localPath: localPath) else {
            return "Không có file \(fileName) ở gốc tiện ích hay src/"
        }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            return "Không đọc được \(fileName) dạng UTF-8"
        }
        let checker: JSContext? = context ?? JSContext()
        if let checker, let error = syntaxError(source, context: checker) {
            return "Lỗi cú pháp: \(error)"
        }
        guard matches(executeRegex, in: source) else {
            return "Không có hàm execute"
        }
        if let missing = loadTargets(in: source).first(where: { resolve($0, localPath: localPath) == nil }) {
            return "load(\"\(missing)\") trỏ tới file không có"
        }
        return nil
    }

    /// File theo tên ở gốc tiện ích rồi `src/`; không có ⇒ `nil`.
    static func resolve(_ fileName: String, localPath: String) -> URL? {
        let root = URL(fileURLWithPath: localPath)
        for candidate in [root.appendingPathComponent(fileName), root.appendingPathComponent("src").appendingPathComponent(fileName)]
        where FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    // MARK: - Riêng

    private static func syntaxError(_ source: String, context: JSContext) -> String? {
        let script = JSStringCreateWithCFString(source as CFString)
        defer { JSStringRelease(script) }
        var exception: JSValueRef?
        guard !JSCheckScriptSyntax(context.jsGlobalContextRef, script, nil, 1, &exception) else { return nil }
        guard let exception, let text = JSValue(jsValueRef: exception, in: context)?.toString() else {
            return "không rõ"
        }
        return LegadoCorpusErrorClassifier.redact(text)
    }

    private static func matches(_ regex: NSRegularExpression?, in source: String) -> Bool {
        guard let regex else { return true }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.firstMatch(in: source, range: range) != nil
    }

    private static func loadTargets(in source: String) -> [String] {
        guard let regex = loadCallRegex else { return [] }
        let text = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: text.length))
            .filter { $0.numberOfRanges == 2 }
            .map { text.substring(with: $0.range(at: 1)) }
    }

    private static func orderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let left = knownKeyOrder.firstIndex(of: lhs) ?? Int.max
        let right = knownKeyOrder.firstIndex(of: rhs) ?? Int.max
        return left == right ? lhs < rhs : left < right
    }
}
