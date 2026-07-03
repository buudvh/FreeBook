import Foundation
import ZIPFoundation
import JavaScriptCore

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
}

public struct ChapterResult {
    public let name: String
    public let url: String
    public let host: String
}

// MARK: - Extension Manager
public final class ExtensionManager {
    public static let shared = ExtensionManager()
    
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
    
    // Đọc cấu trúc plugin.json nội bộ để lấy đường dẫn file script JS
    private func getScriptPath(extensionPath: String, scriptKey: String) throws -> URL {
        let extUrl = URL(fileURLWithPath: extensionPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        
        guard FileManager.default.fileExists(atPath: pluginJsonUrl.path) else {
            throw NSError(domain: "ExtensionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "plugin.json not found inside extension"])
        }
        
        let data = try Data(contentsOf: pluginJsonUrl)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let script = json["script"] as? [String: String],
              let scriptFileName = script[scriptKey] else {
            throw NSError(domain: "ExtensionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Script key '\(scriptKey)' not defined"])
        }
        
        // 1. Thử đường dẫn gốc
        let scriptUrl = extUrl.appendingPathComponent(scriptFileName)
        if FileManager.default.fileExists(atPath: scriptUrl.path) {
            return scriptUrl
        }
        
        // 2. Thử đường dẫn trong thư mục src/
        let srcScriptUrl = extUrl.appendingPathComponent("src").appendingPathComponent(scriptFileName)
        if FileManager.default.fileExists(atPath: srcScriptUrl.path) {
            return srcScriptUrl
        }
        
        // Không tìm thấy ở cả hai nơi
        throw NSError(domain: "ExtensionManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Script file '\(scriptFileName)' not found in root or src/"])
    }
    
    // MARK: - Helper Cấu hình
    private func getCombinedConfigs(localPath: String, configJson: String) -> [String: Any] {
        var combined: [String: Any] = [:]
        
        // 1. Đọc default config từ plugin.json trong thư mục localPath
        let extUrl = URL(fileURLWithPath: localPath)
        let pluginJsonUrl = extUrl.appendingPathComponent("plugin.json")
        if let data = try? Data(contentsOf: pluginJsonUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let configSection = json["config"] as? [String: [String: Any]] {
            
            for (key, configItem) in configSection {
                if let defaultValue = configItem["default"] {
                    combined[key] = defaultValue
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
    
    // Tìm kiếm truyện
    public func search(localPath: String, downloadUrl: String = "", query: String, page: Int, configJson: String = "{}") async throws -> [SearchNovelResult] {
        AppLogger.shared.log("🔍 [ExtensionManager] search called. localPath: \(localPath), query: \(query), page: \(page)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "search")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [query, String(page)])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] search raw JS result: \(stringified)")
            
            guard let jsArray = jsValue.toArray() else {
                AppLogger.shared.log("⚠️ [ExtensionManager] search returned non-array result or null")
                updateDiagnostics(action: "search", input: "query: \(query), page: \(page)", status: "Success (Empty)", details: "Returned non-array result")
                return []
            }
            
            var results: [SearchNovelResult] = []
            for item in jsArray {
                if let dict = item as? [String: Any] {
                    let name = dict["name"] as? String ?? ""
                    let author = dict["author"] as? String ?? "Không rõ"
                    let description = dict["description"] as? String ?? dict["desc"] as? String ?? ""
                    let cover = dict["cover"] as? String ?? ""
                    let link = dict["link"] as? String ?? dict["url"] as? String ?? ""
                    let host = dict["host"] as? String ?? ""
                    
                    results.append(SearchNovelResult(name: name, author: author, description: description, cover: cover, link: link, host: host))
                }
            }
            AppLogger.shared.log("✅ [ExtensionManager] search parsed \(results.count) results")
            updateDiagnostics(action: "search", input: "query: \(query), page: \(page)", status: "Success", details: "Parsed \(results.count) results:\n\(stringified)")
            return results
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] search error: \(error.localizedDescription)")
            updateDiagnostics(action: "search", input: "query: \(query), page: \(page)", status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy thông tin chi tiết truyện
    public func detail(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> NovelDetailResult {
        AppLogger.shared.log("🔍 [ExtensionManager] detail called. localPath: \(localPath), url: \(url)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "detail")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] detail raw JS result: \(stringified)")
            
            guard let dict = jsValue.toDictionary() as? [String: Any] else {
                AppLogger.shared.log("❌ [ExtensionManager] detail returned non-dictionary result or null")
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
            
            let result = NovelDetailResult(name: name, author: author, cover: cover, description: description, detail: detail, host: host, link: link)
            AppLogger.shared.log("✅ [ExtensionManager] detail parsed info: \(result.name) by \(result.author)")
            updateDiagnostics(action: "detail", input: url, status: "Success", details: "Name: \(result.name), Author: \(result.author)\n\(stringified)")
            return result
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] detail error: \(error.localizedDescription)")
            updateDiagnostics(action: "detail", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy mục lục chương
    public func toc(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> [ChapterResult] {
        AppLogger.shared.log("🔍 [ExtensionManager] toc called. localPath: \(localPath), url: \(url)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "toc")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] toc raw JS result: \(stringified)")
            
            guard let jsArray = jsValue.toArray() else {
                AppLogger.shared.log("⚠️ [ExtensionManager] toc returned non-array result or null")
                updateDiagnostics(action: "toc", input: url, status: "Success (Empty)", details: "Returned non-array result")
                return []
            }

            AppLogger.shared.log("📝 [ExtensionManager] Swift array count = \(jsArray.count)")

            var results: [ChapterResult] = []

            for (index, item) in jsArray.enumerated() {

                AppLogger.shared.log("========== Item \(index) ==========")
                AppLogger.shared.log("Type: \(type(of: item))")
                AppLogger.shared.log("Value: \(item)")

                guard let dict = item as? [String: Any] else {
                    AppLogger.shared.log("❌ Item is not Dictionary")
                    continue
                }

                AppLogger.shared.log("Keys: \(Array(dict.keys))")

                if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                let json = String(data: data, encoding: .utf8) {
                    AppLogger.shared.log("Dictionary:\n\(json)")
                }

                let name = dict["name"] as? String ?? ""
                let urlVal = dict["url"] as? String ?? dict["link"] as? String ?? ""
                let host = dict["host"] as? String ?? ""

                AppLogger.shared.log("""
                Parsed:
                name = [\(name)]
                url  = [\(urlVal)]
                host = [\(host)]
                """)

                results.append(ChapterResult(
                    name: name,
                    url: urlVal,
                    host: host
                ))
            }

            AppLogger.shared.log("✅ [ExtensionManager] toc parsed \(results.count) chapters")

            updateDiagnostics(
                action: "toc",
                input: url,
                status: "Success",
                details: "Parsed \(results.count) chapters:\n\(stringified)"
            )

            return results
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] toc error: \(error.localizedDescription)")
            updateDiagnostics(action: "toc", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy nội dung chương (có thể là Text hoặc danh sách URL ảnh cho truyện tranh)
    public func chap(localPath: String, downloadUrl: String = "", url: String, configJson: String = "{}") async throws -> String {
        AppLogger.shared.log("🔍 [ExtensionManager] chap called. localPath: \(localPath), url: \(url)")
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "chap")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [url])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] chap raw JS result length: \(stringified.count)")
            
            var resultStr = ""
            if jsValue.isArray {
                if let array = jsValue.toArray() as? [String] {
                    resultStr = array.joined(separator: "\n")
                }
            } else {
                resultStr = jsValue.toString() ?? ""
            }
            updateDiagnostics(action: "chap", input: url, status: "Success", details: "Length: \(resultStr.count) characters\n\(stringified)")
            return resultStr
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] chap error: \(error.localizedDescription)")
            updateDiagnostics(action: "chap", input: url, status: "Error", details: error.localizedDescription)
            throw error
        }
    }
    
    // Lấy danh mục thể loại (Khám phá)
    public func genre(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [CategoryResult] {
        AppLogger.shared.log("🔍 [ExtensionManager] genre called. localPath: \(localPath)")
        do {
            let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "genre")
            let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
            
            let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
            let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
            executor.injectGlobals(configs)
            
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] genre raw JS result: \(stringified)")
            
            var results: [CategoryResult] = []
            
            if let jsArray = jsValue.toArray() {
                for item in jsArray {
                    if let itemDict = item as? [String: Any] {
                        if let title = itemDict["title"] as? String,
                           let input = itemDict["input"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: title, input: input, script: script))
                        } else if let title = itemDict["name"] as? String,
                                  let input = itemDict["link"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: title, input: input, script: script))
                        }
                    }
                }
            } else if let dict = jsValue.toDictionary() as? [String: String] {
                for (key, val) in dict {
                    results.append(CategoryResult(title: key, input: val, script: "search.js"))
                }
            } else if let dict = jsValue.toDictionary() as? [String: Any] {
                for (key, val) in dict {
                    if let valStr = val as? String {
                        results.append(CategoryResult(title: key, input: valStr, script: "search.js"))
                    }
                }
            }
            
            AppLogger.shared.log("✅ [ExtensionManager] genre parsed \(results.count) categories")
            updateDiagnostics(action: "genre", input: "localPath: \(localPath)", status: "Success", details: "Parsed \(results.count) categories:\n\(stringified)")
            return results
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] genre script failed or not supported: \(error.localizedDescription)")
            updateDiagnostics(action: "genre", input: "localPath: \(localPath)", status: "Error", details: error.localizedDescription)
            return []
        }
    }
    
    // Lấy danh sách tab trang chủ (Home)
    public func home(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [CategoryResult] {
        AppLogger.shared.log("🔍 [ExtensionManager] home called. localPath: \(localPath)")
        do {
            let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "home")
            let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
            
            let executor = JSExecutor(localPath: localPath, downloadUrl: downloadUrl)
            let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
            executor.injectGlobals(configs)
            
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] home raw JS result: \(stringified)")
            
            var results: [CategoryResult] = []
            
            if let jsArray = jsValue.toArray() {
                for item in jsArray {
                    if let itemDict = item as? [String: Any] {
                        if let title = itemDict["title"] as? String,
                           let input = itemDict["input"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: title, input: input, script: script))
                        } else if let title = itemDict["name"] as? String,
                                  let input = itemDict["link"] as? String {
                            let script = itemDict["script"] as? String ?? "search.js"
                            results.append(CategoryResult(title: title, input: input, script: script))
                        }
                    }
                }
            }
            
            AppLogger.shared.log("✅ [ExtensionManager] home parsed \(results.count) tabs")
            if !results.isEmpty {
                updateDiagnostics(action: "home", input: "localPath: \(localPath)", status: "Success", details: "Parsed \(results.count) tabs:\n\(stringified)")
                return results
            }
        } catch {
            AppLogger.shared.log("⚠️ [ExtensionManager] home script failed or missing, trying fallback to genre...")
        }
        
        // Fallback to genre
        return try await genre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
    }
    
    // Thực thi một script tùy chọn (ví dụ: gen.js, tag.js...) với input và page
    public func executeCustomScript(localPath: String, downloadUrl: String = "", scriptFileName: String, input: String, page: Int, pageUrl: String?, configJson: String = "{}") async throws -> (results: [SearchNovelResult], nextPage: String?) {
        AppLogger.shared.log("🔍 [ExtensionManager] executeCustomScript called. localPath: \(localPath), scriptFileName: \(scriptFileName), input: \(input), page: \(page), pageUrl: \(pageUrl ?? "nil")")
        
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
        AppLogger.shared.log("📝 [ExtensionManager] formattedInput: \(formattedInput)")
        
        let pageArg = (page == 1) ? "" : (pageUrl ?? "")
        
        do {
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "execute", arguments: [formattedInput, pageArg])
            let stringified = stringify(jsValue)
            AppLogger.shared.log("📝 [ExtensionManager] custom script raw JS result: \(stringified)")
            
            guard let jsArray = jsValue.toArray() else {
                AppLogger.shared.log("⚠️ [ExtensionManager] custom script returned non-array result or null")
                updateDiagnostics(action: scriptFileName, input: "input: \(input), page: \(page)", status: "Success (Empty)", details: "Returned non-array result")
                return ([], nil)
            }
            
            var results: [SearchNovelResult] = []
            for item in jsArray {
                if let dict = item as? [String: Any] {
                    let name = dict["name"] as? String ?? ""
                    let author = dict["author"] as? String ?? "Không rõ"
                    let description = dict["description"] as? String ?? dict["desc"] as? String ?? ""
                    let cover = dict["cover"] as? String ?? ""
                    let link = dict["link"] as? String ?? dict["url"] as? String ?? ""
                    let host = dict["host"] as? String ?? ""
                    
                    results.append(SearchNovelResult(name: name, author: author, description: description, cover: cover, link: link, host: host))
                }
            }
            
            var nextPageVal: String? = nil
            if let responseObj = executor.context.objectForKeyedSubscript("Response"),
               let nextVal = responseObj.objectForKeyedSubscript("nextPage"),
               !nextVal.isUndefined && !nextVal.isNull {
                nextPageVal = nextVal.toString()
            }
            
            AppLogger.shared.log("✅ [ExtensionManager] custom script parsed \(results.count) results, nextPage: \(nextPageVal ?? "nil")")
            updateDiagnostics(action: scriptFileName, input: "input: \(input), page: \(page)", status: "Success", details: "Parsed \(results.count) results, nextPage: \(nextPageVal ?? "nil")\n\(stringified)")
            return (results, nextPageVal)
        } catch {
            AppLogger.shared.log("❌ [ExtensionManager] custom script error: \(error.localizedDescription)")
            updateDiagnostics(action: scriptFileName, input: "input: \(input), page: \(page)", status: "Error", details: error.localizedDescription)
            throw error
        }
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
