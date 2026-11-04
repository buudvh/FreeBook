import SwiftUI

/// Dải báo "truyện mất nguồn" của Kệ — xem `MissingSourceRebindCoordinator`.
///
/// Dò mỗi lần trang gốc Kệ hiện (`onAppear`: mở app, quay lại từ Chi tiết, đóng Reader, đổi tab), lúc không màn
/// Chi tiết/Reader nào của Kệ đang mở. Theo Cài đặt › Thư Viện › Truyện mất nguồn:
/// - Hỏi một chạm: hiện dải báo, bấm "Chuyển" là chạy cho mọi truyện trong dải.
/// - Tự chuyển: chạy ngầm cho truyện chỉ khớp một nguồn; truyện khớp từ 2 nguồn vẫn hiện dải báo để hỏi.
///
/// Lượt chạy là `Task` không gắn vòng đời view nên vẫn báo toast khi đã rời Kệ, nhưng rời trang gốc Kệ (hoặc mở đúng
/// truyện đang chuyển) thì coordinator dừng trước khi ghi truyện kế tiếp; lần hiện Kệ sau thử lại phần còn lại.
struct MissingSourceRebindBanner: View {
    let books: [Book]
    /// Chỉ hiện ở tab Kệ sách và Lịch sử; việc dò vẫn chạy ở mọi tab.
    let isVisible: Bool

    @Environment(\.modelContext) private var modelContext
    @AppStorage(MissingSourceRebindMode.defaultsKey) private var mode: MissingSourceRebindMode = .ask
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    @State private var pending: [MissingSourceRebindCoordinator.Candidate] = []

    private var coordinator: MissingSourceRebindCoordinator { .shared }

    var body: some View {
        VStack(spacing: 0) {
            // Neo `onAppear`: `if` rỗng không có view để nhận sự kiện.
            Color.clear.frame(height: 0)
            if isVisible && (coordinator.isRunning || (!pending.isEmpty && !coordinator.isBannerDismissed)) {
                banner
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pending)
        .onAppear {
            coordinator.isShelfRootVisible = true
            refresh()
        }
        // Rời trang gốc Kệ (mở Chi tiết/Reader, đổi tab) ⇒ lượt đang chạy dừng trước khi ghi truyện kế tiếp.
        .onDisappear { coordinator.isShelfRootVisible = false }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            if coordinator.isRunning {
                Text(coordinator.statusText)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                ProgressView()
            } else {
                Text(message)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Chuyển", action: switchPending)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button {
                    coordinator.isBannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ẩn")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var message: String {
        guard pending.count == 1, let only = pending.first else {
            return "\(pending.count) truyện mất nguồn có nguồn khớp link"
        }
        let title = BookDisplayTranslation.title(only.title, bookId: only.bookId, isEnabled: isTranslationEnabled)
        let extName = only.packageIds.first.flatMap { ExtensionLibraryRepository.snapshot(packageId: $0)?.name } ?? ""
        return extName.isEmpty ? "“\(title)” mất nguồn, có nguồn khớp link" : "“\(title)” mất nguồn, chuyển sang \(extName)?"
    }

    private func refresh() {
        guard !coordinator.isRunning else { return }
        let found = coordinator.candidates(from: books)
        guard mode == .auto else {
            pending = found
            return
        }
        pending = found.filter { $0.packageIds.count > 1 }
        start(found.filter { $0.packageIds.count == 1 }, isInteractive: false)
    }

    private func switchPending() {
        let items = pending
        pending = []
        start(items, isInteractive: true)
    }

    private func start(_ candidates: [MissingSourceRebindCoordinator.Candidate], isInteractive: Bool) {
        guard !candidates.isEmpty else { return }
        let context = modelContext
        let translates = isTranslationEnabled
        Task { @MainActor in
            let report = await MissingSourceRebindCoordinator.shared.run(
                candidates,
                isInteractive: isInteractive,
                context: context,
                isBookOpen: { ReaderView.activeBookId == $0 }
            )
            Self.showToast(report, translates: translates, includesFailures: isInteractive)
        }
    }

    /// Tự chuyển (`includesFailures == false`) chỉ báo truyện đã chuyển: truyện không chuyển được sẽ được thử lại ở mỗi
    /// lần mở app, báo lỗi mỗi lần là phiền; lý do vẫn có trong log.
    private static func showToast(_ report: MissingSourceRebindCoordinator.Report, translates: Bool, includesFailures: Bool) {
        var parts: [String] = []
        if report.rebound.count == 1, let only = report.rebound.first {
            let title = BookDisplayTranslation.title(only.title, bookId: only.bookId, isEnabled: translates)
            parts.append("Đã chuyển “\(title)” sang nguồn \(only.extName)")
        } else if !report.rebound.isEmpty {
            parts.append("Đã chuyển \(report.rebound.count) truyện mất nguồn sang nguồn khớp link")
        }
        let showsFailures = includesFailures && (report.incompatible > 0 || report.failed > 0)
        if showsFailures && report.incompatible > 0 {
            parts.append("\(report.incompatible) truyện có mục lục nguồn mới khác dạng, hãy dùng Đổi nguồn")
        }
        if showsFailures && report.failed > 0 {
            parts.append("\(report.failed) truyện lỗi khi tải nguồn mới")
        }
        guard !parts.isEmpty else { return }
        let type: ToastType
        if !showsFailures {
            type = .success
        } else {
            type = report.rebound.isEmpty ? .error : .info
        }
        ToastManager.shared.show(message: parts.joined(separator: "; "), type: type)
    }
}
