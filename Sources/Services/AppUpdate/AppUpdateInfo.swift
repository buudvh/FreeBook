import Foundation

/// Bản app mới nhất đọc từ nguồn cập nhật (`apps.json` ở nhánh `source`, do CI ghi — `AppUpdateSourceClient`).
///
/// `buildNumber` = `CFBundleVersion` của bản đó (số lượt chạy CI, tăng dần) ⇒ so với bản đang chạy theo số này, không
/// theo `version` (bản cùng số CHANGELOG vẫn có thể khác build). `notes` = mỗi commit của lượt build một dòng.
public struct AppUpdateInfo: Sendable, Codable, Equatable, Identifiable {
    public var id: Int { buildNumber }
    public let version: String
    public let buildNumber: Int
    public let date: Date?
    public let notes: [String]

    public init(version: String, buildNumber: Int, date: Date?, notes: [String]) {
        self.version = version
        self.buildNumber = buildNumber
        self.date = date
        self.notes = notes
    }

    /// Dạng hiển thị `1.3.727 (1160)`.
    public var display: String { "\(version) (\(buildNumber))" }

    /// Tách ghi chú release (`- <subject>` mỗi dòng) thành danh sách dòng, bỏ tiền tố gạch đầu dòng và dòng rỗng.
    public static func notes(fromDescription text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("• ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            return line.isEmpty ? nil : line
        }
    }
}
