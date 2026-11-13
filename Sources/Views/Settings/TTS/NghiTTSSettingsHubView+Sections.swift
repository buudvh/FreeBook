import SwiftUI

/// Các khối của `NghiTTSSettingsHubView` + số liệu đọc đĩa (dựng ngoài main).
extension NghiTTSSettingsHubView {
    /// Số liệu model NghiTTS đọc từ đĩa — dựng ngoài main (`loadModelSnapshot`), không đọc trong `body`.
    struct ModelSnapshot: Sendable {
        struct VoiceRow: Sendable, Identifiable {
            let id: String
            let name: String
            let bytes: Int64
        }

        var voices: [VoiceRow] = []
        /// Dung lượng thư viện phiên âm (`non-vietnamese-words.plist` + `acronyms.plist`); `nil` = chưa tải.
        var dictionaryBytes: Int64?

        var voiceBytes: Int64 { voices.reduce(Int64(0)) { $0 + $1.bytes } }
    }

    // MARK: - Model

    var modelSection: some View {
        Section {
            LabeledContent("Engine", value: "Piper · ONNX Runtime")
            LabeledContent("Giọng đã tải", value: snapshot.map {
                "\($0.voices.count) giọng · \(Self.size($0.voiceBytes))"
            } ?? "…")
            LabeledContent("Thư viện phiên âm", value: snapshot.map { loaded in
                loaded.dictionaryBytes.map { "Đã tải · \(Self.size($0))" } ?? "Chưa tải"
            } ?? "…")
        } header: {
            SectionHelpHeader("Model", paragraphs: [
                "NghiTTS là các giọng **Piper** chạy trên máy bằng **ONNX Runtime** — mỗi giọng một file model riêng.",
                "Tải / xoá giọng ở **Quản lý Model giọng đọc** bên dưới. Thư viện phiên âm (từ tiếng nước ngoài, viết tắt) tải **cùng từ điển** khi tải giọng NghiTTS đầu tiên."
            ])
        }
    }

    // MARK: - Giọng đã tải

    @ViewBuilder
    var voicesSection: some View {
        if let snapshot, !snapshot.voices.isEmpty {
            Section("Giọng đã tải") {
                ForEach(snapshot.voices) { voice in
                    LabeledContent(voice.name, value: Self.size(voice.bytes))
                }
            }
        }
    }

    // MARK: - Quản lý

    /// Lối vào quản lý — **gom 3 nav cũ ở tab Cài đặt** về một chỗ.
    var managementSection: some View {
        Section {
            NavigationLink(destination: TTSModelManagerView()) {
                Label("Quản lý Model giọng đọc", systemImage: "waveform.and.mic")
            }
            NavigationLink(destination: TTSDictionaryEditView()) {
                Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
            }
            NavigationLink(destination: NghiTTSSettingsView()) {
                Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Quản lý")
        }
    }

    // MARK: - Đọc đĩa (ngoài main)

    nonisolated static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Giọng đã tải (tên theo danh mục `NghiTTSClient.fallbackVietnameseVoices` khi khớp id, không thì id viết lại như
    /// "Giọng đọc tùy chỉnh" của `TTSModelManagerView`) + thư viện phiên âm. `ModelStore` không dựng được ⇒ rỗng.
    nonisolated static func loadModelSnapshot() -> ModelSnapshot {
        guard let store = try? ModelStore() else { return ModelSnapshot() }
        let catalog = Dictionary(
            NghiTTSClient.fallbackVietnameseVoices.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        var result = ModelSnapshot()
        result.voices = store.getLocalVoiceIDs().map { id in
            ModelSnapshot.VoiceRow(
                id: id,
                name: catalog[id] ?? id.replacingOccurrences(of: "_", with: " ").capitalized,
                bytes: store.bytesForVoice(id)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // Hai file của thư viện phiên âm, tải cùng lượt (`NghiTTSClient.downloadDictionaries`) vào `ModelStore.rootURL`;
        // file đầu là dấu "đã tải" (như `TTSSettingsView.hasNoDictionary`).
        let fileManager = FileManager.default
        let urls = ["non-vietnamese-words.plist", "acronyms.plist"].map { store.rootURL.appendingPathComponent($0) }
        if let marker = urls.first, fileManager.fileExists(atPath: marker.path) {
            result.dictionaryBytes = urls.reduce(Int64(0)) { total, url in
                total + Int64(((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0)
            }
        }
        return result
    }
}
