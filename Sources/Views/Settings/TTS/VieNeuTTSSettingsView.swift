import Combine
import SwiftUI

/// Trang **"Cài đặt VieNeu TTS"** (Cài đặt › Đọc & Nghe › Nghe truyện (TTS)) — **chỉ hiện thông tin**: giọng đang dùng,
/// model Nano / Turbo, Tăng tốc Core ML, giọng nhân bản và lối vào từ điển phiên âm tiếng Nhật. Không có nút tải / xoá /
/// thử: tải theo giọng, nghe thử và xoá (nhấn giữ) đều ở sheet chọn giọng (`VieNeuVoicePickerSheet`). Thay màn thử giọng
/// Nano + màn thử Turbo cũ.
///
/// Dung lượng đọc đĩa ở nền (`DiskSnapshot`, `.task` + `Task.detached`), không trong `body`; đọc lại khi sheet chọn giọng
/// đóng và khi một lượt tải VieNeu kết thúc. Phần Tăng tốc Core ML đọc thẳng `VieNeuCoreMLAccelerator` (`@Observable`),
/// nên bước đang chạy đổi ngay. Giọng đang dùng đọc `TTSManager` **không** observe (luật repo) — vẽ lại khi sheet đóng.
struct VieNeuTTSSettingsView: View {
    @State var snapshot: DiskSnapshot?
    @State private var isPickerPresented = false
    /// Tăng khi sheet chọn giọng đóng ⇒ `body` đọc lại giọng đang dùng (không observe `TTSManager`).
    @State private var selectionToken = 0
    @State private var isVieNeuDownloadRunning = false

    var directory: VieNeuVoiceDirectory { .shared }
    var accelerator: VieNeuCoreMLAccelerator { .shared }

    var body: some View {
        Form { Group {
            voiceSection
            nanoSection
            coreMLSection
            turboSection
            customVoicesSection
            japaneseSection
        }.glassSheetRows() }
        .backPageTitle("Cài đặt VieNeu TTS")
        .vieNeuVoicePickerSheet(isPresented: $isPickerPresented)
        .onAppear {
            directory.reload()
            accelerator.refresh()
        }
        .task { await reloadSnapshot() }
        .onChange(of: isPickerPresented) { _, presented in
            guard !presented else { return }
            selectionToken += 1
            directory.reload()
            accelerator.refresh()
            Task { await reloadSnapshot() }
        }
        // Lượt tải VieNeu (bấm ở sheet chọn giọng) xong ⇒ đọc lại dung lượng. `$entries` phát **trước** khi gán nên
        // tính từ giá trị được phát, không từ `isVieNeuBusy`.
        .onReceive(ModelDownloadCenter.shared.$entries) { entries in
            let running = entries.contains { ModelDownloadCenter.isVieNeuTarget($0.id) && $0.state.isRunning }
            guard running != isVieNeuDownloadRunning else { return }
            isVieNeuDownloadRunning = running
            if !running { Task { await reloadSnapshot() } }
        }
    }

    // MARK: - Giọng đang dùng

    private var voiceSection: some View {
        Section {
            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: 12) {
                    Label {
                        Text("Giọng đọc VieNeu")
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "waveform")
                            .foregroundColor(.accentColor)
                    }
                    Spacer(minLength: 8)
                    Text(currentVoiceText)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// "<tên giọng> · Nano|Turbo" — cùng cách chọn giọng hiển thị với hàng "Giọng đọc" của Cài đặt TTS.
    private var currentVoiceText: String {
        _ = selectionToken
        let manager = TTSManager.shared
        let selection = VieNeuVoiceSummaryRow.displayedSelection(tool: manager.tool, selectedVoice: manager.selectedVoice)
        let name = directory.entry(for: selection)?.name ?? selection.voiceId
        return "\(name) · \(selection.model.label)"
    }

    // MARK: - Tiếng Nhật

    private var japaneseSection: some View {
        Section {
            NavigationLink(destination: VieNeuJapaneseDictionaryView()) {
                Label("Từ điển phiên âm tiếng Nhật", systemImage: "character.book.closed")
            }
        } header: {
            SectionHelpHeader("Tiếng Nhật", paragraphs: ["Từ điển **riêng của VieNeu**, độc lập với từ điển của NghiTTS. Bật/tắt áp dụng ở **Cài đặt TTS → Quản lý riêng của trình đọc**; cả hai công tắc ở đó mặc định **tắt**."])
        }
    }

    // MARK: - Đọc đĩa

    private func reloadSnapshot() async {
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.loadDiskSnapshot()
        }.value
        snapshot = loaded
    }
}
