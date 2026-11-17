import SwiftUI

/// Trang "Prompt đã lưu" của sheet quét tên riêng theo phạm vi, đẩy vào `NavigationStack` của sheet như "Chọn chương…".
///
/// Hai nhóm từ `AINameScanPromptStore`: **Đã ghim** (dùng chung mọi truyện) và **Gần đây của truyện này** (tối đa 10).
/// Chạm một dòng ⇒ báo `onSelect` (chữ prompt) rồi quay lại sheet — sheet chép vào ô "Prompt cho lần này" và chọn
/// "Tự nhập prompt". Nhấn giữ: Ghim / Bỏ ghim, Xoá; vuốt trái: Xoá (không hỏi lại). Nhóm rỗng thì ẩn.
struct ReaderAISavedPromptsView: View {
    @Environment(\.dismiss) private var dismiss

    let bookId: String
    let onSelect: (String) -> Void

    @State private var pins: [AINameScanSavedPrompt] = []
    @State private var recents: [AINameScanSavedPrompt] = []
    /// Chưa nạp xong thì không hiện màn trống (tránh loé "Chưa có prompt nào" trước lượt `onAppear`).
    @State private var hasLoaded = false

    var body: some View {
        List { Group {
            if !pins.isEmpty {
                Section("Đã ghim") {
                    ForEach(pins) { prompt in
                        row(for: prompt, isPinned: true)
                    }
                }
            }
            if !recents.isEmpty {
                Section("Gần đây của truyện này") {
                    ForEach(recents) { prompt in
                        row(for: prompt, isPinned: false)
                    }
                }
            }
        }.glassSheetRows() }
        .listStyle(.plain)
        .overlay {
            if hasLoaded && pins.isEmpty && recents.isEmpty {
                ContentUnavailableView("Chưa có prompt nào đã lưu", systemImage: "bookmark")
            }
        }
        .backPageTitle("Prompt đã lưu")
        .onAppear { reload() }
    }

    private func row(for prompt: AINameScanSavedPrompt, isPinned: Bool) -> some View {
        Button {
            onSelect(prompt.text)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isPinned ? "pin.fill" : "clock")
                    .font(.subheadline)
                    .foregroundColor(isPinned ? .accentColor : .secondary)
                    .frame(width: 20)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(prompt.text)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle(for: prompt, isPinned: isPinned))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isPinned {
                Button {
                    update { AINameScanPromptStore.shared.unpin(id: prompt.id, bookId: bookId) }
                } label: {
                    Label("Bỏ ghim", systemImage: "pin.slash")
                }
            } else {
                Button {
                    update { AINameScanPromptStore.shared.pin(id: prompt.id, bookId: bookId) }
                } label: {
                    Label("Ghim", systemImage: "pin")
                }
            }
            Button(role: .destructive) {
                update { AINameScanPromptStore.shared.delete(id: prompt.id, bookId: bookId) }
            } label: {
                Label("Xoá", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                update { AINameScanPromptStore.shared.delete(id: prompt.id, bookId: bookId) }
            } label: {
                Label("Xoá", systemImage: "trash")
            }
        }
    }

    /// Bản ghim: "N dòng"; Gần đây: "14:20 hôm nay · N dòng" / "Hôm qua · …" / "dd/MM · …".
    private func subtitle(for prompt: AINameScanSavedPrompt, isPinned: Bool) -> String {
        let lines = "\(prompt.lineCount) dòng"
        return isPinned ? lines : "\(Self.timeLabel(prompt.lastUsedAt)) · \(lines)"
    }

    private static func timeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "\(date.formatted(date: .omitted, time: .shortened)) hôm nay"
        }
        if calendar.isDateInYesterday(date) { return "Hôm qua" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM"
        return formatter.string(from: date)
    }

    private func update(_ change: () -> Void) {
        change()
        withAnimation { reload() }
    }

    private func reload() {
        pins = AINameScanPromptStore.shared.pins()
        recents = AINameScanPromptStore.shared.recents(bookId: bookId)
        hasLoaded = true
    }
}

extension ReaderAISavedPromptsView {
    /// Dòng "Chọn prompt đã lưu…" trong mục Nguồn prompt của sheet: phụ đề "2 đã ghim · 3 gần đây" (bỏ vế bằng 0);
    /// chưa có prompt nào thì mờ, khoá, "Chưa có prompt nào đã lưu" — cùng kiểu dòng "Chọn chương…". Số do sheet đưa
    /// (sheet đếm lại mỗi lần quay về từ trang này).
    struct EntryRow: View {
        let bookId: String
        let pinnedCount: Int
        let recentCount: Int
        let onSelect: (String) -> Void

        private var isEmpty: Bool { pinnedCount + recentCount == 0 }

        private var subtitle: String {
            var parts: [String] = []
            if pinnedCount > 0 { parts.append("\(pinnedCount) đã ghim") }
            if recentCount > 0 { parts.append("\(recentCount) gần đây") }
            return parts.isEmpty ? "Chưa có prompt nào đã lưu" : parts.joined(separator: " · ")
        }

        var body: some View {
            NavigationLink {
                ReaderAISavedPromptsView(bookId: bookId, onSelect: onSelect)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chọn prompt đã lưu…")
                            .foregroundColor(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .disabled(isEmpty)
            .opacity(isEmpty ? 0.45 : 1)
        }
    }
}
