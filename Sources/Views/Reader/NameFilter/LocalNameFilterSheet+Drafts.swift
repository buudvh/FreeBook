import SwiftUI

/// Section "Gói tạm chưa lưu (N)" ở đầu sheet "Lọc name local" (mockup LAC khung 5) — chỉ hiện khi truyện có gói tạm
/// (`LocalNameFilterDraftStore`, ghi khi đóng màn duyệt mà chưa Lưu / app vào nền lúc đang duyệt). Mỗi hàng: "giờ lọc ·
/// phạm vi", dòng 2 "N name · đang chọn M"; chạm ⇒ mở lại màn duyệt đúng trạng thái đã giữ
/// (`LocalNameFilterSession.openDraft`); vuốt trái ⇒ Xoá. Lưu xong từ màn mở lại ⇒ gói tự xoá (`LocalNameFilterSheet.save`).
extension LocalNameFilterSheet {
    @ViewBuilder
    var draftsSection: some View {
        if !drafts.isEmpty {
            Section {
                ForEach(drafts) { draft in
                    draftRow(draft)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Xoá", role: .destructive) {
                                deleteDraft(draft)
                            }
                        }
                }
            } header: {
                SectionHelpHeader("Gói tạm chưa lưu (\(drafts.count))", paragraphs: [
                    "Đóng màn duyệt mà chưa bấm Lưu (kể cả sau \"Dừng\") thì danh sách đang duyệt được giữ thành một gói tạm của truyện, gồm cả ô đã chọn / bỏ chọn và nghĩa đã sửa.",
                    "Chạm một gói để mở lại đúng màn duyệt đó; vuốt trái để xoá. Bấm Lưu xong thì gói tự biến mất. Mỗi truyện giữ \(LocalNameFilterDraftStore.maxDraftsPerBook) gói ghi gần nhất."
                ])
            }
        }
    }

    private func draftRow(_ draft: LocalNameFilterDraft) -> some View {
        Button {
            session.openDraft(draft, bookId: bookId)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(Self.draftTimeText(draft.filteredAt)) · \(draft.scopeLabel)")
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(verbatim: "\(draft.names.count) name · đang chọn \(draft.selectedCount)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.phase != .setup)
    }

    private func deleteDraft(_ draft: LocalNameFilterDraft) {
        let bid = bookId
        drafts.removeAll { $0.id == draft.id }
        LocalNameFilterDraftStore.delete(id: draft.id, bookId: bid)
        ToastManager.shared.show(message: "Đã xoá gói tạm (\(draft.names.count) name)", type: .success)
    }

    /// Nạp gói của truyện ngoài main (file vài trăm KB với truyện dài).
    func loadDrafts() async {
        let bid = bookId
        let loaded = await Task.detached(priority: .userInitiated) {
            LocalNameFilterDraftStore.load(bookId: bid)
        }.value
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.drafts = loaded
        }
    }

    /// "Hôm nay 10:49" / "Hôm qua 21:05" / "25/11 08:30" (khác năm: "25/11/2025 08:30").
    static func draftTimeText(_ date: Date) -> String {
        let calendar = Calendar.current
        // 24 giờ cố định, không theo kiểu giờ của máy (máy đặt 12 giờ mà bỏ SA / CH thì 09:30 tối thành "09:30").
        let time = String(
            format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date)
        )
        if calendar.isDateInToday(date) { return "Hôm nay \(time)" }
        if calendar.isDateInYesterday(date) { return "Hôm qua \(time)" }
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let dayText = String(format: "%02d/%02d", day, month)
        if year == calendar.component(.year, from: Date()) { return "\(dayText) \(time)" }
        return "\(dayText)/\(year) \(time)"
    }
}
