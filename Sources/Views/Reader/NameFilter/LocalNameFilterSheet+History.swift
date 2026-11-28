import SwiftUI

/// Hàng **"Lịch sử lọc ›"** ở đầu sheet "Lọc name local" (mockup H1, https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 —
/// thay section "Gói tạm chưa lưu (N)" cũ): icon đồng hồ + "Lịch sử lọc", dòng phụ "Lần gần nhất dd/MM HH:mm", bên phải
/// "N lần · M chưa lưu" (M = lần chưa lưu còn gói tạm, màu cam; 0 thì bỏ), chưa có lần nào ⇒ "Chưa có". Chạm ⇒ đẩy trang
/// `LocalNameFilterHistoryView` vào `NavigationStack` của sheet (`showsHistory`).
///
/// Mở lại một gói từ trang lịch sử thay cả gốc sheet bằng màn duyệt (`NavigationStack` bị gỡ); bấm ‹ ở màn duyệt dựng lại
/// stack từ gốc ⇒ `reopenHistoryIfNeeded` (gọi khi phiên về bước chọn) đẩy lại trang lịch sử để về đúng chỗ đã mở. Cờ chỉ
/// dùng một lần, nên quay về gốc bằng nút back sau đó không bị đẩy lại.
///
/// Mỗi lần trang đầu hiện ra: đọc lịch sử + gói tạm (gói có từ trước được tạo mục "chưa lưu"), rồi cho gói tạm tự cập
/// nhật như trước (`LocalNameFilterDraftRefresher` — bộ cập nhật có thể bỏ hết name của một gói ⇒ số "chưa lưu" đổi).
extension LocalNameFilterSheet {
    var historySection: some View {
        Section {
            Button {
                showsHistory = true
            } label: {
                historyRowLabel
            }
            .buttonStyle(.plain)
            .disabled(session.phase != .setup)
        }
    }

    private var historyRowLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalNameFilterHistoryView.title)
                    .foregroundColor(.primary)
                if let latest = history.latest {
                    Text(verbatim: "Lần gần nhất \(LocalNameFilterHistoryRow.stampText(latest.startedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if historyLoaded {
                historyCountText
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// "12 lần · 2 chưa lưu" (phần chưa lưu màu cam) / "Chưa có".
    private var historyCountText: Text {
        guard !history.isEmpty else {
            return Text("Chưa có").foregroundColor(.secondary)
        }
        let total = Text(verbatim: "\(history.entries.count) lần").foregroundColor(.secondary)
        let unsaved = history.unsavedDraftCount
        guard unsaved > 0 else { return total }
        return total
            + Text(verbatim: " · ").foregroundColor(.secondary)
            + Text(verbatim: "\(unsaved) chưa lưu").foregroundColor(.orange)
    }

    /// Chạm một lần chưa lưu ở trang lịch sử: nhớ để quay về trang đó, rồi mở lại màn duyệt của gói. Hạ `showsHistory`
    /// luôn (stack sắp bị gỡ) để lúc quay về là một lần đổi `false → true` thật — stack mới dựng mà cờ đã `true` sẵn thì
    /// không chắc SwiftUI đẩy trang.
    func openDraftFromHistory(_ draft: LocalNameFilterDraft) {
        guard session.phase == .setup else { return }
        reopensHistoryAfterReview = true
        showsHistory = false
        session.openDraft(draft, bookId: bookId)
    }

    /// Phiên về bước chọn sau màn duyệt mở từ lịch sử ⇒ đẩy lại trang lịch sử (stack vừa dựng lại từ gốc).
    func reopenHistoryIfNeeded() {
        guard reopensHistoryAfterReview else { return }
        reopensHistoryAfterReview = false
        showsHistory = true
    }

    /// Đọc lịch sử + gói tạm ngoài main rồi cho gói tự cập nhật (`LocalNameFilterHistoryView.loadSnapshot` /
    /// `refreshedDrafts`). Chạy mỗi lần trang đầu hiện ra (`.task` chạy lại khi quay về từ trang con / từ màn duyệt).
    func loadHistory() async {
        let bid = bookId
        let loaded = await LocalNameFilterHistoryView.loadSnapshot(bookId: bid)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.history = loaded
            self.historyLoaded = true
        }
        guard !loaded.drafts.isEmpty else { return }
        let refreshed = await LocalNameFilterHistoryView.refreshedDrafts(bookId: bid)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.history = self.history.replacingDrafts(refreshed)
        }
    }
}
