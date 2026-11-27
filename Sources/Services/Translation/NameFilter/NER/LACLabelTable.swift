import Foundation

/// Bảng nhãn `tag.dic` (`id<TAB>nhãn`) của LAC, **dòng sau ghi đè** như dict Python ⇒ 16 = `PER-B`, 18 = `LOC-B`,
/// 20 = `ORG-B`, 34 = `TIME-B`, 48 = `O`.
///
/// Tính sẵn hai thứ bước gộp nhãn (`parse_result` của LAC) cần cho mỗi id:
/// - `base` = `nhãn[:-2]` (bỏ hậu tố `-B` / `-I`; `O` ⇒ chuỗi rỗng, đúng như LAC);
/// - `opensWord` = nhãn kết thúc bằng `B` hoặc `S` ⇒ mở từ mới. Chữ thứ hai trở đi của một từ nhiều chữ mang nhãn
///   `base-I` ⇒ không bao giờ mở từ, nhãn sau gộp vẫn là `base`.
struct LACLabelTable: Sendable {
    let names: [String]
    let bases: [String]
    let opensWord: [Bool]

    var count: Int { names.count }

    init(tagDictionary data: Data, numLabels: Int) throws {
        let name = LACModelMirror.tagDictionaryName
        var table: [Int: [UInt32]] = [:]
        try LACDictionaryParser.forEachLine(data, file: name) { line in
            guard let pair = LACDictionaryParser.splitPair(line, separator: LACDictionaryParser.tab) else { return }
            guard let id = LACDictionaryParser.integer(pair.0) else {
                throw LACModelError.invalidFiles("\(name) có id sai")
            }
            table[id] = Array(pair.1)
        }
        var names: [String] = []
        var bases: [String] = []
        var opens: [Bool] = []
        for id in 0..<numLabels {
            guard let label = table[id] else { throw LACModelError.invalidFiles("\(name) thiếu nhãn \(id)") }
            names.append(LACDictionaryParser.string(label))
            bases.append(LACDictionaryParser.string(label.dropLast(2)))
            opens.append(label.last == 0x42 || label.last == 0x53) // "B" / "S"
        }
        self.names = names
        self.bases = bases
        opensWord = opens
    }
}
