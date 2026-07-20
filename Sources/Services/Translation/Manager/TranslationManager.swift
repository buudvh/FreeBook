import Foundation

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
    
    public private(set) var customVietPhraseDict: TrieDictionary?
    public private(set) var customNamesDict: TrieDictionary?
    public private(set) var deletedVietPhrase: Set<String> = []
    public private(set) var deletedNames: Set<String> = []
    
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
        let vpDatUrl = bookDir.appendingPathComponent("VietPhrase.dat")
        let namesTxtUrl = bookDir.appendingPathComponent("Names.txt")
        let namesDatUrl = bookDir.appendingPathComponent("Names.dat")
        
        try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        
        var vp: TrieDictionary?
        var names: TrieDictionary?
        
        // Load VietPhrase
        if FileManager.default.fileExists(atPath: vpDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: vpDatUrl)
            if dat.isLoaded { vp = dat }
        } else if FileManager.default.fileExists(atPath: vpTxtUrl.path) {
            // Compile on the fly
            try? DoubleArrayTrieBuilder().build(fromTxtFile: vpTxtUrl, toDatFile: vpDatUrl)
            let dat = DoubleArrayTrie()
            try? dat.load(from: vpDatUrl)
            if dat.isLoaded { vp = dat }
        }
        
        // Load Names
        if FileManager.default.fileExists(atPath: namesDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded { names = dat }
        } else if FileManager.default.fileExists(atPath: namesTxtUrl.path) {
            // Compile on the fly
            try? DoubleArrayTrieBuilder().build(fromTxtFile: namesTxtUrl, toDatFile: namesDatUrl)
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded { names = dat }
        }
        
        let result = (vietPhrase: vp, names: names)
        bookDicts[bookId] = result
        return result
    }
    
    private func saveDeletedList(isName: Bool) {
        let fileName = isName ? "DeletedNames.txt" : "DeletedVietPhrase.txt"
        let fileUrl = translateDirectory.appendingPathComponent(fileName)
        let list = isName ? deletedNames : deletedVietPhrase
        let content = list.joined(separator: "\n")
        try? content.write(to: fileUrl, atomically: true, encoding: .utf8)
    }

    public func saveCustomEntry(word: String, meaning: String, isName: Bool, bookId: String?) async throws {
        let fileName: String
        if bookId != nil {
            fileName = isName ? "Names.dat" : "VietPhrase.dat"
        } else {
            fileName = isName ? "CustomNames.dat" : "CustomVietPhrase.dat"
        }
        
        let fileUrl: URL
        if let bid = bookId {
            let bookDir = translateDirectory.appendingPathComponent("books").appendingPathComponent(bid)
            try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
            fileUrl = bookDir.appendingPathComponent(fileName)
        } else {
            fileUrl = translateDirectory.appendingPathComponent(fileName)
        }
        
        // 1. Đọc ngược các từ hiện có từ file .dat (nếu có)
        var entries: [(key: String, value: String)] = []
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: fileUrl)
            if dat.isLoaded {
                entries = dat.allEntries()
            }
        }
        
        // 2. Cập nhật hoặc thêm từ mới
        var found = false
        for i in 0..<entries.count {
            if entries[i].key == word {
                entries[i].value = meaning
                found = true
                break
            }
        }
        
        if !found {
            entries.append((key: word, value: meaning))
        }
        
        // 3. Biên dịch trực tiếp ra file .dat ghi đè lên vị trí cũ
        try DoubleArrayTrieBuilder().build(fromEntries: entries, toDatFile: fileUrl)
        
        // 4. Nếu là global, kiểm tra và gỡ khỏi danh sách bị xóa (nếu có)
        if bookId == nil {
            if isName {
                if deletedNames.contains(word) {
                    deletedNames.remove(word)
                    saveDeletedList(isName: true)
                }
            } else {
                if deletedVietPhrase.contains(word) {
                    deletedVietPhrase.remove(word)
                    saveDeletedList(isName: false)
                }
            }
        }
        
        // 5. Reset cache và load lại
        TranslateUtils.clearCache()
        if let bid = bookId {
            bookDicts.removeValue(forKey: bid)
        } else {
            // Invalidate global dictionary cache
            await MainActor.run {
                DictionaryCache.shared.invalidate(type: isName ? .names : .vietPhrase)
            }
        }
        try await loadAllDictionaries()
    }
    
    public func deleteCustomEntry(word: String, isName: Bool, bookId: String?) async throws {
        let fileName: String
        if bookId != nil {
            fileName = isName ? "Names.dat" : "VietPhrase.dat"
        } else {
            fileName = isName ? "CustomNames.dat" : "CustomVietPhrase.dat"
        }
        
        let fileUrl: URL
        if let bid = bookId {
            let bookDir = translateDirectory.appendingPathComponent("books").appendingPathComponent(bid)
            fileUrl = bookDir.appendingPathComponent(fileName)
        } else {
            fileUrl = translateDirectory.appendingPathComponent(fileName)
        }
        
        // 1. Xóa từ trong file Custom (hoặc file Book) nếu tồn tại
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: fileUrl)
            if dat.isLoaded {
                var entries = dat.allEntries()
                let initialCount = entries.count
                entries.removeAll { $0.key == word }
                if entries.count < initialCount {
                    if entries.isEmpty {
                        try? FileManager.default.removeItem(at: fileUrl)
                    } else {
                        try DoubleArrayTrieBuilder().build(fromEntries: entries, toDatFile: fileUrl)
                    }
                }
            }
        }
        
        // 2. Nếu là global (bookId == nil), kiểm tra xem từ này có nằm trong từ điển gốc không.
        // Nếu có, thêm vào danh sách bị xóa (blacklist) để ẩn nó đi.
        if bookId == nil {
            let baseFile = isName ? "Names.dat" : "VietPhrase.dat"
            let baseFileUrl = translateDirectory.appendingPathComponent(baseFile)
            var existsInBase = false
            
            if FileManager.default.fileExists(atPath: baseFileUrl.path) {
                let dat = DoubleArrayTrie()
                try? dat.load(from: baseFileUrl)
                if dat.isLoaded {
                    if let match = dat.findLongestMatch(text: word, startIndex: 0), match.length == word.count {
                        existsInBase = true
                    }
                }
            }
            
            if existsInBase {
                if isName {
                    deletedNames.insert(word)
                    saveDeletedList(isName: true)
                } else {
                    deletedVietPhrase.insert(word)
                    saveDeletedList(isName: false)
                }
            }
        }
        
        // 3. Reset cache và load lại
        TranslateUtils.clearCache()
        if let bid = bookId {
            bookDicts.removeValue(forKey: bid)
        } else {
            // Invalidate global dictionary cache
            await MainActor.run {
                DictionaryCache.shared.invalidate(type: isName ? .names : .vietPhrase)
            }
        }
        try await loadAllDictionaries()
    }
    
    public func addDeletedWords(_ words: Set<String>, isName: Bool) {
        if isName {
            deletedNames.formUnion(words)
            saveDeletedList(isName: true)
        } else {
            deletedVietPhrase.formUnion(words)
            saveDeletedList(isName: false)
        }
    }
    
    public func removeDeletedWords(_ words: [String], isName: Bool) {
        if isName {
            for w in words { deletedNames.remove(w) }
            saveDeletedList(isName: true)
        } else {
            for w in words { deletedVietPhrase.remove(w) }
            saveDeletedList(isName: false)
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
        
        // 1.1 Load Custom Names (Optional)
        let customNamesDatUrl = translateDirectory.appendingPathComponent("CustomNames.dat")
        var tempCustomNames: TrieDictionary? = nil
        if FileManager.default.fileExists(atPath: customNamesDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: customNamesDatUrl)
            if dat.isLoaded { tempCustomNames = dat }
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
        
        // 2.1 Load Custom VietPhrase (Optional)
        let customVpDatUrl = translateDirectory.appendingPathComponent("CustomVietPhrase.dat")
        var tempCustomVP: TrieDictionary? = nil
        if FileManager.default.fileExists(atPath: customVpDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: customVpDatUrl)
            if dat.isLoaded { tempCustomVP = dat }
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
        
        // 6. Load Deleted lists
        let delVPUrl = translateDirectory.appendingPathComponent("DeletedVietPhrase.txt")
        var delVP: Set<String> = []
        if let content = try? String(contentsOf: delVPUrl, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { delVP.insert(clean) }
            }
        }
        self.deletedVietPhrase = delVP

        let delNamesUrl = translateDirectory.appendingPathComponent("DeletedNames.txt")
        var delNames: Set<String> = []
        if let content = try? String(contentsOf: delNamesUrl, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { delNames.insert(clean) }
            }
        }
        self.deletedNames = delNames
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
    }
    
    public func deleteDictionary(type: String) async {
        if type == "vietphrase" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("VietPhrase.txt"))
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("VietPhrase.dat"))
            self.vietPhraseDict = nil
            await MainActor.run { self.isVietPhraseLoaded = false }
        } else if type == "names" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("Names.txt"))
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("Names.dat"))
            self.namesDict = nil
            await MainActor.run { self.isNamesLoaded = false }
        } else if type == "pronouns" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("Pronouns.txt"))
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("Pronouns.dat"))
            self.pronounsDict = nil
            await MainActor.run { self.isPronounsLoaded = false }
        } else if type == "luatnhan" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("LuatNhan.txt"))
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("LuatNhan.dat"))
            self.luatNhanDict = nil
            await MainActor.run { self.isLuatNhanLoaded = false }
        } else if type == "phienam" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt"))
            self.phienAmMap = [:]
            await MainActor.run { self.isPhienAmLoaded = false }
        }
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

