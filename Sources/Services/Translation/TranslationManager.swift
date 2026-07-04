import Foundation

public final class TranslationManager: ObservableObject {
    public static let shared = TranslationManager()
    
    @Published public var isVietPhraseLoaded = false
    @Published public var isPhienAmLoaded = false
    @Published public var isNamesLoaded = false
    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadMessage = ""
    
    public private(set) var vietPhraseDict: TrieDictionary?
    public private(set) var namesDict: TrieDictionary?
    public private(set) var phienAmMap: [String: String] = [:]
    
    private var bookDicts: [String: (vietPhrase: TrieDictionary?, names: TrieDictionary?)] = [:]
    
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
        let vpDatUrl = bookDir.appendingPathComponent("VietPhrase.dat")
        let vpTxtUrl = bookDir.appendingPathComponent("VietPhrase.txt")
        let namesDatUrl = bookDir.appendingPathComponent("Names.dat")
        let namesTxtUrl = bookDir.appendingPathComponent("Names.txt")
        
        try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
        
        var vp: TrieDictionary?
        var names: TrieDictionary?
        
        if FileManager.default.fileExists(atPath: vpDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: vpDatUrl)
            if dat.isLoaded { vp = dat }
        }
        if vp == nil && FileManager.default.fileExists(atPath: vpTxtUrl.path) {
            let txt = TextDictionary()
            try? txt.load(from: vpTxtUrl)
            if txt.isLoaded { vp = txt }
        }
        
        if FileManager.default.fileExists(atPath: namesDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded { names = dat }
        }
        if names == nil && FileManager.default.fileExists(atPath: namesTxtUrl.path) {
            let txt = TextDictionary()
            try? txt.load(from: namesTxtUrl)
            if txt.isLoaded { names = txt }
        }
        
        let result = (vietPhrase: vp, names: names)
        bookDicts[bookId] = result
        return result
    }
    
    public func saveCustomEntry(word: String, meaning: String, isName: Bool, bookId: String?) async throws {
        let fileName = isName ? "Names.txt" : "VietPhrase.txt"
        
        let fileUrl: URL
        if let bid = bookId {
            let bookDir = translateDirectory.appendingPathComponent("books").appendingPathComponent(bid)
            try? FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)
            fileUrl = bookDir.appendingPathComponent(fileName)
        } else {
            fileUrl = translateDirectory.appendingPathComponent(fileName)
        }
        
        var content = ""
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            content = (try? String(contentsOf: fileUrl, encoding: .utf8)) ?? ""
        }
        
        var lines = content.components(separatedBy: .newlines)
        var found = false
        for i in 0..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("\(word)=") {
                lines[i] = "\(word)=\(meaning)"
                found = true
                break
            }
        }
        
        if !found {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("\(word)=\(meaning)")
        }
        
        let newContent = lines.joined(separator: "\n")
        try newContent.write(to: fileUrl, atomically: true, encoding: .utf8)
        
        TranslateUtils.clearCache()
        if let bid = bookId {
            bookDicts.removeValue(forKey: bid)
        }
        try await loadAllDictionaries()
    }
    
    public var translateDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let directory = paths[0].appendingPathComponent("translate", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }
    
    public func isDownloaded() -> Bool {
        let vpExists = FileManager.default.fileExists(atPath: translateDirectory.appendingPathComponent("VietPhrase.dat").path) ||
                       FileManager.default.fileExists(atPath: translateDirectory.appendingPathComponent("VietPhrase.txt").path)
        let paExists = FileManager.default.fileExists(atPath: translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt").path)
        return vpExists && paExists
    }
    
    public func loadAllDictionaries() async throws {
        AppLogger.shared.log("📚 Loading translation dictionaries...")
        
        // 1. Load Names (Optional)
        let namesDatUrl = translateDirectory.appendingPathComponent("Names.dat")
        let namesTxtUrl = translateDirectory.appendingPathComponent("Names.txt")
        
        var tempNames: TrieDictionary? = nil
        if FileManager.default.fileExists(atPath: namesDatUrl.path) {
            let dat = DoubleArrayTrie()
            try? dat.load(from: namesDatUrl)
            if dat.isLoaded {
                tempNames = dat
                AppLogger.shared.log("📚 Names dictionary loaded (.dat)")
            }
        }
        
        if tempNames == nil && FileManager.default.fileExists(atPath: namesTxtUrl.path) {
            let txt = TextDictionary()
            try? txt.load(from: namesTxtUrl)
            if txt.isLoaded {
                tempNames = txt
                AppLogger.shared.log("📚 Names dictionary loaded (.txt)")
            }
        }
        
        self.namesDict = tempNames
        let namesLoaded = tempNames != nil
        await MainActor.run { self.isNamesLoaded = namesLoaded }
        if !namesLoaded {
            AppLogger.shared.log("📚 Names dictionary is missing (optional, skipped)")
        }
        
        // 2. Load VietPhrase (Required)
        let vpDatUrl = translateDirectory.appendingPathComponent("VietPhrase.dat")
        let vpTxtUrl = translateDirectory.appendingPathComponent("VietPhrase.txt")
        var tempVP: TrieDictionary? = nil
        
        if FileManager.default.fileExists(atPath: vpDatUrl.path) {
            let dat = DoubleArrayTrie()
            do {
                try dat.load(from: vpDatUrl)
                if dat.isLoaded {
                    tempVP = dat
                    AppLogger.shared.log("📚 VietPhrase dictionary loaded (.dat)")
                }
            } catch {
                AppLogger.shared.log("❌ Failed to load VietPhrase.dat: \(error.localizedDescription)")
            }
        }
        
        if tempVP == nil && FileManager.default.fileExists(atPath: vpTxtUrl.path) {
            let txt = TextDictionary()
            do {
                try txt.load(from: vpTxtUrl)
                if txt.isLoaded {
                    tempVP = txt
                    AppLogger.shared.log("📚 VietPhrase dictionary loaded (.txt)")
                }
            } catch {
                AppLogger.shared.log("❌ Failed to load VietPhrase.txt: \(error.localizedDescription)")
            }
        }
        
        self.vietPhraseDict = tempVP
        let vpLoaded = tempVP != nil
        await MainActor.run { self.isVietPhraseLoaded = vpLoaded }
        
        // 3. Load PhienAm (Required)
        let paTxtUrl = translateDirectory.appendingPathComponent("ChinesePhienAmWords.txt")
        var tempPA: [String: String] = [:]
        var paLoaded = false
        
        if FileManager.default.fileExists(atPath: paTxtUrl.path) {
            do {
                tempPA = try loadPhoneticMap(from: paTxtUrl)
                paLoaded = true
                AppLogger.shared.log("📚 PhienAm dictionary loaded (\(tempPA.count) entries)")
            } catch {
                AppLogger.shared.log("❌ Failed to load ChinesePhienAmWords.txt: \(error.localizedDescription)")
            }
        }
        
        self.phienAmMap = tempPA
        await MainActor.run { self.isPhienAmLoaded = paLoaded }
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
            destName = url.pathExtension == "dat" ? "VietPhrase.dat" : "VietPhrase.txt"
        } else if type == "names" {
            destName = url.pathExtension == "dat" ? "Names.dat" : "Names.txt"
        } else {
            destName = "ChinesePhienAmWords.txt"
        }
        
        let destUrl = translateDirectory.appendingPathComponent(destName)
        
        if FileManager.default.fileExists(atPath: destUrl.path) {
            try? FileManager.default.removeItem(at: destUrl)
        }
        
        try FileManager.default.copyItem(at: url, to: destUrl)
        try await loadAllDictionaries()
    }
    
    public func deleteDictionary(type: String) async {
        if type == "vietphrase" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("VietPhrase.dat"))
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("VietPhrase.txt"))
            self.vietPhraseDict = nil
            await MainActor.run { self.isVietPhraseLoaded = false }
        } else if type == "names" {
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("Names.dat"))
            try? FileManager.default.removeItem(at: translateDirectory.appendingPathComponent("Names.txt"))
            self.namesDict = nil
            await MainActor.run { self.isNamesLoaded = false }
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
            (name: "ChinesePhienAmWords.txt", required: true),
            (name: "Names.dat", required: false),
            (name: "VietPhrase.dat", required: true)
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
                let (tempUrl, _) = try await URLSession.shared.download(from: url)
                let destUrl = translateDirectory.appendingPathComponent(file.name)
                
                if FileManager.default.fileExists(atPath: destUrl.path) {
                    try? FileManager.default.removeItem(at: destUrl)
                }
                try FileManager.default.moveItem(at: tempUrl, to: destUrl)
                successCount += 1
            } catch {
                AppLogger.shared.log("❌ Download error for \(file.name): \(error.localizedDescription)")
                if file.required {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadMessage = "Lỗi khi tải tệp bắt buộc \(file.name): \(error.localizedDescription)"
                    }
                    return
                }
            }
        }
        
        await MainActor.run {
            self.downloadProgress = 1.0
            self.downloadMessage = "Đã tải xong \(successCount)/\(files.count) tệp!"
            self.isDownloading = false
        }
        
        try? await loadAllDictionaries()
    }
}
