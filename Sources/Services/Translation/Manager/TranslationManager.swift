import Foundation

extension Notification.Name {
    public static let translationDictionariesDidUpdate = Notification.Name("translationDictionariesDidUpdate")
}

public final class TranslationManager: ObservableObject {
    public static let shared = TranslationManager()
    
    @Published public var isVietPhraseLoaded = false
    @Published public var isPhienAmLoaded = false
    @Published public var isNamesLoaded = false
    @Published public var isPronounsLoaded = false
    @Published public var isLuatNhanLoaded = false
    @Published public var isCustomVietPhraseLoaded = false
    @Published public var isCustomNamesLoaded = false
    @Published public var isInitialized = false
    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadMessage = ""
    
    public private(set) var vietPhraseDict: TrieDictionary?
    public private(set) var namesDict: TrieDictionary?
    public private(set) var pronounsDict: TrieDictionary?
    public private(set) var luatNhanDict: TrieDictionary?
    public private(set) var phienAmMap: [String: String] = [:]
    
    @Published public private(set) var customVietPhraseDict: TrieDictionary?
    @Published public private(set) var customNamesDict: TrieDictionary?
    public private(set) var deletedVietPhrase: Set<String> = []
    public private(set) var deletedNames: Set<String> = []
    @Published public private(set) var deletedVietPhraseList: [String] = []
    @Published public private(set) var deletedNamesList: [String] = []
    
    private var bookDicts: [String: (vietPhrase: TrieDictionary?, names: TrieDictionary?)] = [:]
    private var txtWordCountsCache: [String: Int] = [:]
    
    private init() {
        Task {
            try? await loadAllDictionaries()
        }
    }
    
    public func clearBookDictCache(for bookId: String? = nil) {
        if let bid = bookId {
            bookDicts.removeValue(forKey: bid)
        } else {
            bookDicts.removeAll()
        }
    }
    
    public func getBookDictionaries(for bookId: String) -> (vietPhrase: TrieDictionary?, names: TrieDictionary?) {
        if let cached = bookDicts[bookId] {
            return cached
        }
        
        let bookDir = translateDirectory.appendingPathComponent("books").appendingPathComponent(bookId)
        let vpTxtUrl = bookDir.appendingPathComponent("VietPhrase.txt")
        let namesTxtUrl = bookDir.appendingPathComponent("Names.txt")
        
        try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        
        var vp: TrieDictionary?
        var names: TrieDictionary?
        
        // Load VietPhrase
        if FileManager.default.fileExists(atPath: vpTxtUrl.path) {
            let text = TextDictionary()
            try? text.load(from: vpTxtUrl)
            if text.isLoaded, text.wordCount > 0 { vp = text }
        }
        
        // Load Names
        if FileManager.default.fileExists(atPath: namesTxtUrl.path) {
            let text = TextDictionary()
            try? text.load(from: namesTxtUrl)
            if text.isLoaded, text.wordCount > 0 { names = text }
        }
        
        let result = (vietPhrase: vp, names: names)
        bookDicts[bookId] = result
        return result
    }

    public func saveCustomEntry(word: String, meaning: String, isName: Bool, bookId: String?) async throws {
        let fileUrl = customTextURL(isName: isName, bookId: bookId)
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMeaning = DictionaryTextFileStore.normalizeMeaning(meaning)
        guard !cleanWord.isEmpty, !cleanMeaning.isEmpty else { return }
        
        // 1. Đọc danh sách custom/deleted theo đúng thứ tự file TXT.
        var records = (try? DictionaryTextFileStore.parseRecords(from: fileUrl)) ?? []
        
        // 2. Cập nhật hoặc thêm từ mới, đưa entry mới sửa lên đầu danh sách.
        records.removeAll { $0.key == cleanWord }
        records.insert(DictionaryTextRecord(key: cleanWord, value: cleanMeaning), at: 0)
        
        // 3. Ghi TXT-only; helper tự xoá file .dat custom cũ cùng tên nếu còn.
        try DictionaryTextFileStore.persist(records: records, to: fileUrl)
        
        // 4. Reset cache và nạp lại đúng phần bị ảnh hưởng (không đụng .dat / phiên âm)
        if let bid = bookId {
            // File TXT riêng của truyện đổi ⇒ chỉ cần bỏ cache; `getBookDictionaries` nạp lại lazy ở lần dịch sau.
            bookDicts.removeValue(forKey: bid)
        } else {
            // Invalidate global dictionary cache
            await MainActor.run {
                DictionaryCache.shared.invalidate(type: isName ? .names : .vietPhrase)
            }
            await reloadCustomDictionary(isName: isName)
        }
        notifyDictionariesDidUpdate(bookId: bookId, scope: .term(word: cleanWord, isName: isName, bookId: bookId))
    }

    public func deleteCustomEntry(word: String, isName: Bool, bookId: String?) async throws {
        let fileUrl = customTextURL(isName: isName, bookId: bookId)
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty else { return }
        
        // 1. Xóa dòng custom/deleted cũ cùng key.
        var records = (try? DictionaryTextFileStore.parseRecords(from: fileUrl)) ?? []
        let initialRecords = records
        records.removeAll { $0.key == cleanWord }
        
        // 2. Global delete của từ có trong base dictionary trở thành dòng blacklist `word=`.
        if bookId == nil, existsInBaseDictionary(word: cleanWord, isName: isName) {
            records.insert(DictionaryTextRecord(key: cleanWord, value: ""), at: 0)
        }

        if records != initialRecords {
            try DictionaryTextFileStore.persist(records: records, to: fileUrl)
        }
        
        // 3. Reset cache và nạp lại đúng phần bị ảnh hưởng (không đụng .dat / phiên âm)
        if let bid = bookId {
            bookDicts.removeValue(forKey: bid)
        } else {
            // Invalidate global dictionary cache
            await MainActor.run {
                DictionaryCache.shared.invalidate(type: isName ? .names : .vietPhrase)
            }
            await reloadCustomDictionary(isName: isName)
        }
        notifyDictionariesDidUpdate(bookId: bookId, scope: .term(word: cleanWord, isName: isName, bookId: bookId))
    }
    
    public func removeDeletedWords(_ words: [String], isName: Bool) {
        let fileUrl = customTextURL(isName: isName, bookId: nil)
        let wordSet = Set(words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        var records = (try? DictionaryTextFileStore.parseRecords(from: fileUrl)) ?? []
        records.removeAll { $0.isDeleted && wordSet.contains($0.key) }

        if (try? DictionaryTextFileStore.persist(records: records, to: fileUrl)) != nil {
            updateDeletedState(from: records, isName: isName)
            notifyDictionariesDidUpdate()
        }
    }

    /// Nạp lại **chỉ** từ điển custom global (`CustomNames.txt` / `CustomVietPhrase.txt`) và danh sách tombstone
    /// tương ứng, tương đương khối 1.1/2.1 của `loadAllDictionaries()`.
    ///
    /// Dùng cho mọi thao tác CRUD một từ: các file `.dat` chung và `ChinesePhienAmWords.txt` không hề bị thao tác đó
    /// ghi vào, nên nạp lại chúng là việc dư (đặc biệt `loadPhoneticMap` phải dựng lại hàng trăm nghìn entry).
    /// Cùng mẫu với `removeDeletedWords`: persist → cập nhật state hẹp → notify.
    public func reloadCustomDictionary(isName: Bool) async {
        let fileUrl = customTextURL(isName: isName, bookId: nil)
        var records: [DictionaryTextRecord] = []
        var reloaded: TrieDictionary? = nil

        if FileManager.default.fileExists(atPath: fileUrl.path) {
            records = (try? DictionaryTextFileStore.parseRecords(from: fileUrl)) ?? []
            let text = TextDictionary()
            try? text.load(from: fileUrl)
            if text.isLoaded, text.wordCount > 0 { reloaded = text }
        }

        let loaded = reloaded != nil
        if isName {
            self.customNamesDict = reloaded
        } else {
            self.customVietPhraseDict = reloaded
        }
        // Dòng blacklist `word=` là cách biểu diễn "đã xoá", phải cập nhật cùng lúc với dict.
        updateDeletedState(from: records, isName: isName)

        await MainActor.run {
            if isName {
                self.isCustomNamesLoaded = loaded
            } else {
                self.isCustomVietPhraseLoaded = loaded
            }
        }
    }

    public func existsInBaseDictionary(word: String, isName: Bool) -> Bool {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty else { return false }

        let loadedBaseDict = isName ? namesDict : vietPhraseDict
        if let loadedDict = loadedBaseDict,
           let match = loadedDict.findLongestMatch(text: cleanWord, startIndex: 0),
           match.length == cleanWord.count {
            return true
        }

        let baseFile = isName ? "Names.dat" : "VietPhrase.dat"
        let baseFileUrl = translateDirectory.appendingPathComponent(baseFile)
        guard FileManager.default.fileExists(atPath: baseFileUrl.path) else { return false }

        let dat = DoubleArrayTrie()
        try? dat.load(from: baseFileUrl)
        guard dat.isLoaded,
              let match = dat.findLongestMatch(text: cleanWord, startIndex: 0) else {
            return false
        }
        return match.length == cleanWord.count
    }

    private func customTextURL(isName: Bool, bookId: String?) -> URL {
        let fileName: String
        if bookId != nil {
            fileName = isName ? "Names.txt" : "VietPhrase.txt"
        } else {
            fileName = isName ? "CustomNames.txt" : "CustomVietPhrase.txt"
        }

        if let bid = bookId {
            let bookDir = translateDirectory.appendingPathComponent("books").appendingPathComponent(bid)
            try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
            return bookDir.appendingPathComponent(fileName)
        }

        return translateDirectory.appendingPathComponent(fileName)
    }

    private func updateDeletedState(from records: [DictionaryTextRecord], isName: Bool) {
        let deletedList = records.filter { $0.isDeleted }.map { $0.key }
        if isName {
            deletedNamesList = deletedList
            deletedNames = Set(deletedList)
        } else {
            deletedVietPhraseList = deletedList
            deletedVietPhrase = Set(deletedList)
        }
    }
    
    public var translateDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let directory = paths[0].appendingPathComponent("translate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }
    
    public func isDownloaded() -> Bool {
        let vpTxtExists = FileManager.default.fileExists(atPath: translateDirectory.appendingPathComponent("VietPhrase.txt").path)
        let vpDatExists = FileManager.default.fileExists(atPath: translateDirectory.appendingPathComponent("VietPhrase.dat").path)
        let paExists = FileManager.default.fileExists(atPath: translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt").path)
        return (vpTxtExists || vpDatExists) && paExists
    }
    
    public func loadAllDictionaries() async throws {
        defer {
            Task { @MainActor in
                self.isInitialized = true
            }
        }
        
        // 1. Load Names (Optional)
        let namesDatUrl = translateDirectory.appendingPathComponent("Names.dat")
        let namesTxtUrl = translateDirectory.appendingPathComponent("Names.txt")
        var tempNames: TrieDictionary? = nil
        
        if FileManager.default.fileExists(atPath: namesDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded { tempNames = dat }
        } else if FileManager.default.fileExists(atPath: namesTxtUrl.path) {
            // Compile on the fly
            try? DoubleArrayTrieBuilder().build(fromTxtFile: namesTxtUrl, toDatFile: namesDatUrl)
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded { 
                tempNames = dat
                try? FileManager.default.removeItem(at: namesTxtUrl)
            }
        }
        self.namesDict = tempNames
        let namesLoaded = tempNames != nil
        await MainActor.run { self.isNamesLoaded = namesLoaded }
        
        // 1.1 Load Custom Names (Optional, TXT-only)
        let customNamesTxtUrl = customTextURL(isName: true, bookId: nil)
        var tempCustomNames: TrieDictionary? = nil
        var customNameRecords: [DictionaryTextRecord] = []
        if FileManager.default.fileExists(atPath: customNamesTxtUrl.path) {
            customNameRecords = (try? DictionaryTextFileStore.parseRecords(from: customNamesTxtUrl)) ?? []
            let text = TextDictionary()
            try? text.load(from: customNamesTxtUrl)
            if text.isLoaded, text.wordCount > 0 { tempCustomNames = text }
        }
        self.customNamesDict = tempCustomNames
        let customNamesLoaded = tempCustomNames != nil
        await MainActor.run { self.isCustomNamesLoaded = customNamesLoaded }
        
        // 2. Load VietPhrase (Required)
        let vpDatUrl = translateDirectory.appendingPathComponent("VietPhrase.dat")
        let vpTxtUrl = translateDirectory.appendingPathComponent("VietPhrase.txt")
        var tempVP: TrieDictionary? = nil
        
        if FileManager.default.fileExists(atPath: vpDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: vpDatUrl)
            if dat.isLoaded { tempVP = dat }
        } else if FileManager.default.fileExists(atPath: vpTxtUrl.path) {
            // Compile on the fly
            try? DoubleArrayTrieBuilder().build(fromTxtFile: vpTxtUrl, toDatFile: vpDatUrl)
            let dat = DoubleArrayTrie()
            try? dat.load(from: vpDatUrl)
            if dat.isLoaded { 
                tempVP = dat
                try? FileManager.default.removeItem(at: vpTxtUrl)
            }
        }
        self.vietPhraseDict = tempVP
        let vpLoaded = tempVP != nil
        await MainActor.run { self.isVietPhraseLoaded = vpLoaded }
        
        // 2.1 Load Custom VietPhrase (Optional, TXT-only)
        let customVpTxtUrl = customTextURL(isName: false, bookId: nil)
        var tempCustomVP: TrieDictionary? = nil
        var customVPRecords: [DictionaryTextRecord] = []
        if FileManager.default.fileExists(atPath: customVpTxtUrl.path) {
            customVPRecords = (try? DictionaryTextFileStore.parseRecords(from: customVpTxtUrl)) ?? []
            let text = TextDictionary()
            try? text.load(from: customVpTxtUrl)
            if text.isLoaded, text.wordCount > 0 { tempCustomVP = text }
        }
        self.customVietPhraseDict = tempCustomVP
        let customVPLoaded = tempCustomVP != nil
        await MainActor.run { self.isCustomVietPhraseLoaded = customVPLoaded }
        
        // 3. Load Pronouns (Optional)
        let pronounsDatUrl = translateDirectory.appendingPathComponent("Pronouns.dat")
        let pronounsTxtUrl = translateDirectory.appendingPathComponent("Pronouns.txt")
        var tempPronouns: TrieDictionary? = nil
        
        if FileManager.default.fileExists(atPath: pronounsDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: pronounsDatUrl)
            if dat.isLoaded { tempPronouns = dat }
        } else if FileManager.default.fileExists(atPath: pronounsTxtUrl.path) {
            // Compile on the fly
            try? DoubleArrayTrieBuilder().build(fromTxtFile: pronounsTxtUrl, toDatFile: pronounsDatUrl)
            let dat = DoubleArrayTrie()
            try? dat.load(from: pronounsDatUrl)
            if dat.isLoaded { 
                tempPronouns = dat
                try? FileManager.default.removeItem(at: pronounsTxtUrl)
            }
        }
        self.pronounsDict = tempPronouns
        let pronounsLoaded = tempPronouns != nil
        await MainActor.run { self.isPronounsLoaded = pronounsLoaded }
        
        // 4. Load LuatNhan (Optional)
        let luatNhanDatUrl = translateDirectory.appendingPathComponent("LuatNhan.dat")
        let luatNhanTxtUrl = translateDirectory.appendingPathComponent("LuatNhan.txt")
        var tempLuatNhan: TrieDictionary? = nil
        
        if FileManager.default.fileExists(atPath: luatNhanDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: luatNhanDatUrl)
            if dat.isLoaded { tempLuatNhan = dat }
        } else if FileManager.default.fileExists(atPath: luatNhanTxtUrl.path) {
            // Compile on the fly
            try? DoubleArrayTrieBuilder().build(fromTxtFile: luatNhanTxtUrl, toDatFile: luatNhanDatUrl)
            let dat = DoubleArrayTrie()
            try? dat.load(from: luatNhanDatUrl)
            if dat.isLoaded { 
                tempLuatNhan = dat
                try? FileManager.default.removeItem(at: luatNhanTxtUrl)
            }
        }
        self.luatNhanDict = tempLuatNhan
        let luatNhanLoaded = tempLuatNhan != nil
        await MainActor.run { self.isLuatNhanLoaded = luatNhanLoaded }
        
        // 5. Load PhienAm (Required)
        let paTxtUrl = translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt")
        var tempPA: [String: String] = [:]
        let paLoaded: Bool
        if FileManager.default.fileExists(atPath: paTxtUrl.path) {
            var loaded = false
            do {
                tempPA = try loadPhoneticMap(from: paTxtUrl)
                loaded = true
            } catch {}
            paLoaded = loaded
        } else {
            paLoaded = false
        }
        self.phienAmMap = tempPA
        await MainActor.run { self.isPhienAmLoaded = paLoaded }
        
        // 6. Load Deleted lists from unified custom TXT files (`word=` lines)
        updateDeletedState(from: customVPRecords, isName: false)
        updateDeletedState(from: customNameRecords, isName: true)
    }

    public func notifyDictionariesDidUpdate(bookId: String? = nil, scope: DictionaryInvalidationScope = .globalReload) {
        TranslateUtils.invalidateCache(bookId: bookId)
        Task { @MainActor in
            var userInfo: [AnyHashable: Any] = [:]
            if let bookId { userInfo["bookId"] = bookId }
            userInfo["scope"] = scope
            NotificationCenter.default.post(
                name: .translationDictionariesDidUpdate,
                object: nil,
                userInfo: userInfo
            )
        }
    }
    
    private func loadPhoneticMap(from fileURL: URL) throws -> [String: String] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        var map: [String: String] = [:]
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            guard clean.contains("=") else { continue }
            let parts = clean.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty && !val.isEmpty {
                    map[key] = val
                }
            }
        }
        return map
    }
    
    public func importDictionary(from url: URL, type: String) async throws {
        let destName: String
        if type == "vietphrase" {
            destName = "VietPhrase.dat"
        } else if type == "names" {
            destName = "Names.dat"
        } else if type == "pronouns" {
            destName = "Pronouns.dat"
        } else if type == "luatnhan" {
            destName = "LuatNhan.dat"
        } else {
            destName = "ChinesePhienAmWords.txt"
        }
        
        let destUrl = translateDirectory.appendingPathComponent(destName)
        if FileManager.default.fileExists(atPath: destUrl.path) {
            try? FileManager.default.removeItem(at: destUrl)
        }
        
        if destName.hasSuffix(".dat") {
            try DoubleArrayTrieBuilder().build(fromTxtFile: url, toDatFile: destUrl)
        } else {
            try FileManager.default.copyItem(at: url, to: destUrl)
        }
        
        try await loadAllDictionaries()
        notifyDictionariesDidUpdate()
    }
    
    public func downloadDefaultDictionaries() async {
        await MainActor.run {
            self.isDownloading = true
            self.downloadProgress = 0.0
            self.downloadMessage = "Bắt đầu tải xuống..."
        }
        
        let files = [
            (name: "vietpharse.txt", localName: "VietPhrase.txt", required: true),
            (name: "phienam.txt", localName: "ChinesePhienAmWords.txt", required: true),
            (name: "pronouns.txt", localName: "Pronouns.txt", required: false),
            (name: "luatnhan.txt", localName: "LuatNhan.txt", required: false)
        ]
        
        var successCount = 0
        
        for (index, file) in files.enumerated() {
            let urlString = "https://huggingface.co/datasets/raikiri1498/vietpharse/resolve/main/\(file.name)"
            guard let url = URL(string: urlString) else { continue }
            
            await MainActor.run {
                self.downloadMessage = "Đang tải tệp \(file.name) (\(index + 1)/\(files.count))..."
                self.downloadProgress = Double(index) / Double(files.count)
            }
            
            do {
                let (tempUrl, response) = try await URLSession.shared.download(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "DownloadError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP Response"])
                }
                
                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "DownloadError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(httpResponse.statusCode)"])
                }
                
                let destUrl = translateDirectory.appendingPathComponent(file.localName)
                
                if FileManager.default.fileExists(atPath: destUrl.path) {
                    try? FileManager.default.removeItem(at: destUrl)
                }
                try FileManager.default.moveItem(at: tempUrl, to: destUrl)
                successCount += 1
            } catch {
                if file.required {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadMessage = "Lỗi khi tải tệp bắt buộc \(file.name): \(error.localizedDescription)"
                    }
                    return
                }
            }
        }
        
        let finalSuccessCount = successCount
        await MainActor.run {
            self.downloadProgress = 1.0
            self.downloadMessage = "Đã tải xong \(finalSuccessCount)/\(files.count) tệp!"
            self.isDownloading = false
        }
        
        do {
            try await loadAllDictionaries()
            notifyDictionariesDidUpdate()
        } catch {}
    }
    
    public func getWordCount(for type: String) -> Int? {
        // Bước 1: Thử lấy trực tiếp từ thực thể đã nạp sẵn trong RAM (O(1))
        if type == "vietphrase", let dict = vietPhraseDict {
            return dict.wordCount
        } else if type == "names", let dict = namesDict {
            return dict.wordCount
        } else if type == "pronouns", let dict = pronounsDict {
            return dict.wordCount
        } else if type == "luatnhan", let dict = luatNhanDict {
            return dict.wordCount
        } else if type == "phienam", !phienAmMap.isEmpty {
            return phienAmMap.count
        }
        
        let fileName: String
        if type == "vietphrase" {
            fileName = "VietPhrase.dat"
        } else if type == "names" {
            fileName = "Names.dat"
        } else if type == "pronouns" {
            fileName = "Pronouns.dat"
        } else if type == "luatnhan" {
            fileName = "LuatNhan.dat"
        } else if type == "phienam" {
            fileName = "ChinesePhienAmWords.txt"
        } else {
            return nil
        }
        
        let fileUrl = translateDirectory.appendingPathComponent(fileName)
        
        // Nếu file không tồn tại
        guard FileManager.default.fileExists(atPath: fileUrl.path) else {
            // Thử tìm file .txt dự phòng
            let fallbackName = fileName.replacingOccurrences(of: ".dat", with: ".txt")
            let fallbackUrl = translateDirectory.appendingPathComponent(fallbackName)
            guard FileManager.default.fileExists(atPath: fallbackUrl.path) else { return nil }
            
            // Đọc từ Cache hoặc đếm rồi lưu vào Cache
            if let cachedCount = txtWordCountsCache[type] {
                return cachedCount
            }
            if let content = try? String(contentsOf: fallbackUrl, encoding: .utf8) {
                let count = content.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("#") }
                    .count
                txtWordCountsCache[type] = count
                return count
            }
            return nil
        }
        
        // Bước 2: Nếu là file .dat, đọc nhanh 24 byte Header từ ổ đĩa (O(1))
        if fileName.hasSuffix(".dat") {
            if let fileHandle = try? FileHandle(forReadingFrom: fileUrl) {
                defer { try? fileHandle.close() }
                if let headerData = try? fileHandle.read(upToCount: 24), headerData.count >= 12 {
                    let size = headerData.withUnsafeBytes { pointer -> Int32 in
                        guard pointer.count >= 12 else { return 0 }
                        let rawValue = pointer.load(fromByteOffset: 8, as: Int32.self)
                        return Int32(bigEndian: rawValue)
                    }
                    if size > 0 {
                        return Int(size)
                    }
                }
            }
            
            // Fallback trong trường hợp đọc file nhị phân lỗi
            let dat = DoubleArrayTrie()
            try? dat.load(from: fileUrl)
            if dat.isLoaded {
                return dat.wordCount
            }
        } else {
            // Bước 3: Nếu là file .txt, sử dụng cache
            if let cachedCount = txtWordCountsCache[type] {
                return cachedCount
            }
            if let content = try? String(contentsOf: fileUrl, encoding: .utf8) {
                let count = content.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("#") }
                    .count
                txtWordCountsCache[type] = count
                return count
            }
        }
        return nil
    }
}
