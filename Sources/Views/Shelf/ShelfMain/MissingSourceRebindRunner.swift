import SwiftUI
import SwiftData

/// Phần View của một lượt chuyển truyện mất nguồn (`MissingSourceRebindCoordinator.run`): chạy trong `Task` không gắn
/// vòng đời view (rời màn giữa chừng vẫn báo toast), rồi làm nốt các bước thuộc tầng View — chuyển phiên AI sang truyện
/// mới khi lượt đi luồng Đổi nguồn (`AIRuntimeCoordinator` ở tầng View, như `SearchView+SourceChange`) và toast.
/// Dùng chung cho dải báo của Kệ (`MissingSourceRebindBanner`) và sheet nhấn giữ (`MissingSourceRebindActionRows`).
@MainActor
enum MissingSourceRebindRunner {
    static func start(
        _ candidates: [MissingSourceRebindCoordinator.Candidate],
        isInteractive: Bool,
        requiresShelfRoot: Bool,
        context: ModelContext
    ) {
        guard !candidates.isEmpty else { return }
        if isInteractive && (MissingSourceRebindCoordinator.shared.isRunning || BookSourceChangeCoordinator.shared.isRunning) {
            ToastManager.shared.show(message: "Đang có lượt đổi nguồn khác chạy, thử lại sau ít giây", type: .info)
            return
        }
        Task { @MainActor in
            let report = await MissingSourceRebindCoordinator.shared.run(
                candidates,
                isInteractive: isInteractive,
                requiresShelfRoot: requiresShelfRoot,
                context: context,
                isBookOpen: { ReaderView.activeBookId == $0 || ReaderSessionRestoreStore.isRestoring(bookId: $0) }
            )
            for item in report.switched where item.newBookId != item.oldBookId {
                AIRuntimeCoordinator.shared.migrateLastSession(from: item.oldBookId, to: item.newBookId)
            }
            showToast(report, context: context, includesFailures: isInteractive)
        }
    }

    /// Tự chuyển (`includesFailures == false`) chỉ báo truyện đã chuyển: truyện không chuyển được sẽ được thử lại ở mỗi
    /// lần mở app, báo lỗi mỗi lần là phiền; lý do vẫn có trong log (`❌ [SourceRebind]`).
    private static func showToast(
        _ report: MissingSourceRebindCoordinator.Report,
        context: ModelContext,
        includesFailures: Bool
    ) {
        var parts: [String] = []
        if report.switched.count == 1, let only = report.switched.first {
            let title = displayTitle(only.title, bookId: only.newBookId, context: context)
            parts.append("Đã chuyển “\(title)” sang nguồn \(only.extName)")
        } else if !report.switched.isEmpty {
            parts.append("Đã chuyển \(report.switched.count) truyện mất nguồn sang nguồn khớp link")
        }
        if report.keptOldBooks > 0 {
            parts.append("\(report.keptOldBooks) truyện chép chương đã tải lỗi nên giữ lại truyện cũ")
        }
        let showsFailures = includesFailures && (report.incompatible > 0 || report.failed > 0)
        if showsFailures && report.incompatible > 0 {
            parts.append("\(report.incompatible) truyện có mục lục nguồn mới khác hẳn, hãy dùng Đổi nguồn")
        }
        if showsFailures && report.failed > 0 {
            parts.append("\(report.failed) truyện lỗi khi tải nguồn mới")
        }
        guard !parts.isEmpty else { return }
        let type: ToastType
        if !showsFailures && report.keptOldBooks == 0 {
            type = .success
        } else {
            type = report.switched.isEmpty ? .error : .info
        }
        ToastManager.shared.show(message: parts.joined(separator: "; "), type: type)
    }

    /// Tên truyện trong toast theo ba cấp của popup dịch + phồn → giản, tính với nguồn **mới** của truyện (đọc lại `Book`
    /// sau lượt chuyển; không thấy ⇒ bỏ cấp nguồn).
    private static func displayTitle(_ title: String, bookId: String, context: ModelContext) -> String {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        let packageId = (try? context.fetch(descriptor).first)?.extensionPackageId
        return BookDisplayTranslation.title(title, BookDisplayTranslation.options(bookId: bookId, packageId: packageId))
    }
}
