import Foundation

/// Đọc file từ điển do người dùng chọn thành `[String: String]`. Hỗ trợ `.plist`, `.json`, `.csv`, `.txt`.
///
/// ## Vì sao dùng chung
/// Trước đây mỗi màn từ điển có bản parse riêng (`TTSDictionaryEditView.parseCSV` + nhánh plist/json viết
/// thẳng trong `importDictionary`, còn `VieNeuJapaneseDictionaryView` chỉ nhận plist/json), nên "file hợp
/// lệ" ở màn này có thể không hợp lệ ở màn kia. Nay cả hai màn và màn chọn mục trùng khoá đi qua đúng một
/// định nghĩa.
///
/// ## Không chuẩn hoá khoá ở đây — **cố ý**
/// Việc chuẩn hoá khoá là của **từng từ điển**: VieNeu gấp dấu phụ (`VieNeuJapaneseDictionary.normalizedKey`),
/// NghiTTS chỉ hạ chữ thường khi lưu nhưng lúc đọc lại tra bằng khoá **đã gấp dấu**. Bản `parseCSV` cũ tự
/// `lowercased()` khoá nên luồng CSV chuẩn hoá **khác** luồng plist — để caller làm thì hai luồng khớp nhau.
enum DictionaryImportParser {

    enum ParseError: LocalizedError {
        case unsupportedExtension(String)
        case empty
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Định dạng tệp .\(ext) không được hỗ trợ (chỉ nhận .plist, .json, .csv, .txt)."
            case .empty:
                return "File không chứa mục từ điển nào hợp lệ."
            case .malformed(let detail):
                return detail
            }
        }
    }

    static func parse(url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try parse(data: data, pathExtension: url.pathExtension)
    }

    static func parse(data: Data, pathExtension: String) throws -> [String: String] {
        let words: [String: String]
        switch pathExtension.lowercased() {
        case "plist":
            guard let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: String] else {
                throw ParseError.malformed("Tệp .plist không hợp lệ. Vui lòng chọn tệp chứa định dạng [String: String].")
            }
            words = dict
        case "json":
            words = try parseJSON(data)
        case "csv", "txt":
            words = try parseCSV(data)
        default:
            throw ParseError.unsupportedExtension(pathExtension)
        }
        guard !words.isEmpty else { throw ParseError.empty }
        return words
    }

    /// JSON phẳng `[String: String]`. Nhận thêm giá trị số/bool vì bản xuất cũ có thể chứa chúng.
    private static func parseJSON(_ data: Data) throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        if let dict = object as? [String: String] { return dict }
        guard let raw = object as? [String: Any] else {
            throw ParseError.malformed("Tệp .json không hợp lệ. Vui lòng chọn tệp chứa dạng cặp khoá-giá trị phẳng [String: String].")
        }
        var words: [String: String] = [:]
        for (key, value) in raw {
            if let stringValue = value as? String {
                words[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                words[key] = numberValue.stringValue
            }
        }
        return words
    }

    /// CSV 2 cột `key,value`, có hỗ trợ nháy kép (khuôn `generateCSV` của màn NghiTTS: `"key","value"`).
    /// Bỏ dòng tiêu đề (`Từ gốc,Thay thế` / `key,value`).
    private static func parseCSV(_ data: Data) throws -> [String: String] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.malformed("Không thể đọc tệp CSV dưới dạng UTF-8.")
        }
        var words: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let fields = splitCSVLine(line.trimmingCharacters(in: .whitespacesAndNewlines))
            guard fields.count >= 2 else { continue }
            let key = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !isHeaderRow(key, value) else { continue }
            words[key] = value
        }
        return words
    }

    /// Tách một dòng CSV theo dấu phẩy **ngoài** nháy kép; `""` trong chuỗi được hiểu là một nháy kép.
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false
        let chars = Array(line)
        var index = 0

        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if insideQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                insideQuotes.toggle()
            } else if char == ",", !insideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }

    private static func isHeaderRow(_ key: String, _ value: String) -> Bool {
        let keyIsHeader = key == "Từ gốc" || key.lowercased() == "key" || key.lowercased() == "original"
        let valueIsHeader = value == "Thay thế" || value.lowercased() == "value" || value.lowercased() == "replacement"
        return keyIsHeader && valueIsHeader
    }
}
