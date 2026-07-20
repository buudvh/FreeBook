import Foundation

public actor BookBinManager {
    public static let shared = BookBinManager()
    
    private let fileManager = FileManager.default
    
    private var booksDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("books", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    private init() {}
    
    public func binFilePath(for bookId: String) -> URL {
        return booksDirectory.appendingPathComponent("\(bookId).bin")
    }
    
    public func readChapterContent(bookId: String, offset: Int64, length: Int64) throws -> String {
        guard length > 0 else { return "" }
        let fileURL = binFilePath(for: bookId)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "BookBinManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "File .bin không tồn tại cho sách \(bookId)"])
        }
        
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        try fileHandle.seek(toOffset: UInt64(offset))
        guard let data = try fileHandle.read(upToCount: Int(length)) else {
            throw NSError(domain: "BookBinManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Không thể đọc dữ liệu tại offset \(offset)"])
        }
        
        if let content = String(data: data, encoding: .utf8) {
            return content
        }
        throw NSError(domain: "BookBinManager", code: 501, userInfo: [NSLocalizedDescriptionKey: "Lỗi giải mã UTF-8 cho chương truyện"])
    }
    
    public func writeChapterContent(bookId: String, content: String) throws -> (offset: Int64, length: Int64) {
        let fileURL = binFilePath(for: bookId)
        let data = Data(content.utf8)
        let length = Int64(data.count)
        
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
        
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }
        
        try fileHandle.seekToEnd()
        let offset = Int64(try fileHandle.offset())
        try fileHandle.write(contentsOf: data)
        
        return (offset: offset, length: length)
    }
    
    public func deleteBinFile(for bookId: String) {
        let fileURL = binFilePath(for: bookId)
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
