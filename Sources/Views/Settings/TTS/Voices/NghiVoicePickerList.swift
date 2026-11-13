import SwiftUI
import UniformTypeIdentifiers

/// Danh sách giọng của sheet chọn giọng **NghiTTS** (Piper) — thay màn "Quản lý model" cũ (`TTSModelManagerView`).
///
/// - Hàng đầu "Nhập giọng từ file .onnx" ⇒ chọn cặp `.onnx` + `.json` (`NghiVoiceImporter`, chép file ngoài main).
/// - "Giọng đặc sắc" (4 giọng), "Giọng khác" (phần còn lại của danh mục, đã tải lên trước), "Giọng của tôi" (giọng tự nhập).
/// - Đã tải ⇒ ▶ thử giọng (`TTSVoicePreviewPlayer`, engine của trình đọc), dòng phụ dung lượng; chưa tải ⇒ ⬇ tải qua
///   `ModelDownloadCenter` (kèm thư viện phiên âm nếu máy chưa có), tiến độ trên hàng; đích NghiTTS không huỷ được.
/// - Giọng đã tải (danh mục lẫn tự nhập, không lúc đang tải) có nút 🗑 cuối hàng; nút đó hoặc nhấn giữ ⇒ "Xoá giọng" (hỏi
///   lại). Chạm hàng đã tải = chọn giọng (`NghiVoiceDirectory.select`).
/// - Đang tìm thì ẩn hàng nhập file; nhóm không còn giọng khớp thì ẩn cả nhóm.
struct NghiVoicePickerList: View {
    /// Chữ ô tìm (chưa chuẩn hoá).
    let query: String

    @ObservedObject private var downloads = ModelDownloadCenter.shared
    @ObservedObject private var ttsManager = TTSManager.shared
    @State private var pendingDeletion: Voice?
    @State private var isShowingFileImporter = false
    @State private var isImporting = false

    private var directory: NghiVoiceDirectory { .shared }
    private var preview: TTSVoicePreviewPlayer { .shared }

    var body: some View {
        let normalized = VoiceNameSearch.normalize(query)
        let readerVoice = directory.readerVoiceName(tool: ttsManager.tool, selectedVoice: ttsManager.selectedVoice)
        let featured = filtered(directory.featured, normalized)
        let others = filtered(directory.others, normalized)
        let mine = filtered(directory.mine, normalized)
        ZStack {
            List {
                Group {
                    if normalized.isEmpty {
                        importEntryRow
                    }
                    if !featured.isEmpty {
                        Section("Giọng đặc sắc") { rows(featured, readerVoice: readerVoice) }
                    }
                    if !others.isEmpty {
                        Section("Giọng khác") { rows(others, readerVoice: readerVoice) }
                    }
                    if !mine.isEmpty {
                        Section("Giọng của tôi") { rows(mine, readerVoice: readerVoice) }
                    }
                    if featured.isEmpty, others.isEmpty, mine.isEmpty, !normalized.isEmpty {
                        TTSVoiceNoMatchSection(query: query)
                    }
                }
                .glassSheetRows()
            }
            if isImporting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Đang nhập model...")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
        .background {
            DocumentPickerPresenter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "onnx") ?? .data, .json],
                allowsMultipleSelection: true,
                onPick: { urls in handleImportPick(urls) },
                onCancel: nil
            )
        }
        .onAppear { directory.reload() }
        // Lượt giọng tự đọc lại đĩa khi xong (`NghiVoiceDirectory.startDownload`); đây là lưới dự phòng. Theo `isBusy`
        // (Bool), **không** theo `entries`: `entries` đổi ở mỗi nhịp tiến độ.
        .onChange(of: downloads.isBusy) { _, _ in directory.reload() }
        .confirmationDialog(
            "Xoá giọng “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá giọng", role: .destructive) { commitDeletion() }
            Button("Huỷ", role: .cancel) { pendingDeletion = nil }
        } message: {
            if let voice = pendingDeletion, !directory.isCatalogVoice(voice) {
                Text("Giọng tự nhập — muốn dùng lại phải nhập file lần nữa.")
            } else {
                Text("Xoá file model của giọng này khỏi máy. Tải lại bằng nút ⬇ của giọng.")
            }
        }
    }

    // MARK: - Hàng

    /// Hàng đầu: "Nhập giọng từ file .onnx" (chữ màu nhấn, chevron) — khuôn hàng "Nhân bản giọng đọc" của VieNeu.
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
                    Text("Nhập giọng từ file .onnx")
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

    private func filtered(_ voices: [Voice], _ normalized: String) -> [Voice] {
        guard !normalized.isEmpty else { return voices }
        return voices.filter { VoiceNameSearch.matches($0.name, normalizedQuery: normalized) }
    }

    private func rows(_ voices: [Voice], readerVoice: String) -> some View {
        ForEach(voices) { voice in
            row(voice, isSelected: NghiVoiceDirectory.sameName(voice.name, readerVoice))
        }
    }

    @ViewBuilder
    private func row(_ voice: Voice, isSelected: Bool) -> some View {
        let download = downloads.entry(id: ModelDownloadCenter.Target.nghiVoice(voice.id))
        let isDownloading = download?.state.isRunning ?? false
        let bytes = directory.bytes(of: voice)
        let key = Self.previewKey(voice)
        let primary: TTSVoiceListRow.Primary = isDownloading
            ? .downloading
            : (bytes == nil ? .download : (preview.isActive(key) ? .stop : .play))
        let listRow = TTSVoiceListRow(
            name: voice.name,
            detail: bytes.map { NghiVoiceDirectory.sizeText($0) } ?? "chưa tải",
            progress: isDownloading ? download.map { Self.progress(of: $0) } : nil,
            isReady: bytes != nil,
            isSelected: isSelected,
            primary: primary,
            badge: .light,
            onPrimary: { primaryTapped(voice) },
            onSelect: { select(voice) },
            onDelete: bytes != nil && !isDownloading ? { pendingDeletion = voice } : nil
        )
        if bytes != nil {
            listRow.contextMenu {
                Button(role: .destructive) {
                    pendingDeletion = voice
                } label: {
                    Label("Xoá giọng", systemImage: "trash")
                }
            }
        } else {
            listRow
        }
    }

    private static func previewKey(_ voice: Voice) -> String {
        "nghi:\(voice.id)"
    }

    /// Tiến độ theo **byte** của file `.onnx` (1.3.922): "Đang tải 37% · 23 / 61 MB". Chưa biết tổng ⇒ phần trăm theo file
    /// hoặc thanh vô định.
    private static func progress(of entry: ModelDownloadCenter.Entry) -> TTSVoiceListRow.Progress {
        if entry.totalBytes > 0 {
            return TTSVoiceListRow.Progress(text: VieNeuSizeFormatter.progress(entry), fraction: entry.fraction)
        }
        guard let fraction = entry.fraction, fraction > 0 else {
            return TTSVoiceListRow.Progress(text: "Đang tải…", fraction: nil)
        }
        let percent = min(100, max(0, Int((fraction * 100).rounded(.down))))
        return TTSVoiceListRow.Progress(text: "Đang tải \(percent)%", fraction: fraction)
    }

    // MARK: - Hành động

    /// Nút tròn: đang tải ⇒ huỷ tải; đang thử ⇒ dừng; chưa tải ⇒ tải; còn lại ⇒ thử giọng.
    private func primaryTapped(_ voice: Voice) {
        let target = ModelDownloadCenter.Target.nghiVoice(voice.id)
        if downloads.isRunning(id: target) {
            downloads.cancel(id: target)
            return
        }
        guard directory.isDownloaded(voice) else {
            directory.startDownload(voice)
            return
        }
        TTSVoicePreviewToggle.toggle(key: Self.previewKey(voice), request: .nghi(voiceId: voice.id))
    }

    private func select(_ voice: Voice) {
        guard directory.isDownloaded(voice) else { return }
        directory.select(voice)
    }

    private func commitDeletion() {
        guard let voice = pendingDeletion else { return }
        pendingDeletion = nil
        if preview.isActive(Self.previewKey(voice)) { preview.stop() }
        do {
            try directory.delete(voice)
            ToastManager.shared.show(message: "Đã xoá giọng \(voice.name).", type: .success)
        } catch {
            ToastManager.shared.show(message: "Lỗi xoá giọng \(voice.name): \(error.localizedDescription)", type: .error)
        }
    }

    private func handleImportPick(_ urls: [URL]) {
        isShowingFileImporter = false
        switch NghiVoiceImporter.pair(urls) {
        case .failure(let error):
            ToastManager.shared.show(message: error.localizedDescription, type: .error)
        case .success(let pairs):
            isImporting = true
            Task { @MainActor in
                let outcome = await Task.detached(priority: .userInitiated) {
                    NghiVoiceImporter.importPairs(pairs)
                }.value
                isImporting = false
                directory.reload()
                if outcome.errorCount > 0 {
                    ToastManager.shared.show(message: outcome.lastErrorMessage ?? "Lỗi nhập model.", type: .error)
                } else {
                    ToastManager.shared.show(message: "Nhập thành công \(outcome.importedModels) model.", type: .success)
                }
            }
        }
    }
}
