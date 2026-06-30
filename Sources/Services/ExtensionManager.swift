import Foundation
import ZIPFoundation
import JavaScriptCore
import SwiftData

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
    public let author: String
    public let path: String // Link tải file plugin.zip
    public let version: Int
    public let source: String // URL trang web nguồn (ví dụ: https://truyenfull.vn)
    public let icon: String?
    public let description: String?
    public let type: String // "novel", "comic", "chinese_novel"
    public let locale: String // "vi_VN", "zh_CN", ...
}

// MARK: - Helper Structs for JavaScript results
public struct SearchNovelResult: Identifiable {
    public let id = UUID()
    public let title: String
    public let author: String
    public let coverUrl: String
    public let detailUrl: String
}

public struct NovelDetailResult {
    public let title: String
    public let author: String
    public let coverUrl: String
    public let desc: String
    public let detailUrl: String
}

public struct ChapterResult {
    public let title: String
    public let url: String
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
        
        let scriptUrl = extUrl.appendingPathComponent(scriptFileName)
        guard FileManager.default.fileExists(atPath: scriptUrl.path) else {
            throw NSError(domain: "ExtensionManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Script file '\(scriptFileName)' not found"])
        }
        
        return scriptUrl
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
    public func search(localPath: String, query: String, page: Int, configJson: String = "{}") async throws -> [SearchNovelResult] {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "search")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        // Trong VBook, hàm search thường được gọi với tham số (query, page)
        let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "search", arguments: [query, page])
        
        guard let jsArray = jsValue.toArray() else {
            return []
        }
        
        var results: [SearchNovelResult] = []
        for item in jsArray {
            if let dict = item as? [String: Any] {
                let title = dict["name"] as? String ?? ""
                let detailUrl = dict["link"] as? String ?? ""
                let coverUrl = dict["cover"] as? String ?? ""
                let author = dict["author"] as? String ?? "Không rõ"
                
                results.append(SearchNovelResult(title: title, author: author, coverUrl: coverUrl, detailUrl: detailUrl))
            }
        }
        return results
    }
    
    // Lấy thông tin chi tiết truyện
    public func detail(localPath: String, url: String, configJson: String = "{}") async throws -> NovelDetailResult {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "detail")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "detail", arguments: [url])
        
        guard let dict = jsValue.toDictionary() as? [String: Any] else {
            throw NSError(domain: "ExtensionManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "Failed to parse novel detail"])
        }
        
        let title = dict["name"] as? String ?? ""
        let author = dict["author"] as? String ?? "Không rõ"
        let coverUrl = dict["cover"] as? String ?? ""
        let desc = dict["description"] as? String ?? ""
        let detailUrl = dict["detail"] as? String ?? url
        
        return NovelDetailResult(title: title, author: author, coverUrl: coverUrl, desc: desc, detailUrl: detailUrl)
    }
    
    // Lấy mục lục chương
    public func toc(localPath: String, url: String, configJson: String = "{}") async throws -> [ChapterResult] {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "toc")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "toc", arguments: [url])
        
        guard let jsArray = jsValue.toArray() else {
            return []
        }
        
        var results: [ChapterResult] = []
        for item in jsArray {
            if let dict = item as? [String: Any] {
                let title = dict["name"] as? String ?? ""
                let chapUrl = dict["link"] as? String ?? ""
                results.append(ChapterResult(title: title, url: chapUrl))
            }
        }
        return results
    }
    
    // Lấy nội dung chương (có thể là Text hoặc danh sách URL ảnh cho truyện tranh)
    public func chap(localPath: String, url: String, configJson: String = "{}") async throws -> String {
        let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "chap")
        let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
        
        let executor = JSExecutor(localPath: localPath)
        let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
        executor.injectGlobals(configs)
        
        let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "chap", arguments: [url])
        
        if jsValue.isArray {
            if let array = jsValue.toArray() as? [String] {
                return array.joined(separator: "\n")
            }
        }
        
        return jsValue.toString() ?? ""
    }
    
    // Lấy danh mục thể loại (Khám phá)
    public func genre(localPath: String, configJson: String = "{}") async throws -> [String: String] {
        do {
            let scriptUrl = try getScriptPath(extensionPath: localPath, scriptKey: "genre")
            let scriptContent = try String(contentsOf: scriptUrl, encoding: .utf8)
            
            let executor = JSExecutor(localPath: localPath)
            let configs = getCombinedConfigs(localPath: localPath, configJson: configJson)
            executor.injectGlobals(configs)
            
            let jsValue = try await executor.runAsync(scriptContent: scriptContent, functionName: "genre", arguments: [])
            
            if let dict = jsValue.toDictionary() as? [String: String] {
                return dict
            }
            return [:]
        } catch {
            print("Genre script failed or not supported: \(error.localizedDescription)")
            return [:]
        }
    }
}
