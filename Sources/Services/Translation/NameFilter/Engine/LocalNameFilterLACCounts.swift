import Foundation

/// Bước 1 của phía LAC (`lacpipe.py`), cộng dồn theo chương: số lần mỗi từ LAC gắn nhãn thực thể theo **nhóm**
/// (PER ⇒ Nhân danh, LOC ⇒ Địa danh, ORG ⇒ Tổ chức, `nz` / `nw` ⇒ Thuật ngữ), các chương có mặt, số lần từ đó mang nhãn
/// **khác** (luật (e), luật phân loại L2 / L4), và chuỗi các dòng đã gắn nhãn (`joined` của Python — chỉ để đếm từ có chữ ngoài dải Hán của
/// bộ luật, như 奥斯汀·格里芬).
///
/// Chỉ thêm, không sửa phần đã có ⇒ chụp lúc nào cũng như chạy một lần trên đúng phần đã đọc. Một task dùng.
final class LocalNameFilterLACCounts {
    /// Số lần theo bốn nhóm, thứ tự `LocalNameFilter.Category.allCases` (cũng là thứ tự ưu tiên khi hoà).
    struct Tally: Sendable, Equatable {
        var person: Int32 = 0
        var place: Int32 = 0
        var organization: Int32 = 0
        var term: Int32 = 0

        var total: Int32 { person + place + organization + term }

        subscript(category: LocalNameFilter.Category) -> Int32 {
            get {
                switch category {
                case .person: return person
                case .place: return place
                case .organization: return organization
                case .term: return term
                }
            }
            set {
                switch category {
                case .person: person = newValue
                case .place: place = newValue
                case .organization: organization = newValue
                case .term: term = newValue
                }
            }
        }

        mutating func merge(_ other: Tally) {
            person += other.person
            place += other.place
            organization += other.organization
            term += other.term
        }

        /// `cnt.most_common(1)[0][0]`; hoà ⇒ nhóm đứng trước trong `Category.allCases` (Python bản tham chiếu dùng cùng
        /// thứ tự `TAG_PRIORITY`).
        var dominant: LocalNameFilter.Category {
            var best = LocalNameFilter.Category.person
            for category in LocalNameFilter.Category.allCases where self[category] > self[best] { best = category }
            return best
        }

        /// Nhóm của một nhãn LAC (đã gộp B/I); nhãn không phải thực thể ⇒ `nil`.
        static func category(ofTag tag: String) -> LocalNameFilter.Category? {
            switch tag {
            case "PER": return .person
            case "LOC": return .place
            case "ORG": return .organization
            case "nz", "nw": return .term
            default: return nil
            }
        }
    }

    struct Entry {
        var tally = Tally()
        /// Chỉ số chương có mặt, tăng dần (chương được cộng theo thứ tự đọc).
        var chapters: [Int32] = []
    }

    private(set) var entities: [LocalNameFilterWord: Entry] = [:]
    /// Số lần từ mang nhãn không phải thực thể — mọi từ ≥ 2 chữ có chữ Hán (`other[w]` của `lacpipe.py`; luật (e) và L2 / L4
    /// tự lọc từ cần xét). Bảng lớn cỡ vài chục nghìn mục với truyện 7 MB, sống trong lượt lọc.
    private(set) var others: [LocalNameFilterWord: Int32] = [:]
    /// Các dòng có chữ Hán đã gắn nhãn, nối bằng `\n` (UTF-16).
    private(set) var fullText: [UInt16] = []
    private(set) var chaptersRead = 0
    private(set) var taggedLines = 0
    private static let newline: UInt16 = 0x0A

    /// Cộng một chương (đúng thứ tự đọc — chương đọc hỏng không cộng, cũng như bộ luật không `feed`).
    func add(_ chapter: LocalNameFilterLACChapterTagger.Chapter) {
        let index = Int32(chaptersRead)
        chaptersRead += 1
        taggedLines += chapter.taggedLines
        for (word, tally) in chapter.entities {
            var entry = entities[word] ?? Entry()
            entry.tally.merge(tally)
            if entry.chapters.last != index { entry.chapters.append(index) }
            entities[word] = entry
        }
        for (word, count) in chapter.others { others[word, default: 0] += count }
        if !chapter.text.isEmpty {
            if !fullText.isEmpty { fullText.append(Self.newline) }
            fullText.append(contentsOf: chapter.text)
        }
    }

    /// `joined.count(s)` cho từ có chữ ngoài dải Hán của bộ luật: đếm không chồng lấn trên `fullText`.
    ///
    /// Đếm **cộng dần**: nhớ chỗ đã quét tới + số đã đếm, lần sau chỉ quét phần mới thêm. Từ không chứa `\n` nên không lần
    /// khớp nào vắt qua chỗ nối (phần mới luôn mở đầu bằng `\n`) ⇒ kết quả y như quét lại từ đầu.
    func countInFullText(_ units: [UInt16]) -> Int {
        let length = units.count
        guard length > 0 else { return 0 }
        var state = fullTextCounts[units] ?? FullTextCount()
        if state.scannedEnd == fullText.count { return state.count }
        fullText.withUnsafeBufferPointer { text in
            var position = max(state.nextAllowed, state.scannedEnd)
            let first = units[0]
            while position + length <= text.count {
                if text[position] == first {
                    var matches = true
                    for step in 1..<length where text[position + step] != units[step] {
                        matches = false
                        break
                    }
                    if matches {
                        state.count += 1
                        position += length
                        state.nextAllowed = position
                        continue
                    }
                }
                position += 1
            }
        }
        state.scannedEnd = fullText.count
        fullTextCounts[units] = state
        return state.count
    }

    private struct FullTextCount {
        var scannedEnd = 0
        var count = 0
        var nextAllowed = 0
    }

    private var fullTextCounts: [[UInt16]: FullTextCount] = [:]
}
