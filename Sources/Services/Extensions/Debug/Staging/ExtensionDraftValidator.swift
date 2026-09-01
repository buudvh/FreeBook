import Foundation

/// Validate một snapshot nháp **trước** khi cho phép chạy (Phase 3).
///
/// Checksum đã được `ExtensionDraftStagingStore` xác minh; ở đây kiểm những thứ về *ngữ nghĩa VBook*:
/// `plugin.json` đọc được, mọi script khai trong nó có mặt trong snapshot, mọi `load("…")` trỏ tới file
/// có thật, và từng script biên dịch được.
///
/// Kiểm cú pháp dùng `JSExecutor.validateSyntax` trên một executor **dùng một lần rồi thả** — cùng luật
/// "không shared executor" của phần còn lại; và cố ý *không* gọi `execute(...)`, nên validate không có
/// side effect mạng.
public enum ExtensionDraftValidator {
    /// Chỉ nhận `load("x")` / `load('x')`; biểu thức động thì không kiểm được và được bỏ qua có chủ ý.
    private static let loadCallRegex = try! NSRegularExpression(
        pattern: #"load\(\s*['"]([^'"]{1,200})['"]\s*\)"#,
        options: []
    )

    public static func validate(directory: URL, manifest: ExtensionDraftManifest) -> [String] {
        var issues: [String] = []
        let declaredPaths = Set(manifest.entries.map { $0.relativePath })

        let pluginUrl = directory.appendingPathComponent("plugin.json")
        guard let pluginData = try? Data(contentsOf: pluginUrl),
              let pluginJson = (try? JSONSerialization.jsonObject(with: pluginData)) as? [String: Any] else {
            return ["plugin.json không đọc được hoặc không phải JSON object"]
        }

        guard let scriptMap = pluginJson["script"] as? [String: Any], !scriptMap.isEmpty else {
            return ["plugin.json không có mục \"script\""]
        }

        for (key, value) in scriptMap {
            guard let fileName = value as? String, !fileName.isEmpty else {
                issues.append("script.\(key) không phải tên file")
                continue
            }
            guard let resolved = resolvedScriptPath(fileName, declaredPaths: declaredPaths) else {
                issues.append("script.\(key) trỏ tới '\(fileName)' không có trong snapshot (đã thử gốc và src/)")
                continue
            }
            issues.append(contentsOf: syntaxIssues(relativePath: resolved, directory: directory))
            issues.append(contentsOf: loadIssues(relativePath: resolved, directory: directory, declaredPaths: declaredPaths))
        }

        return issues
    }

    /// Cùng thứ tự resolve với production: gốc extension trước, rồi `src/`.
    private static func resolvedScriptPath(_ fileName: String, declaredPaths: Set<String>) -> String? {
        if declaredPaths.contains(fileName) { return fileName }
        let srcPath = "src/" + fileName
        if declaredPaths.contains(srcPath) { return srcPath }
        return nil
    }

    private static func syntaxIssues(relativePath: String, directory: URL) -> [String] {
        let fileUrl = directory.appendingPathComponent(relativePath)
        guard let source = try? String(contentsOf: fileUrl, encoding: .utf8) else {
            return ["\(relativePath): không đọc được nội dung dạng UTF-8"]
        }
        let executor = JSExecutor(localPath: directory.path)
        let result = executor.validateSyntax(source)
        guard result.isValid else {
            return ["\(relativePath): lỗi cú pháp — \(result.errorMessage ?? "không rõ")"]
        }
        return []
    }

    private static func loadIssues(relativePath: String, directory: URL, declaredPaths: Set<String>) -> [String] {
        let fileUrl = directory.appendingPathComponent(relativePath)
        guard let source = try? String(contentsOf: fileUrl, encoding: .utf8) else { return [] }
        let ns = source as NSString
        let matches = loadCallRegex.matches(in: source, options: [], range: NSRange(location: 0, length: ns.length))
        var issues: [String] = []
        for match in matches where match.numberOfRanges == 2 {
            let dependency = ns.substring(with: match.range(at: 1))
            if resolvedScriptPath(dependency, declaredPaths: declaredPaths) == nil {
                issues.append("\(relativePath): load(\"\(dependency)\") không có trong snapshot")
            }
        }
        return issues
    }
}
