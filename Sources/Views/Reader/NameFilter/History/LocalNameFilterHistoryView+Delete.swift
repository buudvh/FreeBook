import SwiftUI

/// Xoá ở trang Lịch sử lọc (mockup H3–H5, https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2):
/// - **H3** vuốt trái một hàng ⇒ hỏi "Xoá lần lọc 10:20?"; còn gói tạm thì nói rõ gói cũng bị xoá.
/// - **H4** ⋯ ⇒ ngăn kéo: "Chọn nhiều để xoá" (vào H5) và "Dọn dẹp tất cả" (đỏ, dòng phụ "N lần · M gói tạm chưa lưu",
///   hỏi "Xoá N lần lọc?").
/// - **H5** chế độ chọn nhiều kiểu Kệ (`ShelfView+Selection`): header ✕ + "Đã chọn N" + "Chọn tất cả" / "Bỏ chọn tất cả",
///   chạm hàng để tích, thanh đáy "N lần · M gói tạm chưa lưu" + nút đỏ "Xoá (N)" ⇒ hỏi lại; ✕ hoặc xoá xong ⇒ về như thường.
/// Mọi lối xoá đều hỏi lại và kéo theo gói tạm chưa lưu của lần đó (`LocalNameFilterHistoryStore.removeEntries`); name đã
/// lưu vào Name / VP riêng không bị đụng.
extension LocalNameFilterHistoryView {
    /// Một lối xoá đang chờ hỏi lại.
    struct DeleteRequest: Identifiable {
        let id = UUID()
        let ids: Set<UUID>
        let title: String
        let message: String
    }

    /// Các lần đã tích còn trong danh sách đang hiện.
    func selectedIds(_ selection: Set<UUID>) -> Set<UUID> {
        selection.intersection(snapshot.entries.map(\.id))
    }

    // MARK: - Header

    /// ✕ trước tiêu đề "Đã chọn N" (chỉ khi đang chọn).
    var selectionExitButton: HeaderLeadingIconButton {
        HeaderLeadingIconButton(systemName: "xmark", accessibilityLabel: "Thoát chọn nhiều") {
            selection = nil
        }
    }

    /// Thường ⇒ ⋯ mở ngăn kéo; đang chọn ⇒ "Chọn tất cả" / "Bỏ chọn tất cả".
    @ViewBuilder
    var headerTrailingButton: some View {
        if let selection {
            let allSelected = !snapshot.isEmpty && selectedIds(selection).count == snapshot.entries.count
            Button(allSelected ? "Bỏ chọn tất cả" : "Chọn tất cả") {
                self.selection = allSelected ? [] : Set(snapshot.entries.map(\.id))
            }
            .headerTextButton()
            .disabled(snapshot.isEmpty)
        } else {
            Button {
                showingMenu = true
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: HeaderMetrics.iconFontSize, weight: .semibold))
                    .frame(width: HeaderMetrics.iconFrameWidth, height: HeaderMetrics.iconFrameHeight, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tuỳ chọn Lịch sử lọc")
        }
    }

    // MARK: - Ngăn kéo (H4)

    @ViewBuilder
    var drawerContent: some View {
        SideDrawerActionRow("Chọn nhiều để xoá", systemImage: "checkmark.circle") {
            selection = []
        }
        .disabled(snapshot.isEmpty)
        LocalNameFilterHistoryDrawerRow(
            title: "Dọn dẹp tất cả",
            subtitle: Self.countText(entries: snapshot.entries.count, drafts: snapshot.unsavedDraftCount),
            systemImage: "trash",
            role: .destructive
        ) {
            requestDelete(ids: Set(snapshot.entries.map(\.id)))
        }
        .disabled(snapshot.isEmpty)
    }

    // MARK: - Thanh đáy (H5)

    /// Gắn qua `safeAreaInset` luôn có mặt; chỉ có nội dung khi đang chọn.
    @ViewBuilder
    var selectionBar: some View {
        if let selection {
            let ids = selectedIds(selection)
            HStack(spacing: 12) {
                Text(verbatim: ids.isEmpty
                    ? "Chưa chọn lần nào"
                    : Self.countText(entries: ids.count, drafts: snapshot.unsavedDraftCount(among: ids)))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    requestDelete(ids: ids)
                } label: {
                    Text(verbatim: "Xoá (\(ids.count))")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(ids.isEmpty)
            }
            .padding(.horizontal, HeaderMetrics.horizontalMargin)
            .padding(.vertical, 10)
            .background(.bar, ignoresSafeAreaEdges: .bottom)
        }
    }

    // MARK: - Hỏi lại + xoá

    /// Vuốt Xoá một lần lọc (H3).
    func requestDelete(_ entry: LocalNameFilterHistoryEntry) {
        let message: String
        switch snapshot.status(of: entry) {
        case .unsaved(let draft):
            message = "Gói tạm \(draft.names.count) name chưa lưu của lần này cũng bị xoá."
        case .saved:
            message = "Chỉ xoá dòng lịch sử, name đã lưu vào Name / VP riêng giữ nguyên."
        case .draftGone, .noNames, .failed, .cancelled, .interrupted, .running:
            message = "Chỉ xoá dòng lịch sử."
        }
        deleteRequest = DeleteRequest(
            ids: [entry.id],
            title: "Xoá lần lọc \(LocalNameFilterHistoryRow.shortStampText(entry.startedAt))?",
            message: message
        )
    }

    /// Xoá nhiều lần một lúc — chọn nhiều (H5) hoặc "Dọn dẹp tất cả" (H4).
    func requestDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let drafts = snapshot.unsavedDraftCount(among: ids)
        let kept = "Name đã lưu vào Name / VP riêng giữ nguyên."
        deleteRequest = DeleteRequest(
            ids: ids,
            title: "Xoá \(ids.count) lần lọc?",
            message: drafts > 0 ? "\(drafts) gói tạm chưa lưu cũng bị xoá. \(kept)" : kept
        )
    }

    func performDelete(_ request: DeleteRequest) {
        let ids = selectedIds(request.ids)
        deleteRequest = nil
        guard !ids.isEmpty else { return }
        let drafts = snapshot.unsavedDraftCount(among: ids)
        LocalNameFilterHistoryStore.removeEntries(ids: ids, bookId: bookId)
        snapshot = snapshot.removing(ids)
        selection = nil
        let draftNote = drafts > 0 ? " · \(drafts) gói tạm" : ""
        ToastManager.shared.show(message: "Đã xoá \(ids.count) lần lọc\(draftNote)", type: .success)
    }

    /// "12 lần · 2 gói tạm chưa lưu" (không có gói ⇒ "12 lần").
    static func countText(entries: Int, drafts: Int) -> String {
        drafts > 0 ? "\(entries) lần · \(drafts) gói tạm chưa lưu" : "\(entries) lần"
    }
}
