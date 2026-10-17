import Foundation

/// Host mặc định để ghép URL tương đối khi gọi script, theo hợp đồng extension (extension-api.md):
/// URL tương đối ghép với `host` của item, thiếu thì với `source` của tiện ích.
///
/// Dữ liệu cũ (sách/chương lưu trước 1.3.532) thường có `host = ""` — `toc` từng ghi `""` cho cả item thiếu khoá
/// `host` — nên fallback phải chạy **lúc gọi** (`chapterHost`), không trông vào dữ liệu mới.
///
/// Mọi hàm đọc bảng chụp có lock của `ExtensionLibraryRepository` (hoặc `plugin.json`) nên gọi được từ thread/actor
/// bất kỳ, không `await`.
enum ExtensionHostResolver {
    /// `sourceUrl` của tiện ích **đã cài** (dự phòng: mục catalog chưa cài). `"local"`/rỗng/không tìm thấy ⇒ `nil`.
    nonisolated static func sourceUrl(packageId: String) -> String? {
        let key = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.lowercased() != "local" else { return nil }
        if let installed = nonEmpty(ExtensionLibraryRepository.snapshot(packageId: key)?.sourceUrl) {
            return installed
        }
        return nonEmpty(ExtensionLibraryRepository.catalogSnapshot(packageId: key)?.sourceUrl)
    }

    /// `sourceUrl` theo thư mục tiện ích: tiện ích đã cài ⇒ bản ghi trong kho tiện ích (người dùng có thể đã sửa
    /// `source` ở màn Cấu hình); bản nháp debug (ngoài `extensions/`) hoặc bản ghi thiếu `source` ⇒ `metadata.source`
    /// trong `plugin.json`.
    nonisolated static func sourceUrl(localPath: String) -> String? {
        let path = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if let packageId = ExtensionLibraryRepository.packageId(forLocalPath: path),
           let source = sourceUrl(packageId: packageId) {
            return source
        }
        return ExtensionManifestReader.source(localPath: path)
    }

    /// Host dùng khi gọi `chap` cho một chương: host chương (khác rỗng) → host sách (khác rỗng) → `source`.
    /// Chỉ dùng cho tham số `host` của script — **không** đổi URL chương đã lưu (khoá nhận diện).
    nonisolated static func chapterHost(chapterHost: String?, bookHost: String?, packageId: String) -> String? {
        nonEmpty(chapterHost) ?? nonEmpty(bookHost) ?? sourceUrl(packageId: packageId)
    }

    /// Chuỗi đã trim, `nil` khi rỗng.
    nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
