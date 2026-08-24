import Foundation

/// Mã hoá / giải mã và gộp danh sách **công cụ tra cứu nhanh** (`SearchEngine`).
///
/// Dùng chung cho hai chỗ nên phải là kiểu thuần, không I/O ngoài `Data`:
/// - màn `SearchEnginesConfigView` (nút Xuất/Nhập cấu hình JSON),
/// - `BackupConfigArchiver` (entry `config/search_engines.json` trong file `.fbbackup`).
public enum SearchEngineTransfer {
    /// Trần số lượng và dung lượng file nhập, chặn file rác trước khi decode cả mảng.
    public static let maxEngineCount = 50
    public static let maxFileSizeBytes = 200 * 1024

    public enum Failure: LocalizedError, Equatable {
        case fileTooLarge(maxKB: Int)
        case invalidJSON
        case empty
        case tooMany(count: Int, max: Int)
        case emptyField(index: Int)
        case missingPlaceholder(index: Int, name: String)

        public var errorDescription: String? {
            switch self {
            case .fileTooLarge(let maxKB):
                return "File quá lớn (giới hạn \(maxKB) KB)"
            case .invalidJSON:
                return "Nội dung không phải danh sách công cụ tra cứu hợp lệ"
            case .empty:
                return "File không chứa công cụ nào"
            case .tooMany(let count, let max):
                return "File chứa \(count) công cụ, vượt giới hạn \(max)"
            case .emptyField(let index):
                return "Công cụ thứ \(index + 1) thiếu tên hoặc mẫu URL"
            case .missingPlaceholder(let index, let name):
                return "Công cụ thứ \(index + 1) (\(name)) thiếu ký tự %s trong mẫu URL"
            }
        }
    }

    public static func encode(_ engines: [SearchEngine]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(engines)
    }

    /// Giải mã + kiểm tra từng phần tử. Trả về bản đã trim, giữ nguyên thứ tự trong file.
    public static func decode(_ data: Data, maxSizeBytes: Int = maxFileSizeBytes) -> Result<[SearchEngine], Failure> {
        if data.count > maxSizeBytes {
            return .failure(.fileTooLarge(maxKB: maxSizeBytes / 1024))
        }
        guard let list = try? JSONDecoder().decode([SearchEngine].self, from: data) else {
            return .failure(.invalidJSON)
        }
        if list.isEmpty { return .failure(.empty) }
        if list.count > maxEngineCount {
            return .failure(.tooMany(count: list.count, max: maxEngineCount))
        }

        var sanitized: [SearchEngine] = []
        for (index, engine) in list.enumerated() {
            let name = engine.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let template = engine.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || template.isEmpty {
                return .failure(.emptyField(index: index))
            }
            guard template.contains("%s") else {
                return .failure(.missingPlaceholder(index: index, name: name))
            }
            sanitized.append(SearchEngine(id: engine.id, name: name, urlTemplate: template))
        }
        return .success(sanitized)
    }

    /// Gộp: giữ nguyên thứ tự bản trên máy, chỉ nối vào cuối những công cụ máy chưa có.
    ///
    /// Nhận dạng trùng theo cặp (tên không phân biệt hoa thường, mẫu URL) chứ **không** theo `id`:
    /// cùng một công cụ nhập tay ở hai máy sẽ có `id` khác nhau, so theo `id` sẽ nhân đôi. Ngược
    /// lại, `id` trùng mà nội dung khác thì cấp `id` mới — `ForEach` dựng theo `Identifiable`, hai
    /// hàng cùng `id` là hỏng danh sách.
    public static func merged(current: [SearchEngine], imported: [SearchEngine]) -> [SearchEngine] {
        var result = current
        var usedIds = Set(current.map { $0.id })
        var signatures = Set(current.map(signature(of:)))

        for engine in imported {
            let key = signature(of: engine)
            guard !signatures.contains(key) else { continue }
            signatures.insert(key)

            var copy = engine
            if usedIds.contains(copy.id) { copy.id = UUID() }
            usedIds.insert(copy.id)
            result.append(copy)
        }
        return result
    }

    /// Số công cụ sẽ được thêm nếu gộp — dùng cho hộp thoại chọn phương thức nhập.
    public static func newCount(current: [SearchEngine], imported: [SearchEngine]) -> Int {
        merged(current: current, imported: imported).count - current.count
    }

    private static func signature(of engine: SearchEngine) -> String {
        let name = engine.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let template = engine.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name)\u{1}\(template)"
    }
}
