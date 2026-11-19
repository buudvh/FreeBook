import Foundation

/// Nạp lại **riêng** một từ điển gốc sau khi danh sách Phiên âm / Pronouns sửa thẳng file (`GlobalDictionaryEditor`) —
/// không gọi `loadAllDictionaries()` (nạp lại cả VietPhrase / Names / lớp custom mỗi lần lưu một mục).
/// Cùng luật nạp với khối tương ứng của `loadAllDictionaries()`.
extension TranslationManager {
    func reloadPronounsDictionary() async {
        let url = translateDirectory.appendingPathComponent("Pronouns.dat")
        var loaded: FrozenTrieDictionary?
        if FileManager.default.fileExists(atPath: url.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: url)
            if dat.isLoaded { loaded = dat.frozen() }
        }
        dictionaryState.update { $0.pronouns = loaded }
        let isLoaded = loaded != nil
        await MainActor.run { self.isPronounsLoaded = isLoaded }
    }

    func reloadPhienAmMap() async {
        let url = translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt")
        let map: [String: String]? = FileManager.default.fileExists(atPath: url.path)
            ? (try? Self.loadPhoneticMap(from: url)) : nil
        dictionaryState.update { $0.phienAm = map ?? [:] }
        let isLoaded = map != nil
        await MainActor.run { self.isPhienAmLoaded = isLoaded }
    }
}
