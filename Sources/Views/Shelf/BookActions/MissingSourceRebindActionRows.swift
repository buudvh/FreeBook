import SwiftUI

/// Hàng "Chuyển sang nguồn …" của sheet nhấn giữ cho truyện mất nguồn (tiện ích nguồn đã gỡ): mỗi tiện ích đã cài có
/// `regexp` khớp link chi tiết một hàng. Bấm ⇒ đóng sheet rồi chạy `MissingSourceRebindRunner` cho riêng truyện đó với
/// đúng tiện ích đã chọn — cùng bước kiểm và cùng cách chuyển (gắn lại tại chỗ / luồng Đổi nguồn) như dải báo của Kệ,
/// kể cả truyện dải báo đã thử không được trong phiên. Truyện còn nguồn hoặc không có tiện ích khớp ⇒ không hiện gì
/// (vẫn còn hàng "Đổi nguồn" thường).
struct MissingSourceRebindActionRows: View {
    let book: Book
    /// Sheet đóng mình trước khi chạy.
    let onStart: () -> Void

    @Environment(\.modelContext) private var modelContext
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false

    var body: some View {
        if MissingSourceRebindCoordinator.isMissingSource(book.extensionPackageId),
           let candidate = MissingSourceRebindCoordinator.shared.candidates(from: [book], includingAttempted: true).first {
            ForEach(candidate.packageIds, id: \.self) { packageId in
                Button {
                    run(candidate.limited(to: packageId))
                } label: {
                    Label("Chuyển sang nguồn \(ExtensionLibraryRepository.snapshot(packageId: packageId)?.name ?? packageId)",
                          systemImage: "arrow.triangle.swap")
                }
                .disabled(MissingSourceRebindCoordinator.shared.isRunning)
            }
        }
    }

    private func run(_ candidate: MissingSourceRebindCoordinator.Candidate) {
        onStart()
        let context = modelContext
        let translates = isTranslationEnabled
        // Như `BookActionSheet.emit`: chạy ở lượt sau, khi sheet đã bắt đầu đóng.
        Task { @MainActor in
            MissingSourceRebindRunner.start(
                [candidate],
                isInteractive: true,
                requiresShelfRoot: false,
                context: context,
                translatesTitles: translates
            )
        }
    }
}
