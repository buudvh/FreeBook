import Foundation

/// Bộ đệm `NSRegularExpression` theo pattern cho engine nguồn Legado (không tạo regex trong vòng lặp nóng).
/// `NSRegularExpression` bất biến và an toàn đa luồng nên dùng chung được giữa mọi phiên; bảng đệm có khoá.
///
/// Cú pháp nguồn viết là regex kiểu Java (spec §2.6). ICU gần như trùng; chỗ khác đã biết được sửa trước khi biên dịch:
/// `[^]…]` / `[]…]` (Java coi `]` đứng đầu lớp ký tự là chữ thường, ICU báo lỗi).
final class LegadoRegexCache {
    static let shared = LegadoRegexCache()

    private let lock = NSLock()
    private var compiled: [String: NSRegularExpression] = [:]
    private var failed: Set<String> = []
    private static let capacity = 1024

    /// `nil` khi pattern không biên dịch được (đã ghi nhớ để lần sau khỏi thử lại).
    func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(options.rawValue)|\(pattern)"
        lock.lock()
        if let cached = compiled[key] {
            lock.unlock()
            return cached
        }
        if failed.contains(key) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let made = try? NSRegularExpression(pattern: Self.javaCompatible(pattern), options: options)

        lock.lock()
        defer { lock.unlock() }
        if let made {
            if compiled.count >= Self.capacity { compiled.removeAll(keepingCapacity: true) }
            compiled[key] = made
        } else {
            if failed.count >= Self.capacity { failed.removeAll(keepingCapacity: true) }
            failed.insert(key)
        }
        return made
    }

    /// Thoát `]` đứng ngay sau `[` hoặc `[^` (lớp ký tự kiểu Java).
    static func javaCompatible(_ pattern: String) -> String {
        guard pattern.contains("[]") || pattern.contains("[^]") else { return pattern }
        var output = ""
        var escaped = false
        var inClass = false
        var classLength = 0
        for character in pattern {
            if escaped {
                output.append(character)
                escaped = false
                if inClass { classLength += 1 }
                continue
            }
            if character == "\\" {
                output.append(character)
                escaped = true
                continue
            }
            if inClass {
                if character == "]" {
                    if classLength == 0 {
                        output += "\\]"
                        classLength += 1
                        continue
                    }
                    inClass = false
                } else if character == "^" && classLength == 0 && output.hasSuffix("[") {
                    output.append(character)
                    continue
                } else {
                    classLength += 1
                }
                output.append(character)
                continue
            }
            if character == "[" {
                inClass = true
                classLength = 0
            }
            output.append(character)
        }
        return output
    }

    // MARK: - Áp regex

    /// Thay mọi đoạn khớp bằng `template` (cú pháp `$1` như Java). Regex lỗi ⇒ giữ nguyên chuỗi.
    static func replaceAll(_ regex: NSRegularExpression, in text: String, template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    /// Chế độ `###`: kết quả = `template` khai triển theo đoạn khớp **đầu tiên**; không khớp ⇒ giữ nguyên chuỗi (U3).
    static func firstMatch(_ regex: NSRegularExpression, in text: String, template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return text }
        return regex.replacementString(for: match, in: text, offset: 0, template: template)
    }

    /// Mọi đoạn khớp, mỗi đoạn là mảng nhóm `[0…n]` (nhóm không khớp ⇒ chuỗi rỗng).
    static func allGroups(_ regex: NSRegularExpression, in text: String) -> [[String]] {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).map { group in
                let groupRange = match.range(at: group)
                return groupRange.location == NSNotFound ? "" : nsText.substring(with: groupRange)
            }
        }
    }
}
