import SwiftUI

/// Màn tải/xoá bộ model VieNeu-TTS v3 Turbo (~274 MB).
///
/// Tách khỏi `TTSModelManagerView` vì file đó đã ở đúng baseline 478 dòng của
/// `check_architecture.py` và chỉ được phép giảm.
///
/// Bộ model gồm 11 file phải nằm **cùng một thư mục** và **không được đổi tên** (hai graph tham
/// chiếu file weight bằng tên trần) — chi tiết ở `VieNeuModelFile`.
struct VieNeuModelManagerView: View {
    @ObservedObject private var ttsManager = TTSManager.shared

    @State private var isDownloading = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""
    @State private var errorMessage: String?
    @State private var installedBytes: Int64 = 0
    @State private var isInstalled = false
    @State private var downloadTask: Task<Void, Never>?

    private var store: VieNeuModelStore? { VieNeuModelStore.shared }

    var body: some View {
        Form {
            statusSection
            actionSection
            if isInstalled {
                voicesSection
            }
            noteSection
        }
        .navigationTitle("Model VieNeu-TTS")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshState)
    }

    // MARK: - Các section

    @ViewBuilder
    private var statusSection: some View {
        Section("Trạng thái") {
            HStack {
                Text("Bộ model")
                Spacer()
                Text(isInstalled ? "Đã cài" : "Chưa cài")
                    .foregroundColor(isInstalled ? .green : .secondary)
            }
            if installedBytes > 0 {
                HStack {
                    Text("Dung lượng")
                    Spacer()
                    Text(Self.formatBytes(installedBytes)).foregroundColor(.secondary)
                }
            }
            if !isInstalled {
                HStack {
                    Text("Cần tải")
                    Spacer()
                    Text(Self.formatBytes(VieNeuModelDownloader.totalExpectedBytes))
                        .foregroundColor(.secondary)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        Section {
            if isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress)
                    Text(statusMessage.isEmpty ? "Đang tải…" : statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("\(Int(progress * 100))%")
                        .font(.footnote.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Button(role: .destructive) {
                    downloadTask?.cancel()
                    downloadTask = nil
                    isDownloading = false
                    statusMessage = "Đã dừng. Lần tải sau sẽ tiếp tục từ chỗ đang dở."
                } label: {
                    Text("Dừng tải")
                }
            } else {
                Button {
                    startDownload()
                } label: {
                    Text(isInstalled ? "Tải lại phần còn thiếu" : "Tải bộ model (~274 MB)")
                }
                .disabled(store == nil)

                if isInstalled || installedBytes > 0 {
                    Button(role: .destructive) {
                        deleteModel()
                    } label: {
                        Text("Xoá bộ model")
                    }
                }
            }
        } footer: {
            Text("Tải một lần, dùng chung cho cả 20 giọng. Bị ngắt giữa đường thì lần sau tiếp tục từ chỗ đang dở, không tải lại từ đầu.")
        }
    }

    @ViewBuilder
    private var voicesSection: some View {
        let voices = ttsManager.vieNeuVoices
        if !voices.isEmpty {
            Section("Giọng có sẵn (\(voices.count))") {
                ForEach(voices) { voice in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.displayLabel)
                        if !voice.description.isEmpty {
                            Text(voice.description)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        Section("Ghi chú") {
            Text("VieNeu đọc **tiếng Anh gốc**, không phiên âm sang âm Việt như Piper, nên tên riêng và thuật ngữ nghe tự nhiên hơn.")
                .font(.footnote)
            Text("Âm thanh 48 kHz và model nặng hơn Piper, nên tốn pin và toả nhiệt nhiều hơn khi nghe liên tục nhiều giờ.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("Chọn engine ở Cài đặt TTS → Trình đọc → Engine offline.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Hành động

    private func refreshState() {
        guard let store else {
            errorMessage = "Không truy cập được thư mục Application Support."
            return
        }
        isInstalled = store.isInstalled
        installedBytes = store.bytesInstalled()
    }

    private func startDownload() {
        guard let store else { return }
        errorMessage = nil
        isDownloading = true
        progress = 0
        statusMessage = "Chuẩn bị…"

        let downloader = VieNeuModelDownloader(store: store)
        downloadTask = Task {
            do {
                try await downloader.download { update in
                    Task { @MainActor in
                        progress = update.fraction
                        statusMessage = update.message
                    }
                }
                await MainActor.run {
                    isDownloading = false
                    downloadTask = nil
                    refreshState()
                    statusMessage = "Đã cài xong."
                    // Dựng lại service để engine nhận model mới mà không cần khởi động lại app.
                    ttsManager.rebuildLocalTTSService()
                }
            } catch is CancellationError {
                await MainActor.run {
                    isDownloading = false
                    downloadTask = nil
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadTask = nil
                    errorMessage = error.localizedDescription
                    refreshState()
                }
            }
        }
    }

    private func deleteModel() {
        guard let store else { return }
        do {
            try store.deleteAll()
            errorMessage = nil
            statusMessage = ""
            refreshState()
            ttsManager.rebuildLocalTTSService()
        } catch {
            errorMessage = "Không xoá được: \(error.localizedDescription)"
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
