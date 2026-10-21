import Foundation

/// Đọc và gộp header của nguồn Legado (spec §3.10).
///
/// Header luôn là danh sách cặp có thứ tự; gộp **không phân biệt hoa thường** (HTTP vốn vậy), bản sau thắng.
enum LegadoHeaderParser {
    /// Object JSON (hoặc chuỗi chứa object JSON lenient) → cặp tên/giá trị. Giá trị không phải chuỗi được chuyển chuỗi.
    static func pairs(from value: LegadoEngineJSON) -> [(name: String, value: String)] {
        switch value {
        case .object(let entries):
            return entries.compactMap { entry -> (name: String, value: String)? in
                let name = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !entry.value.isNull else { return nil }
                return (name: name, value: entry.value.scalarString)
            }
        case .string(let text):
            return pairs(fromText: text)
        default:
            return []
        }
    }

    /// Văn bản header (§3.10 mục 2–3): object JSON lenient; dòng `Khoá: Giá trị`; chuỗi bắt đầu bằng `Mozilla/` ⇒ UA.
    static func pairs(fromText text: String) -> [(name: String, value: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("{"), let json = LegadoEngineJSONParser.parse(trimmed, lenient: true), json.objectEntries != nil {
            return pairs(from: json)
        }
        if trimmed.hasPrefix("Mozilla/") {
            return [(name: "User-Agent", value: trimmed)]
        }
        var output: [(name: String, value: String)] = []
        for line in trimmed.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.count < 60 else { continue }
            output.append((name: name, value: value))
        }
        return output
    }

    /// Ghi đè/ thêm `extra` vào `base` (so tên không phân biệt hoa thường; giữ vị trí cũ, đổi cách viết tên theo bản mới).
    static func merge(_ base: [(name: String, value: String)], _ extra: [(name: String, value: String)]) -> [(name: String, value: String)] {
        var output = base
        for pair in extra {
            if let position = output.firstIndex(where: { $0.name.caseInsensitiveCompare(pair.name) == .orderedSame }) {
                output[position] = pair
            } else {
                output.append(pair)
            }
        }
        return output
    }

    static func value(_ name: String, in headers: [(name: String, value: String)]) -> String? {
        headers.last(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    static func removing(_ name: String, from headers: [(name: String, value: String)]) -> [(name: String, value: String)] {
        headers.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
    }
}
