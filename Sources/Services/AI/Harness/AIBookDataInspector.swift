import Foundation

/// Cung cấp dữ liệu nội dung truyện và từ điển cho AI Agent Harness.
final class AIBookDataInspector: Sendable {
    static let shared = AIBookDataInspector()

    private init() {}

    /// Lấy danh sách tất cả các chương đã tải về (isCached = true) của cuốn sách.
    func fetchDownloadedChapters(bookId: String) async -> [StoredChapterSnapshot] {
        guard let toc = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId) else {
            return []
        }
        return toc.filter { $0.isCached && $0.length > 0 }
    }

    /// Đọc nội dung raw (chưa dịch) từ file binary của một chương đã tải.
    func readRawChapterContent(bookId: String, snapshot: StoredChapterSnapshot) async -> String? {
        guard snapshot.isCached, snapshot.length > 0 else { return nil }
        do {
            let raw = try await BookBinManager.shared.readChapterContent(
                bookId: bookId,
                offset: snapshot.offset,
                length: snapshot.length
            )
            return ChapterTextNormalizer.normalize(raw).content
        } catch {
            AppLogger.shared.log("Lỗi đọc nội dung raw chương \(snapshot.index): \(error.localizedDescription)")
            return nil
        }
    }

    /// Đọc nội dung raw của một chương theo index.
    func readRawChapterContent(bookId: String, chapterIndex: Int) async -> String? {
        guard let toc = try? await ChapterStore.shared.fetchOrderedTOC(bookId: bookId),
              let chapter = toc.first(where: { $0.index == chapterIndex }) else {
            return nil
        }
        return await readRawChapterContent(bookId: bookId, snapshot: chapter)
    }

    /// Lấy danh sách các từ/tên riêng đã có trong từ điển riêng của truyện.
    func fetchExistingNamesInBook(bookId: String) -> [String] {
        let translateDir = TranslationManager.shared.translateDirectory
        let bookDir = translateDir.appendingPathComponent("books").appendingPathComponent(bookId)
        let txtUrl = bookDir.appendingPathComponent("Names.txt")
        return DictionaryTextFileStore.loadEntries(from: txtUrl).map { $0.key }
    }

    /// Nạp ngữ cảnh từ điển Name riêng và VietPhrase riêng của truyện (lọc ưu tiên theo nội dung chương hiện tại).
    func fetchBookDictionaryContext(bookId: String, currentRawText: String = "") -> String {
        let translateDir = TranslationManager.shared.translateDirectory
        let bookDir = translateDir.appendingPathComponent("books").appendingPathComponent(bookId)
        let namesUrl = bookDir.appendingPathComponent("Names.txt")
        let vpUrl = bookDir.appendingPathComponent("VietPhrase.txt")

        let names = DictionaryTextFileStore.loadEntries(from: namesUrl)
        let vps = DictionaryTextFileStore.loadEntries(from: vpUrl)

        guard !names.isEmpty || !vps.isEmpty else { return "" }

        var result = ""

        if !names.isEmpty {
            let relevantNames = names.filter { !currentRawText.isEmpty && currentRawText.contains($0.key) }
            let recentNames = Array(names.suffix(80))
            var combinedSet = Set<String>()
            var chosenNames: [(key: String, value: String)] = []

            for item in (relevantNames + recentNames) {
                if !combinedSet.contains(item.key) {
                    combinedSet.insert(item.key)
                    chosenNames.append(item)
                }
            }

            result += "\n\n[Từ điển Name riêng đã có của truyện (\(names.count) mục)]:\n"
            for item in chosenNames.prefix(100) {
                result += "- \(item.key) = \(item.value)\n"
            }
        }

        if !vps.isEmpty {
            let relevantVps = vps.filter { !currentRawText.isEmpty && currentRawText.contains($0.key) }
            let recentVps = Array(vps.suffix(80))
            var combinedSet = Set<String>()
            var chosenVps: [(key: String, value: String)] = []

            for item in (relevantVps + recentVps) {
                if !combinedSet.contains(item.key) {
                    combinedSet.insert(item.key)
                    chosenVps.append(item)
                }
            }

            result += "\n[Từ điển VietPhrase riêng đã có của truyện (\(vps.count) mục)]:\n"
            for item in chosenVps.prefix(100) {
                result += "- \(item.key) = \(item.value)\n"
            }
        }

        return result
    }

    /// Lấy tập hợp Name riêng và VP riêng của cuốn truyện dưới dạng Set để tra cứu nhanh O(1).
    func fetchBookDictionarySets(bookId: String) -> (names: Set<String>, vps: Set<String>) {
        let translateDir = TranslationManager.shared.translateDirectory
        let bookDir = translateDir.appendingPathComponent("books").appendingPathComponent(bookId)
        let namesUrl = bookDir.appendingPathComponent("Names.txt")
        let vpUrl = bookDir.appendingPathComponent("VietPhrase.txt")

        let names = DictionaryTextFileStore.loadEntries(from: namesUrl).map { $0.key }
        let vps = DictionaryTextFileStore.loadEntries(from: vpUrl).map { $0.key }
        return (Set(names), Set(vps))
    }

    /// Kiểm tra từ/tên riêng đã có trong từ điển Name (riêng, custom, hoặc chung).
    func checkWordInNames(word: String, bookNames: Set<String>) -> Bool {
        if bookNames.contains(word) { return true }
        let tm = TranslationManager.shared
        let utf16Len = word.utf16.count
        if let customNames = tm.customNamesDict,
           let match = customNames.findLongestMatch(text: word, startIndex: 0),
           match.length == utf16Len {
            return true
        }
        if !tm.deletedNames.contains(word), tm.existsInBaseDictionary(word: word, isName: true) {
            return true
        }
        return false
    }

    /// Kiểm tra từ/tên riêng đã có trong từ điển VietPhrase (riêng, custom, hoặc chung).
    func checkWordInVietPhrase(word: String, bookVPs: Set<String>) -> Bool {
        if bookVPs.contains(word) { return true }
        let tm = TranslationManager.shared
        let utf16Len = word.utf16.count
        if let customVP = tm.customVietPhraseDict,
           let match = customVP.findLongestMatch(text: word, startIndex: 0),
           match.length == utf16Len {
            return true
        }
        if !tm.deletedVietPhrase.contains(word), tm.existsInBaseDictionary(word: word, isName: false) {
            return true
        }
        return false
    }

    /// Bổ sung trạng thái từ điển đã có cho danh sách tên riêng trích xuất được.
    /// Kiểm tra cả từ điển riêng và chung; nếu từ đã có trong Names hoặc VP thì gắn cờ tương ứng và tự bỏ chọn ban đầu.
    func decorateExtractedNames(names: [AIExtractedName], bookId: String) -> [AIExtractedName] {
        let (bookNames, bookVPs) = fetchBookDictionarySets(bookId: bookId)
        return names.map { item in
            var copy = item
            let orig = item.original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !orig.isEmpty else { return copy }
            let inNames = checkWordInNames(word: orig, bookNames: bookNames)
            let inVP = checkWordInVietPhrase(word: orig, bookVPs: bookVPs)
            copy.hasInBookNames = inNames
            copy.hasInBookVP = inVP
            if inNames || inVP {
                copy.isSelected = false
            }
            return copy
        }
    }
}
