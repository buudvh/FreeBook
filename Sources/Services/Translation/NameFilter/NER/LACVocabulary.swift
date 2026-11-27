import Foundation

/// Bước 2 của LAC: từ đã tách ⇒ id embedding — bản viết lại `Dataset.text_to_ids` / `word_to_ids` (LAC 2.1.2).
///
/// - `word.dic` (`id<TAB>từ`) đọc ngược thành từ → id, dòng sau ghi đè; chỉ bỏ `\n`, **giữ dấu cách** (id 0 là `" "`).
/// - `q2b.dic` (`gốc<TAB>thay`, toàn khoá một chữ ở bản ghim) đổi chữ toàn hình sang bán hình trước khi tra.
/// - Từ có trong `word.dic` (tra bằng chữ **gốc**) ⇒ một id (qua `q2b` rồi tra lại, không có ⇒ `OOV`), độ dài = số chữ;
///   không có ⇒ **từng chữ** qua `q2b` rồi tra, mỗi chữ một id, độ dài 1.
struct LACVocabulary: Sendable {
    private let wordTrie: LACScalarTrie
    private let oovID: Int32
    private let singleReplacements: [UInt32: [UInt32]]
    /// Khoá nhiều chữ của `q2b.dic` (bản ghim không có; giữ cho đúng `dict.get(từ)` của Python).
    private let multiReplacements: [[UInt32]: [UInt32]]

    init(wordDictionary: Data, replaceDictionary: Data, vocabSize: Int) throws {
        let wordName = LACModelMirror.wordDictionaryName
        var trie = LACScalarTrie(reservingCapacity: 120_000)
        try LACDictionaryParser.forEachLine(wordDictionary, file: wordName) { line in
            guard let pair = LACDictionaryParser.splitPair(line, separator: LACDictionaryParser.tab) else { return }
            guard let id = LACDictionaryParser.integer(pair.0), id < vocabSize else {
                throw LACModelError.invalidFiles("\(wordName) có id sai")
            }
            trie.insert(pair.1, payload: Int32(id))
        }
        guard let oov = trie.lookup(Array("OOV".unicodeScalars.map(\.value))) else {
            throw LACModelError.invalidFiles("\(wordName) thiếu OOV")
        }

        var singles: [UInt32: [UInt32]] = [:]
        var multis: [[UInt32]: [UInt32]] = [:]
        try LACDictionaryParser.forEachLine(replaceDictionary, file: LACModelMirror.replaceDictionaryName) { line in
            guard let pair = LACDictionaryParser.splitPair(line, separator: LACDictionaryParser.tab) else { return }
            if pair.0.count == 1, let key = pair.0.first {
                singles[key] = Array(pair.1)
            } else {
                multis[Array(pair.0)] = Array(pair.1)
            }
        }
        wordTrie = trie
        oovID = oov
        singleReplacements = singles
        multiReplacements = multis
    }

    /// Id theo thứ tự + số chữ mỗi id phủ (tổng = số scalar của câu).
    func encode(_ text: [UInt32], words: [Range<Int>]) -> (ids: [Int32], lengths: [Int]) {
        var ids: [Int32] = []
        var lengths: [Int] = []
        ids.reserveCapacity(text.count)
        lengths.reserveCapacity(text.count)
        for range in words {
            let word = text[range]
            if let found = wordTrie.lookup(word) {
                if let replaced = replacement(forWord: word) {
                    ids.append(id(of: replaced))
                } else {
                    ids.append(found)
                }
                lengths.append(range.count)
            } else {
                for index in range {
                    let scalar = text[index]
                    if let replaced = singleReplacements[scalar] {
                        ids.append(id(of: replaced))
                    } else {
                        ids.append(id(of: CollectionOfOne(scalar)))
                    }
                    lengths.append(1)
                }
            }
        }
        return (ids, lengths)
    }

    /// `word_replace_dict.get(từ)` cho cả từ (không có ⇒ `nil`, dùng chính từ).
    private func replacement(forWord word: ArraySlice<UInt32>) -> [UInt32]? {
        if word.count == 1, let scalar = word.first { return singleReplacements[scalar] }
        return multiReplacements.isEmpty ? nil : multiReplacements[Array(word)]
    }

    @inline(__always)
    private func id<C: Collection>(of scalars: C) -> Int32 where C.Element == UInt32 {
        wordTrie.lookup(scalars) ?? oovID
    }
}
