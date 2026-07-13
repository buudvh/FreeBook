import Foundation
import ZIPFoundation
import JavaScriptCore
import Combine

// MARK: - Helper Structs for Registry
public struct RegistryResponse: Codable {
    public let metadata: RegistryMetadata?
    public let data: [ExtensionRegistryItem]
}

public struct RegistryMetadata: Codable {
    public let author: String?
    public let description: String?
}

public struct ExtensionRegistryItem: Codable {
    public let name: String
    public let author: String?
    public let path: String // Link tải file plugin.zip
    public let version: Int?
    public let source: String? // URL trang web nguồn (ví dụ: https://truyenfull.vn)
    public let icon: String?
    public let description: String?
    public let type: String? // "novel", "comic", "chinese_novel"
    public let locale: String? // "vi_VN", "zh_CN", ...
}

// MARK: - Helper Structs for JavaScript results
public struct SearchNovelResult: Identifiable {
    public let id = UUID()
    public let name: String
    public let author: String
    public let description: String
    public let cover: String
    public let link: String
    public let host: String
}

public struct NovelDetailResult {
    public let name: String
    public let author: String
    public let cover: String
    public let description: String
    public let detail: String
    public let host: String
    public let link: String
    
    public let genres: [CategoryResult]
    public let suggests: [CategoryResult]
    public let comments: [CategoryResult]
}

public struct ChapterResult {
    public let name: String
    public let url: String
    public let host: String
}

// MARK: - Extension Manager
public final class ExtensionManager: ObservableObject {
    public static let shared = ExtensionManager()
    
    @Published public var loadingStates: [String: Bool] = [:]
    
    private init() {}
    
    private var extensionsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let directory = paths[0].appendingPathComponent("extensions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }
    
    public var commonDirectory: URL {
        let directory = extensionsDirectory.appendingPathComponent("common", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }
    
    // Tải danh sách registry từ một URL kho (plugin.json)
    public func fetchRegistry(from urlString: String) async throws -> [ExtensionRegistryItem] {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ExtensionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Registry URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(RegistryResponse.self, from: data)
        return response.data
    }
    
    // Cài đặt/Cập nhật một extension
    public func install(item: ExtensionRegistryItem, packageId: String) async throws -> String {
        guard let zipUrl = URL(string: item.path) else {
            throw NSError(domain: "ExtensionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid ZIP URL"])
        }
        
        // 1. Tải file ZIP về thư mục tạm
        let (tempZipUrl, _) = try await URLSession.shared.download(from: zipUrl)
        
        // 2. Chuẩn bị thư mục giải nén
        let destFolder = extensionsDirectory.appendingPathComponent(packageId, isDirectory: true)
        
        // Nếu thư mục đã tồn tại, xóa đi để cập nhật mới
        if FileManager.default.fileExists(atPath: destFolder.path) {
            try FileManager.default.removeItem(at: destFolder)
        }
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true, attributes: nil)
        
        // 3. Giải nén ZIPFoundation
        try FileManager.default.unzipItem(at: tempZipUrl, to: destFolder)
        
        // 4. Kiểm tra cấu trúc thư mục sau khi giải nén
        // Một số file zip giải nén ra sẽ chứa thẳng các file js, một số khác nén trong 1 folder con
        // Tìm kiếm tệp plugin.json để xác định thư mục làm việc chính
        let mainFolder = findMainExtensionFolder(at: destFolder)
        
        return mainFolder.path
    }
    
    private func findMainExtensionFolder(at url: URL) -> URL {
        let pluginJsonUrl = url.appendingPathComponent("plugin.json")
        if FileManager.default.fileExists(atPath: pluginJsonUrl.path) {
            return url
        }
        
        // Nếu không thấy, duyệt các thư mục con
        if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let subPluginUrl = item.appendingPathComponent("plugin.json")
                    if FileManager.default.fileExists(atPath: subPluginUrl.path) {
                        return item
                    }
                }
            }
        }
        return url
    }
    
    // Gỡ cài đặt extension
    public func uninstall(localPath: String) {
        let url = URL(fileURLWithPath: localPath)
        try? FileManager.default.removeItem(at: url)
    }
    
    // getScriptPath: Đọc cấu trúc tệp cấu hình plugin.json để xác định đường dẫn thực tế của file script JS cần chạy
    // Hỗ trợ tìm kiếm dự phòng (fallback) cả ở thư mục gốc của extension lẫn thư mục src/
    private func getScriptPath(extensionPath: String, scriptKey: String) throws -> URL {
        let extUrl = URL(fileURLWithPath: extensionPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        
        // Kiểm tra sự tồn tại của file cấu hình plugin.json
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path) else {
            throw NSError(domain: "ExtensionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "plugin.json not found inside extension"])
        }
        
        // Đọc nội dung plugin.json và lấy tên file script tương ứng với scriptKey (ví dụ: search, detail, chap)
        let data = try Data(contentsOf: pluginJsonUrl)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let script = json["script"] as? [String: Any],
              let scriptFileName = script[scriptKey] as? String else {
            throw NSError(domain: "ExtensionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Script key '\(scriptKey)' not defined"])
        }
        
        // Cách 1: Thử tìm trực tiếp ở thư mục gốc của extension
        let scriptUrl = extUrl.appendingPathComponent(scriptFileName)
        if FileManager.default.fileExists(atPath: scriptUrl.path) {
            return scriptUrl
        }
        
        // Cách 2: Tìm dự phòng bên trong thư mục con src/ (cấu trúc phổ biến của VBook Extension)
        let srcScriptUrl = extUrl.appendingPathComponent("src").appendingPathComponent(scriptFileName)
        if FileManager.default.fileExists(atPath: srcScriptUrl.path) {
            return srcScriptUrl
        }
        
        // Trả về lỗi nếu không tìm thấy file script ở cả 2 vị trí trên
        throw NSError(domain: "ExtensionManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Script file '\(scriptFileName)' not found in root or src/"])
    }
    
    // MARK: - Helper Cấu hình
    public func hasConfig(localPath: String) -> Bool {
        guard !localPath.isEmpty else { return false }
        let extUrl = URL(fileURLWithPath: localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path) else { return false }
        
        guard let data = try? Data(contentsOf: pluginJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = json["config"] as? [String: Any] else {
            return false
        }
        return config.values.contains { $0 is [String: Any] }
    }
    
    private func getCombinedConfigs(localPath: String, configJson: String) -> [String: Any] {
        var combined: [String: Any] = [:]
        
        // 1. Đọc default config từ plugin.json trong thư mục localPath
        let extUrl = URL(fileURLWithPath: localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        if let data = try? Data(contentsOf: pluginJsonUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let configSection = json["config"] as? [String: Any] {
            
            for (key, val) in configSection {
                if let configDict = val as? [String: Any] {
                    // Nếu là dạng Object mô tả cấu hình có trường "default"
                    if let defaultValue = configDict["default"] {
                        combined[key] = defaultValue
                    }
                } else {
                    // Nếu là dạng giá trị thô trực tiếp (ví dụ: "thread_num": 1 hoặc "delay": 3000)
                    combined[key] = val
                }
            }
        }
        
        // 2. Đọc user config đã lưu từ configJson và đè lên default config
        if let data = configJson.data(using: .utf8),
           let userDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in userDict {
                combined[key] = value
            }
        }
        
        return combined
    }
    
    // MARK: - Chạy Script JS bóc tách dữ liệu
    
    // search: Gọi script JS tìm kiếm sách từ nguồn truyện.
    // Trả về một mảng chứa thông tin sách tìm kiếm được [SearchNovelResult]
    public func search(localPath: String, downloadUrl: String = "", query: String, page: Int, configJson: String = "{}") async throws -> [SearchNovelResult] {
        // Lấy đường dẫn file script JS tìm kiếm ("search")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "search")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        // Khởi tạo bộ thực thi Javascript (JSExecutor)
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        // Nạp và gộp các cấu hình của extension (mặc định + người dùng tuỳ chỉnh)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs) // Tiêm các hàm global (Html, fetch, Response, Console) vào JSContext
        
        do {
            // Chạy hàm "execute(query, page)" bất đồng bộ bên trong JS Engine
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [query, String(page)])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] search raw JS result: \(stringified)")
            
            // Ép kiểu kết quả trả về của JS thành mảng bằng toDictionaryArray
            let jsArray = toDictionaryArray(cleanVal)
            
            // Duyệt qua mảng kết quả JS để ánh xạ sang cấu trúc dữ liệu SearchNovelResult của Swift
            var results: [SearchNovelResult] = []
            for dict in jsArray {
                let name = dict["name"]?.toString() ?? ""
                let author = dict["author"]?.toString() ?? "Không rõ"
                let description = dict["description"]?.toString() ?? dict["desc"]?.toString() ?? ""
                let cover = dict["cover"]?.toString() ?? ""
                let link = dict["link"]?.toString() ?? dict["url"]?.toString() ?? ""
                let host = dict["host"]?.toString() ?? ""
                
                guard !link.isEmpty else { continue }
                
                results.append(SearchNovelResult(name: name, author: author, description: description, cover: cover, link: link, host: host))
            }
            // AppLogger.shared.log("✅ [ExtensionManager] search parsed \(results.count) results")
            updateDiagnostics(action: "search", input: "query: \(query), page: \(page)", status: "Success", details: "Parsed \(results.count) results:\n\(stringified)")
            return results
        } catch {
            // AppLogger.shared.log("❌ [ExtensionManager] search error: \(error.localizedDescription)")
            updateDiagnostics(action: "search", input: "query: \(query), page: \(page)", status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy thông tin chi tiết truyện
    public func detail(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> NovelDetailResult {
        // AppLogger.shared.log("🔍 [ExtensionManager] detail called. localPath: \(localPath), url: \(url)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "detail")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] detail raw JS result: \(stringified)")
            
            guard let dict = cleanVal.toDictionary() as? [String: Any] else {
                // AppLogger.shared.log("❌ [ExtensionManager] detail returned non-dictionary result or null")
                let errorDesc = "Failed to parse novel detail: result is not dictionary"
                updateDiagnostics(action: "detail", input: url, status: "Error", details: errorDesc)
                throw NSError(domain: "ExtensionManager", code: -6, userInfo: [NSLocalizedDescriptionKey: errorDesc])
            }
            
            let name = dict["name"] as? String ?? ""
            let author = dict["author"] as? String ?? "Không rõ"
            let cover = dict["cover"] as? String ?? ""
            let description = dict["description"] as? String ?? ""
            let detail = dict["detail"] as? String ?? ""
            let host = dict["host"] as? String ?? ""
            let link = dict["link"] as? String ?? dict["url"] as? String ?? url
            
            // No on-the-fly translation during parsing to preserve raw Chinese in memory/DB
            
            // Parse genres
            var genres: [CategoryResult] = []
            if let genresArray = dict["genres"] as? [[String: Any]] {
                for item in genresArray {
                    let gTitle = item["title"] as? String ?? ""
                    let gInput = item["input"] as? String ?? ""
                    let gScript = item["script"] as? String ?? "search.js"
                    if !gTitle.isEmpty && !gInput.isEmpty {
                        genres.append(CategoryResult(title: gTitle, input: gInput, script: gScript))
                    }
                }
            } else if let genresDict = dict["genres"] as? [String: String] {
                for (key, val) in genresDict {
                    genres.append(CategoryResult(title: key, input: val, script: "search.js"))
                }
            }
            
            // Parse suggests
            var suggests: [CategoryResult] = []
            if let suggestsArray = dict["suggests"] as? [[String: Any]] {
                for item in suggestsArray {
                    let sTitle = item["title"] as? String ?? ""
                    let sInput = item["input"] as? String ?? ""
                    let sScript = item["script"] as? String ?? "search.js"
                    if !sTitle.isEmpty && !sInput.isEmpty {
                        suggests.append(CategoryResult(title: sTitle, input: sInput, script: sScript))
                    }
                }
            }
            
            // Parse comments
            var comments: [CategoryResult] = []
            if let commentsArray = dict["comments"] as? [[String: Any]] {
                for item in commentsArray {
                    let cTitle = item["title"] as? String ?? ""
                    let cInput = item["input"] as? String ?? ""
                    let cScript = item["script"] as? String ?? "comment.js"
                    if !cTitle.isEmpty && !cInput.isEmpty {
                        comments.append(CategoryResult(title: cTitle, input: cInput, script: cScript))
                    }
                }
            }
            
            let result = NovelDetailResult(name: name, author: author, cover: cover, description: description, detail: detail, host: host, link: link, genres: genres, suggests: suggests, comments: comments)
            // AppLogger.shared.log("✅ [ExtensionManager] detail parsed info: \(result.name) by \(result.author)")
            updateDiagnostics(action: "detail", input: url, status: "Success", details: "Name: \(result.name), Author: \(result.author)\n\(stringified)")
            return result
        } catch {
            // AppLogger.shared.log("❌ [ExtensionManager] detail error: \(error.localizedDescription)")
            updateDiagnostics(action: "detail", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy mục lục chương
    public func toc(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> [ChapterResult] {
        // AppLogger.shared.log("🔍 [ExtensionManager] toc called. localPath: \(localPath), url: \(url)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "toc")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] toc raw JS result: \(stringified)")
            
            let jsArray = toDictionaryArray(cleanVal)

            var results: [ChapterResult] = []
 
            for dict in jsArray {
                let name = dict["name"]?.toString() ?? ""
                let url = dict["url"]?.toString()
                    ?? dict["link"]?.toString()
                    ?? ""
                let host = dict["host"]?.toString() ?? ""
 
                // No on-the-fly translation during parsing to preserve raw Chinese in memory/DB
 
                results.append(
                    ChapterResult(
                        name: name,
                        url: url,
                        host: host
                    )
                )
            }

            // AppLogger.shared.log("✅ [ExtensionManager] toc parsed \(results.count) chapters")
            updateDiagnostics(action: "toc", input: url, status: "Success", details: "Parsed \(results.count) chapters:\n\(stringified)")
            return results
        } catch {
            // AppLogger.shared.log("❌ [ExtensionManager] toc error: \(error.localizedDescription)")
            updateDiagnostics(action: "toc", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }

    private func toDictionaryArray(_ value: JSValue) -> [[String: JSValue]] {
        guard let context = value.context,
            let objectKeys = context.objectForKeyedSubscript("Object")
                                    .objectForKeyedSubscript("keys") else {
            return []
        }

        let length = Int(value.forProperty("length").toInt32())
        var result: [[String: JSValue]] = []
        result.reserveCapacity(length)

        for i in 0..<length {
            guard let item = value.atIndex(i) else { continue }

            var dict: [String: JSValue] = [:]

            guard let keys = objectKeys.call(withArguments: [item]) else {
                continue
            }

            let keyCount = Int(keys.forProperty("length").toInt32())

            for j in 0..<keyCount {
                guard let key = keys.atIndex(j)?.toString() else { continue }
                dict[key] = item.forProperty(key)
            }

            result.append(dict)
        }

        return result
    }
    
    // Lấy nội dung chương (có thể là Text hoặc danh sách URL ảnh cho truyện tranh)
    public func chap(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> String {
        // AppLogger.shared.log("🔍 [ExtensionManager] chap called. localPath: \(localPath), url: \(url)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "chap")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] chap raw JS result length: \(stringified.count)")
            
            var resultStr = ""
            if cleanVal.isArray {
                if let array = cleanVal.toArray() as? [String] {
                    resultStr = array.joined(separator: "\n")
                }
            } else {
                resultStr = cleanVal.toString() ?? ""
            }
            
            updateDiagnostics(action: "chap", input: url, status: "Success", details: "Length: \(resultStr.count) characters\n\(stringified)")
            return resultStr
        } catch {
            // AppLogger.shared.log("❌ [ExtensionManager] chap error: \(error.localizedDescription)")
            updateDiagnostics(action: "chap", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy danh mục thể loại (Khám phá)
    public func genre(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [CategoryResult] {
        // AppLogger.shared.log("🔍 [ExtensionManager] genre called. localPath: \(localPath)")
        
        let translateTitle: (String) -> String = { title in
            return title
        }
        
        do {
            let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "genre")
            let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
            
            let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
            let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
            executor.injectGlobals(configs)
            
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] genre raw JS result: \(stringified)")
            
            var results: [CategoryResult] = []
            
            if let jsArray = cleanVal.toArray() {
                for item in jsArray {
                    if let itemDict = item as? [String: Any] {
                        if let title = itemDict["title"] as? String,
                           let input = itemDict["input"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: translateTitle(title), input: input, script: script))
                        } else if let title = itemDict["name"] as? String,
                                  let input = itemDict["link"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: translateTitle(title), input: input, script: script))
                        }
                    }
                }
            } else if let dict = cleanVal.toDictionary() as? [String: String] {
                for (key, val) in dict {
                    results.append(CategoryResult(title: translateTitle(key), input: val, script: "search.js"))
                }
            } else if let dict = cleanVal.toDictionary() as? [String: Any] {
                for (key, val) in dict {
                    if let valStr = val as? String {
                        results.append(CategoryResult(title: translateTitle(key), input: valStr, script: "search.js"))
                    }
                }
            }
            
            // AppLogger.shared.log("✅ [ExtensionManager] genre parsed \(results.count) categories")
            updateDiagnostics(action: "genre", input: "localPath: \(localPath)", status: "Success", details: "Parsed \(results.count) categories:\n\(stringified)")
            return results
        } catch {
            // AppLogger.shared.log("❌ [ExtensionManager] genre script failed or not supported: \(error.localizedDescription)")
            updateDiagnostics(action: "genre", input: "localPath: \(localPath)", status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy danh sách tab trang chủ (Home)
    public func home(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [CategoryResult] {
        // AppLogger.shared.log("🔍 [ExtensionManager] home called. localPath: \(localPath)")
        
        let translateTitle: (String) -> String = { title in
            return title
        }
        
        do {
            let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "home")
            let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
            
            let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
            let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
            executor.injectGlobals(configs)
            
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] home raw JS result: \(stringified)")
            
            var results: [CategoryResult] = []
            
            if let jsArray = cleanVal.toArray() {
                for item in jsArray {
                    if let itemDict = item as? [String: Any] {
                        if let title = itemDict["title"] as? String,
                           let input = itemDict["input"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: translateTitle(title), input: input, script: script))
                        } else if let title = itemDict["name"] as? String,
                                  let input = itemDict["link"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: translateTitle(title), input: input, script: script))
                        }
                    }
                }
            }
            
            // AppLogger.shared.log("✅ [ExtensionManager] home parsed \(results.count) tabs")
            if !results.isEmpty {
                updateDiagnostics(action: "home", input: "localPath: \(localPath)", status: "Success", details: "Parsed \(results.count) tabs:\n\(stringified)")
                return results
            }
        } catch {
            // AppLogger.shared.log("⚠️ [ExtensionManager] home script failed or missing, trying fallback to genre...")
        }
        
        // Fallback to genre
        return try await genre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
    }
    
    // Thực thi một script tùy chọn (ví dụ: gen.js, tag.js...) với input và page
    public func executeCustomScript(localPath: String, downloadUrl: String = "", scriptFileName: String, input: String, page: Int, pageUrl: String?, configJson: String = "{}") async throws -> (results: [SearchNovelResult], nextPage: String?) {
        // AppLogger.shared.log("🔍 [ExtensionManager] executeCustomScript called. localPath: \(localPath), scriptFileName: \(scriptFileName), input: \(input), page: \(page), pageUrl: \(pageUrl ?? "nil")")
        
        let extUrl = URL(fileURLWithPath: localPath)
        // Tìm file script trong thư mục gốc hoặc src/
        var scriptUrl = extUrl.appendingPathComponent(scriptFileName)
        if !FileManager.default.fileExists(atPath: scriptUrl.path) {
            let srcScriptUrl = extUrl.appendingPathComponent("src").appendingPathComponent(scriptFileName)
            if FileManager.default.fileExists(atPath: srcScriptUrl.path) {
                scriptUrl = srcScriptUrl
            } else {
                let errorDesc = "Script file '\(scriptFileName)' not found in root or src/"
                updateDiagnostics(action: scriptFileName, input: "input: \(input), page: \(page)", status: "Error", details: errorDesc)
                throw NSError(domain: "ExtensionManager", code: -5, userInfo: [NSLocalizedDescriptionKey: errorDesc])
            }
        }
        
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        // VBook formatting: thay thế {0} trong input bằng số trang hiện tại
        let formattedInput = input.replacingOccurrences(of: "{0}", with: String(page))
        // AppLogger.shared.log("📝 [ExtensionManager] formattedInput: \(formattedInput)")
        
        let pageArg = (page == 1) ? "" : (pageUrl ?? "")
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [formattedInput, pageArg])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            // AppLogger.shared.log("📝 [ExtensionManager] custom script raw JS result: \(stringified)")
            // Ép kiểu kết quả trả về của JS thành mảng bằng toDictionaryArray
            let jsArray = toDictionaryArray(cleanVal)
            
            var results: [SearchNovelResult] = []
            for dict in jsArray {
                var name = dict["name"]?.toString() ?? dict["username"]?.toString() ?? dict["author"]?.toString() ?? ""
                var author = dict["author"]?.toString() ?? "Không rõ"
                var description = dict["description"]?.toString() ?? dict["desc"]?.toString() ?? dict["content"]?.toString() ?? ""
                let cover = dict["cover"]?.toString() ?? ""
                let link = dict["link"]?.toString() ?? dict["url"]?.toString() ?? ""
                let host = dict["host"]?.toString() ?? ""
                
                let isCommentScript = scriptFileName.localizedCaseInsensitiveContains("comment")
                if !isCommentScript {
                    guard !link.isEmpty else { continue }
                }
                
                if TranslateUtils.isTranslationEnabled {
                    if TranslateUtils.containsChinese(name) { name = TranslateUtils.translateMeta(name) }
                    if TranslateUtils.containsChinese(author) { author = TranslateUtils.translateMeta(author) }
                    if TranslateUtils.containsChinese(description) { description = TranslateUtils.translateMeta(description) }
                }
                
                results.append(SearchNovelResult(name: name, author: author, description: description, cover: cover, link: link, host: host))
            }
            
            var nextPageVal: String? = nil
            if let responseObj = executor.context.objectForKeyedSubscript("Response"),
               let nextVal = responseObj.objectForKeyedSubscript("nextPage"),
               !nextVal.isUndefined && !nextVal.isNull {
                nextPageVal = nextVal.toString()
            }
            
            // AppLogger.shared.log("✅ [ExtensionManager] custom script parsed \(results.count) results, nextPage: \(nextPageVal ?? "nil")")
            updateDiagnostics(action: scriptFileName, input: "input: \(input), page: \(page)", status: "Success", details: "Parsed \(results.count) results, nextPage: \(nextPageVal ?? "nil")\n\(stringified)")
            return (results, nextPageVal)
        } catch {
            // AppLogger.shared.log("❌ [ExtensionManager] custom script error: \(error.localizedDescription)")
            updateDiagnostics(action: scriptFileName, input: "input: \(input), page: \(page)", status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    public func hasScript(localPath: String, scriptKey: String) -> Bool {
        let extUrl = URL(fileURLWithPath: localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        guard let data = try? Data(contentsOf: pluginJsonUrl),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let script = json["script"] as? [String: String] else {
            return false
        }
        return script[scriptKey] != nil
    }
    
    public func page(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> [String] {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "page")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let cleanVal = try verifyJSResponse(jsValue)
            let stringified = stringify(cleanVal)
            
            var results: [String] = []
            if cleanVal.isArray {
                let length = Int(cleanVal.forProperty("length").toInt32())
                for i in 0..<length {
                    if let itemVal = cleanVal.atIndex(i), !itemVal.isUndefined && !itemVal.isNull {
                        results.append(itemVal.toString() ?? "")
                    }
                }
            } else if !cleanVal.isUndefined && !cleanVal.isNull {
                if let str = cleanVal.toString() {
                    results = [str]
                }
            }
            
            updateDiagnostics(action: "page", input: url, status: "Success", details: "Parsed \(results.count) pages:\n\(stringified)")
            return results
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] page script error: \(error.localizedDescription)")
            updateDiagnostics(action: "page", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy danh sách giọng đọc từ extension TTS
    public func ttsVoices(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [[String: String]] {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "voice")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [])
            let cleanVal = try verifyJSResponse(jsValue)
            var results: [[String: String]] = []
            
            if let jsArray = cleanVal.toArray() {
                for item in jsArray {
                    if let dict = item as? [String: Any] {
                        var voiceDict: [String: String] = [:]
                        for (key, val) in dict {
                            voiceDict[key] = String(describing: val)
                        }
                        results.append(voiceDict)
                    }
                }
            }
            
            updateDiagnostics(action: "voice", input: "", status: "Success", details: "Found \(results.count) voices")
            return results
        } catch {
            updateDiagnostics(action: "voice", input: "", status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Tạo âm thanh TTS từ extension
    public func ttsGenerate(localPath: String, downloadUrl: String = "", text: String, voice: String, configJson: String = "{}") async throws -> String {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "tts")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [text, voice])
            let cleanVal = try verifyJSResponse(jsValue)
            let resultStr = cleanVal.toString() ?? ""
            updateDiagnostics(action: "tts", input: text, status: "Success", details: "Base64 string length: \(resultStr.count)")
            return resultStr
        } catch {
            updateDiagnostics(action: "tts", input: text, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    private func verifyJSResponse(_ jsValue: JSValue) throws -> JSValue {
        guard jsValue.isObject else { return jsValue }
        
        if let successVal = jsValue.objectForKeyedSubscript("success"),
           !successVal.isUndefined,
           !successVal.isNull {
            let success = successVal.toBool()
            if !success {
                let msgVal = jsValue.objectForKeyedSubscript("message")
                let msg = (msgVal != nil && !msgVal!.isUndefined && !msgVal!.isNull) ? msgVal!.toString() ?? "Lỗi từ nguồn truyện" : "Lỗi từ nguồn truyện"
                AppLogger.shared.log("❌ [ExtensionManager] Response.error: \(msg)")
                throw NSError(domain: "ExtensionManager", code: -999, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            if let dataVal = jsValue.objectForKeyedSubscript("data"),
               !dataVal.isUndefined {
                let dataStr = stringify(dataVal)
                AppLogger.shared.log("✅ [ExtensionManager] Response.success: \(dataStr)")
                return dataVal
            }
        }
        return jsValue
    }

    private func stringify(_ jsValue: JSValue) -> String {
        if let jsonModule = jsValue.context.objectForKeyedSubscript("JSON"),
           let stringifyFunc = jsonModule.objectForKeyedSubscript("stringify"),
           let result = stringifyFunc.call(withArguments: [jsValue]) {
            return result.toString() ?? ""
        }
        return jsValue.toString() ?? ""
    }
    
    private func updateDiagnostics(action: String, input: String, status: String, details: String) {
        Task { @MainActor in
            AppDiagnostics.shared.lastCall = AppDiagnostics.CallInfo(
                action: action,
                input: input,
                status: status,
                details: details
            )
        }
    }
}

// Model danh mục / Home Tab
public struct CategoryResult: Identifiable, Codable {
    public var id: String { title + "_" + input }
    public let title: String
    public let input: String
    public let script: String
}
