import Foundation

/// Lượt 1 của bộ lọc name local, chạy dần theo chương — `Stream.feed` + `candidates_in_run` của bản thử Python.
///
/// Giữ toàn bộ chữ Hán đã đọc thành **một** mảng UTF-16 `text`: các đoạn Hán liền (`HAN_RUN`) nối bằng `\n` — đúng chuỗi
/// `joined` của Python — kèm biên từng đoạn, và chỉ mục vị trí theo chữ (cho `text_count`). Đếm ứng viên: số lần **sinh ra**
/// (một cụm ở cùng vị trí có thể được sinh hai lần — họ kép + họ đơn, 山谷 + 谷… — đúng như Python, không gộp), tập loại
/// `(kind, extra)`, số chương có mặt, và với danh xưng 1 chữ: các phần đứng trước khác nhau (`pred`).
///
/// Chỉ thêm, không bao giờ sửa phần đã có ⇒ lượt 2 chạy trên một trạng thái bất kỳ cho kết quả như chạy một lần trên đúng
/// phần đó.
final class LocalNameFilterAccumulator {
    struct TermStats {
        /// `count[term]`: số lần sinh ra ở lượt 1.
        var count: Int32 = 0
        /// `kinds[term]`: bit `LocalNameFilterRules.kindBit`.
        var kinds: UInt8 = 0
        /// `len(chap_seen[term])`: chương được đọc lần lượt, nên chỉ cần nhớ chương cuối.
        var chapters: Int32 = 0
        var lastChapter: Int32 = -1

        @inline(__always)
        mutating func add(kindBit: UInt8, chapter: Int32) {
            count += 1
            kinds |= kindBit
            if lastChapter != chapter {
                lastChapter = chapter
                chapters += 1
            }
        }
    }

    private let setup: LocalNameFilterSetup
    private static let newline: UInt16 = 0x0A

    /// Chuỗi `joined` của Python dưới dạng UTF-16.
    private(set) var text: [UInt16] = []
    /// Biên `[start, end)` của từng đoạn Hán trong `text`.
    private(set) var runStarts: [Int] = []
    private(set) var runEnds: [Int] = []
    /// Vị trí (trong `text`) của mọi chữ Hán, theo chữ — tăng dần.
    private(set) var positionsByUnit: [[Int32]] = Array(repeating: [], count: 65_536)
    private(set) var stats: [LocalNameFilterTermKey: TermStats] = [:]
    /// `pred` của Python, chỉ cho danh xưng **1 chữ** (danh xưng ≥ 2 chữ luôn là danh xưng, không cần đếm); dừng thêm khi
    /// đủ `titleMinPredecessors`.
    private(set) var predecessors: [LocalNameFilterTermKey: Set<LocalNameFilterTermKey>] = [:]
    private(set) var chaptersRead = 0
    private(set) var hanCount = 0

    private let personBits: [UInt8]
    private let familyBits: [UInt8]
    private let placeBits: [UInt8]
    private let sectBits: [UInt8]

    init(setup: LocalNameFilterSetup) {
        self.setup = setup
        let order = LocalNameFilterRules.order(of:)
        personBits = [0, LocalNameFilterRules.kindBit(order: order(.person), extra: 1),
                      LocalNameFilterRules.kindBit(order: order(.person), extra: 2)]
        familyBits = [0, LocalNameFilterRules.kindBit(order: order(.family), extra: 1),
                      LocalNameFilterRules.kindBit(order: order(.family), extra: 2)]
        placeBits = [0, LocalNameFilterRules.kindBit(order: order(.place), extra: 1),
                     LocalNameFilterRules.kindBit(order: order(.place), extra: 2)]
        sectBits = [0, LocalNameFilterRules.kindBit(order: order(.sect), extra: 1),
                    LocalNameFilterRules.kindBit(order: order(.sect), extra: 2)]
    }

    /// `Stream.feed(chapter)`: tách các đoạn Hán liền của chương (theo đơn vị UTF-16, không theo `Character` — chữ Hán kèm
    /// dấu biến thể vẫn bị cắt như regex của Python), nối vào `text`, sinh ứng viên của từng đoạn.
    func feed(_ chapterText: String) {
        let chapter = Int32(chaptersRead)
        chaptersRead += 1
        var runStart = -1
        for unit in chapterText.utf16 {
            if LocalNameFilterRules.isHan(unit) {
                if runStart < 0 {
                    if !text.isEmpty { text.append(Self.newline) }
                    runStart = text.count
                }
                text.append(unit)
            } else if runStart >= 0 {
                closeRun(start: runStart, chapter: chapter)
                runStart = -1
            }
        }
        if runStart >= 0 { closeRun(start: runStart, chapter: chapter) }
    }

    private func closeRun(start: Int, chapter: Int32) {
        let end = text.count
        runStarts.append(start)
        runEnds.append(end)
        hanCount += end - start
        for position in start..<end {
            positionsByUnit[Int(text[position])].append(Int32(position))
        }
        text.withUnsafeBufferPointer { buffer in
            collectCandidates(buffer, start: start, end: end, chapter: chapter)
        }
    }

    /// `candidates_in_run(run)` — mọi lần sinh đều được đếm (xem doc của type).
    private func collectCandidates(_ units: UnsafeBufferPointer<UInt16>, start: Int, end: Int, chapter: Int32) {
        let length = end - start
        // Họ (2 chữ rồi 1 chữ) + 1–2 chữ tên; họ + 家 / 氏 / 族.
        for offset in 0..<length {
            let position = start + offset
            let unit = units[position]
            for surnameLength in stride(from: 2, through: 1, by: -1) {
                guard offset + surnameLength <= length else { continue }
                if surnameLength == 2 {
                    guard setup.has(unit, .surnamePairStart),
                          setup.surnamePairs.contains(LocalNameFilterRules.pair(unit, units[position + 1])) else { continue }
                } else {
                    guard setup.has(unit, .surnameSingle) else { continue }
                }
                for givenLength in 1...2 where offset + surnameLength + givenLength <= length {
                    let term = LocalNameFilterTermKey(units, start: position, count: surnameLength + givenLength)
                    record(term, kindBit: personBits[surnameLength], chapter: chapter)
                    notePronounPredecessor(term, surnameLength: surnameLength)
                }
                if offset + surnameLength < length, LocalNameFilterRules.has(units[position + surnameLength], .family) {
                    let term = LocalNameFilterTermKey(units, start: position, count: surnameLength + 1)
                    record(term, kindBit: familyBits[surnameLength], chapter: chapter)
                }
            }
        }
        // Đuôi địa danh / tông môn: mọi chỗ xuất hiện (chồng lấn được, như `run.find(suf, j + 1)`), 1–3 chữ đứng trước.
        for offset in 0..<length {
            let position = start + offset
            let unit = units[position]
            if setup.has(unit, .placeSuffix) { recordSuffix(units, start: start, at: offset, suffixLength: 1, bit: placeBits[1], chapter: chapter) }
            if setup.has(unit, .sectSuffix) { recordSuffix(units, start: start, at: offset, suffixLength: 1, bit: sectBits[1], chapter: chapter) }
            if offset + 2 <= length, setup.has(unit, .suffixPairStart),
               let kinds = setup.pairSuffixKinds[LocalNameFilterRules.pair(unit, units[position + 1])] {
                if kinds & LocalNameFilterSetup.placeKindBit != 0 {
                    recordSuffix(units, start: start, at: offset, suffixLength: 2, bit: placeBits[2], chapter: chapter)
                }
                if kinds & LocalNameFilterSetup.sectKindBit != 0 {
                    recordSuffix(units, start: start, at: offset, suffixLength: 2, bit: sectBits[2], chapter: chapter)
                }
            }
        }
    }

    @inline(__always)
    private func recordSuffix(_ units: UnsafeBufferPointer<UInt16>, start: Int, at offset: Int, suffixLength: Int,
                              bit: UInt8, chapter: Int32) {
        for prefixLength in 1...3 where offset - prefixLength >= 0 {
            let term = LocalNameFilterTermKey(units, start: start + offset - prefixLength, count: prefixLength + suffixLength)
            record(term, kindBit: bit, chapter: chapter)
        }
    }

    @inline(__always)
    private func record(_ term: LocalNameFilterTermKey, kindBit: UInt8, chapter: Int32) {
        stats[term, default: TermStats()].add(kindBit: kindBit, chapter: chapter)
    }

    /// `pred[p].add(term[:-len(p)])` cho ứng viên tên người — chỉ giữ cho danh xưng 1 chữ.
    @inline(__always)
    private func notePronounPredecessor(_ term: LocalNameFilterTermKey, surnameLength: Int) {
        guard !setup.pronouns.isEmpty, let tail = setup.pronounTail(of: term, surnameLength: surnameLength),
              tail.count == 1, let head = term.dropLast(1) else { return }
        if (predecessors[tail]?.count ?? 0) >= LocalNameFilterRules.titleMinPredecessors { return }
        predecessors[tail, default: []].insert(head)
    }

    /// `Stream.titles()`: mọi danh xưng ≥ 2 chữ + danh xưng 1 chữ đứng sau ≥ `TITLE_MIN_PREDECESSORS` tên / họ khác nhau.
    func titles() -> Set<LocalNameFilterTermKey> {
        var result = Set<LocalNameFilterTermKey>()
        for term in setup.pronouns.keys {
            if term.count >= 2 || (predecessors[term]?.count ?? 0) >= LocalNameFilterRules.titleMinPredecessors {
                result.insert(term)
            }
        }
        return result
    }
}
