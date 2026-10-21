import Foundation

/// Chỉ số ở cuối một bước chọn của chế độ mặc định (spec §2.8.3).
///
/// - Kiểu chấm/chấm than: `.N`, `.-N`, `.N:M:K` (danh sách theo thứ tự viết), `!N`, `!N:M` (loại trừ); `.!N` ≡ `!N`.
/// - Kiểu ngoặc vuông: `[N]`, `[a:b]` (**gồm cả hai đầu**, `a > b` thì đảo chiều), `[a:]`, `[:b]`, `[N,M]`,
///   `[!N,…]`, `[a:b:c]` (khoảng có bước — khuyến nghị U13).
///
/// Chỉ số âm tính từ cuối; chỉ số vượt phạm vi bị bỏ qua, không lỗi.
struct LegadoRuleIndex {
    enum Entry {
        case single(Int)
        case range(Int?, Int?, Int?)
    }

    var excludes: Bool
    var entries: [Entry]

    /// Tách chỉ số khỏi cuối bước. Trả `index == nil` khi bước không có chỉ số.
    static func parse(step: String) -> (body: String, index: LegadoRuleIndex?) {
        if let bracket = parseBracket(step) { return bracket }
        if let dotted = parseDotted(step) { return dotted }
        return (step, nil)
    }

    private static let dottedPattern = try? NSRegularExpression(pattern: "(\\.!|[.!])(-?\\d+(?::-?\\d+)*)$")

    private static func parseDotted(_ step: String) -> (body: String, index: LegadoRuleIndex?)? {
        guard let regex = dottedPattern else { return nil }
        let range = NSRange(step.startIndex..., in: step)
        guard let match = regex.firstMatch(in: step, range: range),
              let markerRange = Range(match.range(at: 1), in: step),
              let numbersRange = Range(match.range(at: 2), in: step),
              let wholeRange = Range(match.range, in: step) else { return nil }
        let marker = String(step[markerRange])
        let numbers = step[numbersRange].split(separator: ":").compactMap { Int($0) }
        guard !numbers.isEmpty else { return nil }
        let body = String(step[step.startIndex..<wholeRange.lowerBound])
        let index = LegadoRuleIndex(excludes: marker != ".", entries: numbers.map { Entry.single($0) })
        return (body, index)
    }

    private static let bracketCharacters = CharacterSet(charactersIn: "0123456789:,!- ")

    private static func parseBracket(_ step: String) -> (body: String, index: LegadoRuleIndex?)? {
        guard step.hasSuffix("]"), let open = step.lastIndex(of: "[") else { return nil }
        let innerStart = step.index(after: open)
        let innerEnd = step.index(before: step.endIndex)
        guard innerStart <= innerEnd else { return nil }
        let inner = String(step[innerStart..<innerEnd]).trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty,
              inner.unicodeScalars.allSatisfy({ bracketCharacters.contains($0) }),
              inner.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) || $0 == ":" }) else {
            return nil
        }
        var text = inner
        var excludes = false
        if text.hasPrefix("!") {
            excludes = true
            text.removeFirst()
        }
        var entries: [Entry] = []
        for part in text.split(separator: ",") {
            let piece = part.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "!", with: "")
            if piece.contains(":") {
                let bounds = piece.split(separator: ":", omittingEmptySubsequences: false).map {
                    Int($0.trimmingCharacters(in: .whitespaces))
                }
                entries.append(.range(bounds.first ?? nil, bounds.count > 1 ? bounds[1] : nil, bounds.count > 2 ? bounds[2] : nil))
            } else if let value = Int(piece) {
                entries.append(.single(value))
            }
        }
        guard !entries.isEmpty else { return nil }
        return (String(step[step.startIndex..<open]), LegadoRuleIndex(excludes: excludes, entries: entries))
    }

    // MARK: - Áp

    func apply<T>(_ items: [T]) -> [T] {
        let positions = resolvedPositions(count: items.count)
        if excludes {
            let excluded = Set(positions)
            return items.enumerated().filter { !excluded.contains($0.offset) }.map { $0.element }
        }
        return positions.map { items[$0] }
    }

    /// Các vị trí hợp lệ theo đúng thứ tự viết.
    func resolvedPositions(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var output: [Int] = []
        func resolve(_ value: Int) -> Int { value < 0 ? count + value : value }
        for entry in entries {
            switch entry {
            case .single(let value):
                let position = resolve(value)
                if position >= 0 && position < count { output.append(position) }
            case .range(let start, let end, let step):
                let rawFirst = resolve(start ?? 0)
                let rawLast = resolve(end ?? (count - 1))
                let stride = max(1, abs(step ?? 1))
                // Kẹp vào [0, count-1] trước khi lặp (giữ đúng nhịp bước): `[0:99999999]` không được lặp hàng trăm
                // triệu lần.
                if rawFirst <= rawLast {
                    var cursor = rawFirst
                    if cursor < 0 { cursor += ((-cursor + stride - 1) / stride) * stride }
                    let last = min(rawLast, count - 1)
                    while cursor <= last {
                        output.append(cursor)
                        cursor += stride
                    }
                } else {
                    var cursor = rawFirst
                    if cursor > count - 1 { cursor -= ((cursor - (count - 1) + stride - 1) / stride) * stride }
                    let last = max(rawLast, 0)
                    while cursor >= last {
                        output.append(cursor)
                        cursor -= stride
                    }
                }
            }
        }
        return output
    }
}
