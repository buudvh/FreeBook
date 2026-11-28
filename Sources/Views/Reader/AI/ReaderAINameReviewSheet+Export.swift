import SwiftUI
import SwiftData

/// Nút ▼ › "Xuất file" của màn duyệt name (`ReaderAINameReviewSheet`, cả luồng AI và Lọc name local; mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M1, mục C8 — anh Bửu chốt "xuất mục đang tích"):
/// - Nội dung = **đúng** tập Lưu sẽ ghi (`recordsToSave` của `+Save`: mục đang tích, luồng AI bỏ hàng gạch, khoá đã trim,
///   nghĩa đã chuẩn hoá, khoá lặp giữ mục đầu), mỗi dòng `chữ Hán=nghĩa`, UTF-8.
/// - Tên file `Name_<tên truyện>_<yyyyMMddHHmmss>.txt` đặt như danh sách Name (`DictionaryExportFileName`, chung với
///   `DictionaryListView`): luồng lọc local tra `Book` theo `bookId`; luồng AI dùng tên truyện màn AI đang hiện
///   (`exportBookTitle`) vì màn AI có thể mở bằng UIKit, môi trường không có `ModelContainer`.
/// - Ghi xong mở bảng chia sẻ hệ thống (`ShareSheet`); ghi lỗi ⇒ toast lỗi + log ❌.
extension ReaderAINameReviewSheet {
    /// File đang đưa cho bảng chia sẻ (`.sheet(item:)` của màn duyệt).
    struct ExportedFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    func exportSelectedNames() {
        let records = recordsToSave
        guard !records.isEmpty else { return }
        let content = records.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        do {
            let url = try DictionaryExportFileName.writeTemporaryFile(content, named: exportFileName())
            exportedFile = ExportedFile(url: url)
        } catch {
            AppLogger.shared.log("❌ Lỗi ghi file xuất name của màn duyệt (truyện \(bookId)): \(error.localizedDescription)")
            ToastManager.shared.show(message: "Không xuất được file name: \(error.localizedDescription)", type: .error)
        }
    }

    func exportShareSheet(for file: ExportedFile) -> some View {
        ShareSheet(activityItems: [file.url]) { _, completed, _, error in
            if completed {
                ToastManager.shared.show(message: "Xuất file name thành công!", type: .success)
            } else if let error {
                ToastManager.shared.show(message: "Lỗi chia sẻ: \(error.localizedDescription)", type: .error)
            }
        }
    }

    private func exportFileName() -> String {
        if let exportBookTitle {
            return DictionaryExportFileName.make(
                prefix: "Name", dbTitle: nil, fallbackTitle: exportBookTitle, bookId: bookId, packageId: nil
            )
        }
        let book = storedBook()
        return DictionaryExportFileName.make(
            prefix: "Name", dbTitle: book?.title, fallbackTitle: "", bookId: bookId, packageId: book?.extensionPackageId
        )
    }

    /// `Book` của màn duyệt — chỉ luồng lọc local gọi (mở từ `ReaderView` bằng `.sheet`, môi trường có container của app).
    /// Container trong môi trường không có `Book` (container mặc định khi không ai gắn `.modelContainer`) ⇒ `nil`, tên file
    /// lùi về `bookId` thay vì fetch trên schema rỗng.
    private func storedBook() -> Book? {
        let entityName = String(describing: Book.self)
        guard !bookId.isEmpty,
              modelContext.container.schema.entities.contains(where: { $0.name == entityName }) else { return nil }
        let id = bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
