import Foundation

/// Khoá `config` nào được **script của một tab** dùng tới — để sheet "Bộ lọc" chỉ hiện đúng các mục của tab đang xem.
///
/// Quét chữ, không chạy script:
/// - Đọc file script của tab cùng mọi file nó `load('x.js')` (chữ cố định, đệ quy, chống lặp, tối đa `maxFiles` file).
///   File tìm ở gốc tiện ích rồi `src/` (cùng thứ tự `JSExecutor+Load`). Thư viện dựng sẵn không có file trong tiện ích
///   (vd `crypto.js`) thì bỏ qua — chúng không đọc config.
/// - Bỏ comment `//` và `/* */` (chuỗi giữ nguyên), rồi tìm **nguyên tên** khoá: trước và sau tên không được là chữ, số,
///   `_` hay `$` ⇒ `FILTER_SORT` không khớp nhầm `FILTER_SORT_NAME` hay `MY_FILTER_SORT`.
/// - Không theo luồng dữ liệu: file dùng chung đọc `EXPLORE_RANK` vào một biến khác thì mọi tab load file đó đều tính là dùng.
enum ExtensionScriptConfigScanner {
    static let maxFiles = 30

    /// Các khoá trong `candidates` được nhắc tới trong code của `entryScript` (tên file) và các file nó `load`.
    /// Không đọc được file của tab ⇒ rỗng. Đọc file ⇒ gọi ngoài main.
    static func referencedKeys(localPath: String, entryScript: String, candidates: [String]) -> Set<String> {
        guard !localPath.isEmpty, !candidates.isEmpty else { return [] }
        let code = collectCode(localPath: localPath, entryScript: entryScript)
        guard !code.isEmpty else { return [] }
        return Set(candidates.filter { containsIdentifier($0, in: code) })
    }

    // MARK: - Gom code

    /// `load('x.js')` / `load("x.js")` ở bất kỳ đâu trong code (không tính `obj.load(...)`).
    private static let loadRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_$.])load\(\s*(['"])([^'"\r\n]+)\1\s*\)"#
    )

    private static func collectCode(localPath: String, entryScript: String) -> String {
        var queue = [entryScript]
        var visited = Set<String>()
        var parts: [String] = []
        while !queue.isEmpty, visited.count < maxFiles {
            let name = queue.removeFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, visited.insert(name).inserted, let data = scriptData(named: name, localPath: localPath) else {
                continue
            }
            let code = stripComments(TextEncodingDecoder.decode(data))
            parts.append(code)
            queue.append(contentsOf: loadedFileNames(in: code))
        }
        return parts.joined(separator: "\n")
    }

    private static func loadedFileNames(in code: String) -> [String] {
        guard let regex = loadRegex else { return [] }
        let text = code as NSString
        return regex.matches(in: code, range: NSRange(location: 0, length: text.length)).map {
            text.substring(with: $0.range(at: 2))
        }
    }

    /// File theo tên ở gốc gói rồi `src/` (`ExtensionPackageReader`). Tên có `..` (ra ngoài gói) ⇒ bỏ qua.
    private static func scriptData(named name: String, localPath: String) -> Data? {
        guard !name.contains("..") else { return nil }
        return ExtensionPackageReader.scriptData(named: name, localPath: localPath)
    }

    // MARK: - Bỏ comment

    private enum LexState {
        case code, singleQuote, doubleQuote, template, lineComment, blockComment
    }

    /// Bỏ `// …` và `/* … */` ngoài chuỗi; chuỗi `'…'`, `"…"`, `` `…` `` giữ nguyên. Ngoài chuỗi, `\` bỏ qua ký tự kế
    /// (`/https?:\/\//` không bị coi là comment). Chuỗi `'`/`"` kết thúc ở cuối dòng — regex có dấu nháy (`/'/g`) đọc
    /// nhầm thành chuỗi cũng chỉ ảnh hưởng tới hết dòng.
    static func stripComments(_ source: String) -> String {
        let scalars = Array(source.unicodeScalars)
        var output = String.UnicodeScalarView()
        output.reserveCapacity(scalars.count)
        var state = LexState.code
        var index = 0
        while index < scalars.count {
            let char = scalars[index]
            let next: Unicode.Scalar? = index + 1 < scalars.count ? scalars[index + 1] : nil
            switch state {
            case .code:
                if char == "/", next == "/" {
                    state = .lineComment
                    index += 2
                    continue
                }
                if char == "/", next == "*" {
                    state = .blockComment
                    index += 2
                    continue
                }
                if char == "\\", let next {
                    output.append(char)
                    output.append(next)
                    index += 2
                    continue
                }
                if char == "'" { state = .singleQuote } else if char == "\"" { state = .doubleQuote } else if char == "`" { state = .template }
                output.append(char)
            case .singleQuote, .doubleQuote, .template:
                if char == "\\", let next {
                    output.append(char)
                    output.append(next)
                    index += 2
                    continue
                }
                output.append(char)
                let closes = (state == .singleQuote && char == "'") || (state == .doubleQuote && char == "\"")
                    || (state == .template && char == "`")
                let lineEnds = state != .template && (char == "\n" || char == "\r")
                if closes || lineEnds { state = .code }
            case .lineComment:
                if char == "\n" || char == "\r" {
                    output.append(char)
                    state = .code
                }
            case .blockComment:
                if char == "*", next == "/" {
                    output.append(" ")
                    state = .code
                    index += 2
                    continue
                }
                if char == "\n" { output.append(char) }
            }
            index += 1
        }
        return String(output)
    }

    // MARK: - Khớp tên

    private static func containsIdentifier(_ key: String, in code: String) -> Bool {
        let pattern = "(?<![A-Za-z0-9_$])" + NSRegularExpression.escapedPattern(for: key) + "(?![A-Za-z0-9_$])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: code, range: NSRange(location: 0, length: (code as NSString).length)) != nil
    }
}
