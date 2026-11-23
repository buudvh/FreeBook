import SwiftUI
import UniformTypeIdentifiers

/// Danh sách giọng của sheet chọn giọng **vtts Việt–Anh** (2026-11-20, mockup anh Bửu duyệt; giọng tự nhập 1.3.1043 —
/// chép khuôn `NghiVoicePickerList`):
/// - Hàng đầu "Nhập giọng từ file .vtts" ⇒ bộ chọn file (`DocumentPickerPresenter` — `.fileImporter` không trả kết quả
///   trong LiveContainer) ⇒ `VttsImportedVoiceRepository.importVoice` (nạp thử bằng runtime vtts trước khi nhận).
/// - "Có sẵn trong app" (`VttsVoice.bundled`, không tải / xoá), "Giọng của tôi" (giọng tự nhập: dòng phụ dung lượng, nút
///   🗑 cuối hàng hoặc nhấn giữ ⇒ "Xoá giọng", hỏi lại).
/// - Mọi hàng: badge Nhẹ, ▶ thử giọng (`TTSVoicePreviewPlayer`, đường `VttsTTSService`). Chạm hàng = chọn giọng qua
///   `TTSManager.selectVttsVoice` — trình đọc là vtts thì đổi giọng trình đọc, không thì chỉ lưu cho giọng dự phòng (mở
///   từ màn Giọng dự phòng).
/// - Đang tìm thì ẩn hàng nhập file; nhóm không còn giọng khớp thì ẩn cả nhóm.
struct VttsVoicePickerList: View {
    /// Chữ ô tìm (chưa chuẩn hoá).
    let query: String

    @ObservedObject private var ttsManager = TTSManager.shared
    /// Giọng đang chọn. `@State` vì chọn cho giọng dự phòng chỉ ghi `UserDefaults` (không quan sát được) ⇒ dấu ✓ phải tự
    /// đổi; đọc lại mỗi lần danh sách hiện (bài học 1.3.456).
    @State private var selected = VttsVoice.resolve(TTSManager.storedVttsVoice)
    @State private var pendingDeletion: VttsVoice?
    @State private var isShowingFileImporter = false
    @State private var isImporting = false

    private var repository: VttsImportedVoiceRepository { .shared }
    private var preview: TTSVoicePreviewPlayer { .shared }

    var body: some View {
        let normalized = VoiceNameSearch.normalize(query)
        let bundled = VttsVoice.bundled.filter { VoiceNameSearch.matches($0.displayName, normalizedQuery: normalized) }
        let mine = repository.entries.filter {
            VoiceNameSearch.matches($0.voice.displayName, normalizedQuery: normalized)
        }
        ZStack {
            List {
                Group {
                    if normalized.isEmpty {
                        importEntryRow
                    }
                    if !bundled.isEmpty {
                        Section("Có sẵn trong app") {
                            ForEach(bundled) { voice in row(voice, detail: voice.bundledRowDetail) }
                        }
                    }
                    if !mine.isEmpty {
                        Section("Giọng của tôi") {
                            ForEach(mine) { entry in importedRow(entry) }
                        }
                    }
                    if bundled.isEmpty, mine.isEmpty, !normalized.isEmpty {
                        TTSVoiceNoMatchSection(query: query)
                    }
                }
                .glassSheetRows()
            }
            if isImporting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Đang nhập giọng...")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .background {
            DocumentPickerPresenter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false,
                onPick: { urls in handleImportPick(urls) },
                onCancel: nil
            )
        }
        .onAppear {
            selected = ttsManager.vttsDisplayedVoice()
            repository.reload()
        }
        .confirmationDialog(
            "Xoá giọng “\(pendingDeletion?.displayName ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá giọng", role: .destructive) { commitDeletion() }
            Button("Huỷ", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Giọng tự nhập — muốn dùng lại phải nhập file lần nữa.")
        }
    }

    // MARK: - Hàng

    /// Hàng đầu: "Nhập giọng từ file .vtts" (chữ màu nhấn, chevron) — khuôn hàng "Nhập giọng từ file .onnx" của NghiTTS.
    private var importEntryRow: some View {
        Section {
            Button {
                preview.stop()
                isShowingFileImporter = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36)
                    Text("Nhập giọng từ file .vtts")
                        .font(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func importedRow(_ entry: VttsImportedVoiceRepository.Entry) -> some View {
        row(
            entry.voice,
            detail: "Tự nhập · " + VttsImportedVoiceRepository.sizeText(entry.bytes),
            onDelete: { pendingDeletion = entry.voice }
        )
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = entry.voice
            } label: {
                Label("Xoá giọng", systemImage: "trash")
            }
        }
    }

    private func row(_ voice: VttsVoice, detail: String, onDelete: (() -> Void)? = nil) -> TTSVoiceListRow {
        let key = Self.previewKey(voice)
        return TTSVoiceListRow(
            name: voice.displayName,
            detail: detail,
            isReady: true,
            isSelected: selected.id == voice.id,
            primary: preview.isActive(key) ? .stop : .play,
            badge: .light,
            onPrimary: { TTSVoicePreviewToggle.toggle(key: key, request: .vtts(voiceId: voice.id)) },
            onSelect: { select(voice) },
            onDelete: onDelete
        )
    }

    private static func previewKey(_ voice: VttsVoice) -> String {
        "vtts:\(voice.id)"
    }

    // MARK: - Hành động

    private func select(_ voice: VttsVoice) {
        guard selected.id != voice.id else { return }
        selected = voice
        ttsManager.selectVttsVoice(voice)
    }

    private func commitDeletion() {
        guard let voice = pendingDeletion else { return }
        pendingDeletion = nil
        if preview.isActive(Self.previewKey(voice)) { preview.stop() }
        do {
            try repository.delete(voice)
            selected = ttsManager.vttsDisplayedVoice()
            ToastManager.shared.show(message: "Đã xoá giọng \(voice.displayName).", type: .success)
        } catch {
            ToastManager.shared.show(message: "Lỗi xoá giọng \(voice.displayName): \(error.localizedDescription)", type: .error)
        }
    }

    private func handleImportPick(_ urls: [URL]) {
        isShowingFileImporter = false
        guard let url = urls.first else { return }
        isImporting = true
        Task { @MainActor in
            let outcome = await repository.importVoice(from: url)
            isImporting = false
            switch outcome {
            case .success(let voice):
                ToastManager.shared.show(message: "Đã nhập giọng \(voice.displayName).", type: .success)
            case .failure(let error):
                ToastManager.shared.show(message: error.localizedDescription, type: .error)
            }
        }
    }
}
