import Foundation
import CryptoKit

/// Tệp và đệm tệp của nguồn (spec §13.7, §14.2): `java.downloadFile`, `cacheFile`, `importScript`, `getZip*Content`.
/// Tải luôn qua client của phiên (kho cookie, header nguồn, `concurrentRate`).
extension LegadoEngineSession {
    var sourceFiles: LegadoSourceFiles {
        LegadoSourceFiles(sourceKey: source.key)
    }

    /// `java.md5Encode16`: ký tự 8…23 của MD5 hex thường.
    static func md5Hex16(_ text: String) -> String {
        let full = Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        let start = full.index(full.startIndex, offsetBy: 8)
        return String(full[start..<full.index(start, offsetBy: 16)])
    }

    /// `java.downloadFile(url)`: tên = `md5Encode16(url)` + đuôi (từ path URL, không có thì từ `Content-Type`); ghi đè;
    /// trả **đường dẫn tương đối**; lỗi/quá 50 MB ⇒ `""`.
    func jsDownloadFile(_ url: String) throws -> String {
        do {
            let request = try buildRequest(url, baseUrl: currentFrameBaseUrl)
            let response = try perform(request, allowHTTPError: true)
            guard response.statusCode < 400 else {
                diagnostics.record(.http, "java.downloadFile HTTP \(response.statusCode)")
                return ""
            }
            guard response.data.count <= LegadoSourceFiles.maxDownloadBytes else {
                diagnostics.record(.network, "java.downloadFile: tệp vượt 50 MB")
                return ""
            }
            let name = Self.md5Hex16(url) + Self.fileExtension(url: request.url, contentType: response.header("Content-Type"))
            return try sourceFiles.write(response.data, to: name)
        } catch {
            if error is CancellationError || cancellation.isCancelled { throw CancellationError() }
            diagnostics.record(.network, "java.downloadFile \(url.prefix(160)): \(error.localizedDescription)")
            return ""
        }
    }

    /// `java.cacheFile(url[, saveTime])`: như `cache.getFile(md5Encode16(url))`, chưa có thì tải và lưu bằng
    /// `cache.putFile(…, saveTime)` (giây; ≤ 0/không có ⇒ không hết hạn). Lỗi ⇒ `""`.
    func jsCacheFile(_ url: String, saveTime: Double?) throws -> String {
        let key = Self.md5Hex16(url)
        if let cached = store.cacheValue(forKey: key, sourceKey: source.key) { return cached }
        guard let response = try jsConnect(url, headers: nil), response.statusCode < 400, !response.body.isEmpty else {
            diagnostics.record(.network, "java.cacheFile: không tải được \(url.prefix(160))")
            return ""
        }
        let ttl = saveTime.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
        store.setCacheValue(response.body, forKey: key, sourceKey: source.key, ttl: ttl)
        return response.body
    }

    /// `java.importScript(pathOrUrl)` (§13.7): **trả mã**, không tự chạy. `http(s)` ⇒ như `cacheFile`; đường dẫn ⇒ tệp
    /// UTF-8 trong thư mục của nguồn. Lỗi ⇒ `""`.
    func jsImportScript(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if LegadoURLResolver.hasHTTPScheme(trimmed) { return try jsCacheFile(trimmed, saveTime: nil) }
        let text = sourceFiles.readText(trimmed, charset: nil)
        if text.isEmpty { diagnostics.record(.info, "java.importScript: không đọc được \(trimmed.prefix(160))") }
        return text
    }

    /// `java.getZip{String,ByteArray}Content(url, path)`: tải zip (đệm theo URL) hoặc dùng tệp tương đối có sẵn, giải nén
    /// một lần, đọc mục `path`. Không có ⇒ `nil`.
    func zipEntryData(url: String, entry: String) throws -> Data? {
        let files = sourceFiles
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var archive = trimmed
        if LegadoURLResolver.hasHTTPScheme(trimmed) || LegadoDataURL.isDataURL(trimmed) {
            archive = "zip/" + Self.md5Hex16(trimmed) + ".zip"
            if !files.exists(archive) {
                let request = try buildRequest(trimmed, baseUrl: currentFrameBaseUrl)
                let response = try perform(request)
                guard response.data.count <= LegadoSourceFiles.maxDownloadBytes else {
                    throw LegadoJSNativeError("Tệp nén vượt 50 MB")
                }
                _ = try files.write(response.data, to: archive)
            }
        }
        var folder = archive + "_unzip"
        if !files.exists(folder) {
            folder = try files.unzip(archive)
        }
        return files.readEntry(entry, inFolder: folder)
    }

    /// Đuôi tệp: từ path URL (1–5 chữ/số), không có thì theo `Content-Type`; không đoán được ⇒ `""`.
    static func fileExtension(url: String, contentType: String?) -> String {
        let path = LegadoURLResolver.splitOption(url).url.components(separatedBy: "?").first ?? ""
        let last = path.components(separatedBy: "/").last ?? ""
        if let dot = last.lastIndex(of: ".") {
            let ext = String(last[last.index(after: dot)...])
            if (1...5).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                return "." + ext.lowercased()
            }
        }
        let type = (contentType ?? "").lowercased()
        let table: [(String, String)] = [
            ("png", ".png"), ("jpeg", ".jpg"), ("jpg", ".jpg"), ("gif", ".gif"), ("webp", ".webp"), ("x-icon", ".ico"),
            ("json", ".json"), ("html", ".html"), ("javascript", ".js"), ("zip", ".zip"), ("text/plain", ".txt"),
            ("font", ".ttf"), ("ttf", ".ttf"), ("otf", ".otf")
        ]
        return table.first { type.contains($0.0) }?.1 ?? ""
    }
}
