import SwiftUI

/// Hàng nút viên thuốc (cao 38pt) dưới tên phim: **Trên kệ / Tải / Đổi nguồn / Chia sẻ / Trình duyệt**. Cuộn ngang khi
/// chật.
///
/// - Trên kệ: `VideoWatchModel.toggleShelf` (bật = `setOnShelf` / tạo `Book` trên kệ; tắt = `removeFromShelf`, phim về
///   Lịch sử) — không bao giờ xoá `Book` đang phát. Vừa lên kệ ⇒ mời chọn bộ sưu tập (`CollectionPickerSheet`).
/// - Tải: sheet tải nhiều tập (`TaskOptionsSheet` chế độ video) của **phim này** (`bookForDownload`), không phải phim
///   đang chạy trong phiên.
/// - Đổi nguồn: `SearchView` chế độ đổi nguồn trong sheet; `executeSourceChange` dừng phim của truyện cũ trước khi chạy
///   `BookSourceChangeCoordinator`. Xong ⇒ đóng sheet rồi đóng màn (`onSourceChanged`). Phim chưa lưu ⇒ chỉ tìm nguồn
///   khác cùng loại (bấm kết quả là mở phim đó).
/// - Chia sẻ: link chi tiết tuyệt đối (`shareURL`); không có link http(s) thì ẩn.
/// - Trình duyệt (1.3.763): luôn hiện, có lỗi hay không — mở **trang chi tiết của phim** (`detailPageLink`, không phải
///   link tập) ở trình duyệt chế độ điện thoại; đóng lại chỉ chép cookie, không thử lại (`.sourcePageBrowser`, gắn ở
///   `VideoPlayerScreen`). Tách riêng khỏi "Mở link lỗi" của dòng lỗi: link lỗi thường là `fetch` hỏng (host API).
/// Phim nhập từ file (`LocalMediaPackage`) không có Tải / Đổi nguồn / Trình duyệt (không có nguồn).
struct VideoWatchActionRow: View {
    let model: VideoWatchModel
    /// Trang đang mở trong trình duyệt — `VideoPlayerScreen` giữ để biết màn bị che (không thu nhỏ phim).
    @Binding var openingDetailPage: SourceErrorLink?
    let onSourceChanged: () -> Void

    @State private var collectionPickerBookId = ""
    @State private var showingCollectionPicker = false
    @State private var downloadBook: Book? = nil
    @State private var showingChangeSource = false
    @State private var didChangeSource = false
    @State private var showingShare = false

    private var isLocalMedia: Bool { LocalMediaPackage.isLocalMedia(packageId: model.request.packageId) }
    /// Có `Book` (đã từng xem / lưu) hoặc đã đủ mục lục để tạo ⇒ nút Kệ / Tải bấm được.
    private var canCreateBook: Bool { model.resumePoint != nil || model.phase == .ready }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill(
                    title: model.isOnShelf ? "Trên kệ" : "Thêm vào kệ",
                    systemImage: model.isOnShelf ? "checkmark.circle.fill" : "plus.circle",
                    isActive: model.isOnShelf,
                    isEnabled: canCreateBook && !model.isRunningAction,
                    action: toggleShelf
                )
                if !isLocalMedia {
                    pill(title: "Tải", systemImage: "arrow.down.circle", isEnabled: canCreateBook && !model.isRunningAction, action: openDownload)
                    pill(title: "Đổi nguồn", systemImage: "arrow.2.squarepath") { showingChangeSource = true }
                }
                if model.shareURL != nil {
                    pill(title: "Chia sẻ", systemImage: "square.and.arrow.up") { showingShare = true }
                }
                if let page = model.detailPageLink {
                    pill(title: "Trình duyệt", systemImage: ErrorLinkButton.systemImage) { openingDetailPage = page }
                        .accessibilityHint(page.displayText)
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showingCollectionPicker) {
            CollectionPickerSheet(bookId: collectionPickerBookId)
        }
        .sheet(item: $downloadBook) { book in
            TaskOptionsSheet(book: book, taskType: .download)
        }
        .sheet(isPresented: $showingChangeSource, onDismiss: finishSourceChangeIfNeeded) {
            NavigationStack {
                SearchView(
                    activeExtensions: ExtensionLibraryRepository.shared.installed,
                    selectedExtension: nil,
                    initialSearchQuery: model.displayTitle,
                    changeSourceTargetBook: model.fetchBook(),
                    kindScopePackageId: model.request.packageId,
                    onSourceChanged: {
                        didChangeSource = true
                        showingChangeSource = false
                    },
                    isPresentedAsSheet: true
                )
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingShare) {
            if let url = model.shareURL {
                ShareSheet(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Hành động

    private func toggleShelf() {
        Task {
            switch await model.toggleShelf() {
            case .added(let bookId):
                ToastManager.shared.show(message: "Đã thêm phim vào kệ", type: .success)
                collectionPickerBookId = bookId
                showingCollectionPicker = true
            case .removed:
                ToastManager.shared.show(message: "Đã bỏ phim khỏi kệ (vẫn còn trong Lịch sử)", type: .success)
            case .failed(let message):
                ToastManager.shared.show(message: message, type: .error)
            }
        }
    }

    private func openDownload() {
        Task {
            if let book = await model.bookForDownload() {
                downloadBook = book
            } else {
                ToastManager.shared.show(message: "Chưa tải xong danh sách tập, thử lại sau giây lát.", type: .error)
            }
        }
    }

    /// Sheet đổi nguồn đã đóng hẳn ⇒ mới đóng màn (đóng màn lúc sheet còn hiện chỉ đóng được sheet).
    private func finishSourceChangeIfNeeded() {
        guard didChangeSource else { return }
        didChangeSource = false
        onSourceChanged()
    }

    // MARK: - Viên thuốc

    private func pill(
        title: String,
        systemImage: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 19, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? Color.accentColor : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(shape.fill(isActive ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.12)))
            .overlay(shape.strokeBorder(isActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}
