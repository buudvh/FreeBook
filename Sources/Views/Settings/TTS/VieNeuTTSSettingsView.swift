import Combine
import SwiftUI

/// Trang **"Cài đặt VieNeu TTS"** (Cài đặt › Đọc & Nghe › Nghe truyện (TTS)) — thông tin giọng đang dùng, model Nano / Turbo,
/// Tăng tốc Core ML, giọng nhân bản và lối vào từ điển phiên âm tiếng Nhật. Tải theo giọng, nghe thử và xoá từng giọng Turbo
/// (nút 🗑) ở sheet chọn giọng (`VieNeuVoicePickerSheet`); trang này chỉ có hai nút **xoá cả gói** ở cuối mục Nano / Turbo
/// ("Xoá tất cả dữ liệu …", hỏi lại, `VieNeuModelDataRemover`). Thay màn thử giọng Nano + màn thử Turbo cũ.
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
    /// Gói đang chờ xác nhận "Xoá tất cả dữ liệu …" / gói đang xoá (vòng xoay trên hàng). `internal` vì hàng nằm ở `+Sections`.
    @State var pendingWipe: VieNeuModelChoice?
    @State var wipingModel: VieNeuModelChoice?

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
        .confirmationDialog(
            "Xoá tất cả dữ liệu \(pendingWipe?.label ?? "")?",
            isPresented: Binding(get: { pendingWipe != nil }, set: { if !$0 { pendingWipe = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá tất cả", role: .destructive) { commitWipe() }
            Button("Huỷ", role: .cancel) { pendingWipe = nil }
        } message: {
            Text(wipeMessage)
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

    // MARK: - Xoá cả gói

    private var wipeMessage: String {
        switch pendingWipe {
        case .nano:
            return "Xoá model Nano, gói nhân bản Nano và gói Tăng tốc Core ML (\(Self.size(nanoWipeBytes))). Giọng nhân bản giữ nguyên; tải lại ở sheet chọn giọng."
        case .turbo:
            let count = snapshot?.turboVoiceCount ?? 0
            return "Xoá model Turbo và \(count) giọng Turbo đã tải (\(Self.size(snapshot?.turboRemovableBytes ?? 0))). Giọng nhân bản giữ nguyên; tải lại ở sheet chọn giọng."
        case nil:
            return ""
        }
    }

    /// Xoá cả gói (đã xác nhận): service tự từ chối khi đang tải / đang chuẩn bị Core ML và tự dừng trình đọc đang dùng
    /// model đó; View báo kết quả bằng toast rồi đọc lại số liệu.
    private func commitWipe() {
        guard let model = pendingWipe, wipingModel == nil else { return }
        pendingWipe = nil
        wipingModel = model
        VieNeuVoicePreviewPlayer.shared.stop()
        Task {
            do {
                switch model {
                case .nano: try await VieNeuModelDataRemover.deleteNano()
                case .turbo: try await VieNeuModelDataRemover.deleteTurbo()
                }
                ToastManager.shared.show(message: "Đã xoá tất cả dữ liệu \(model.label).", type: .success)
            } catch {
                ToastManager.shared.show(message: "Xoá dữ liệu \(model.label) thất bại: \(error.localizedDescription)", type: .error)
            }
            accelerator.refresh()
            await reloadSnapshot()
            wipingModel = nil
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
