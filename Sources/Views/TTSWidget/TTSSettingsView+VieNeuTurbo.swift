import SwiftUI

/// Phần **VieNeu Turbo** của màn Cài đặt TTS: hàng tải model 188 MB tại chỗ, Picker giọng gộp Nano + Turbo (1.3.897: model
/// đi theo giọng), cảnh báo tốc độ và nút "?" của section "Cấu hình giọng nói".
///
/// Tách file riêng vì `TTSSettingsView.swift` là file legacy chỉ được giảm dòng — ở đó chỉ đổi đúng một dòng (selection
/// của Picker "Trình đọc"); `+VieNeu` / `+Voice` chỉ thêm lời gọi tới các khối ở đây.
///
/// Bên trong vẫn là `tool == "vieneu"`: model là phần của giọng đang chọn (`VieNeuVoiceSelection`).
extension TTSSettingsView {
    /// Turbo đang là trình đọc (model **hiệu lực**, đã xét máy có đủ file).
    var isVieNeuTurboSelected: Bool {
        ttsManager.tool == "vieneu" && VieNeuModelChoice.current == .turbo
    }

    /// Máy đủ file để đọc Turbo — quyết định nhóm "Turbo" của Picker giọng. Đọc trạng thái quan sát được của
    /// `VieNeuTurboLab` để tải xong là nhóm hiện ra ngay.
    var vieNeuTurboReady: Bool {
        VieNeuTurboRuntime.isAvailable && VieNeuTurboLab.shared.isTurboReady
    }

    // MARK: - Picker "Trình đọc"

    /// Selection của Picker "Trình đọc" — từ 1.3.897 chỉ còn **một** mục VieNeu (`tool = "vieneu"`), model đi theo giọng.
    var readerPickerSelection: Binding<String> {
        Binding(get: { ttsManager.tool }, set: { ttsManager.tool = $0 })
    }

    // MARK: - Tải model

    /// Hàng tải model Turbo ngay dưới Picker, khi máy chưa có. Tải **tại chỗ** qua `VieNeuTurboLab.shared.downloadAll()`
    /// (cùng lượt tải với màn thử: rời màn vẫn tải tiếp) — trong lúc tải, trình đọc đang chọn vẫn đọc bình thường.
    @ViewBuilder
    var vieNeuTurboDownloadRow: some View {
        let lab = VieNeuTurboLab.shared
        if VieNeuTurboRuntime.isAvailable && !lab.isTurboReady {
            if lab.isDownloading {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Đang tải model VieNeu Turbo", systemImage: "arrow.down.circle")
                            .foregroundColor(.accentColor)
                        Spacer()
                        if lab.downloadTotalBytes > 0 {
                            Text(Self.megabytes(lab.downloadedBytes, of: lab.downloadTotalBytes))
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let fraction = lab.downloadFraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                    // Trước GGUF còn bộ phiên âm (khi máy chưa có Nano) và danh sách giọng — nói rõ đang tải gì.
                    if lab.downloadTotalBytes != VieNeuTurboModelStore.modelByteCount, !lab.downloadMessage.isEmpty {
                        Text(lab.downloadMessage)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Button {
                    lab.downloadAll()
                } label: {
                    Label("Tải model VieNeu Turbo (188 MB)", systemImage: "arrow.down.circle")
                }
                if let error = lab.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// "74 / 188 MB" (MB thập phân — GGUF 187.917.664 byte hiện là 188 MB như nhãn nút).
    static func megabytes(_ completed: Int64, of total: Int64) -> String {
        String(format: "%.0f / %.0f MB", Double(completed) / 1_000_000, Double(total) / 1_000_000)
    }

    // MARK: - Giọng đọc

    /// Picker giọng VieNeu gộp hai model (1.3.897): chọn giọng Nano ⇒ trình đọc chạy Nano, giọng Turbo ⇒ Turbo. Mỗi nhóm
    /// chỉ hiện khi model của nó đã tải đủ. Tag = `VieNeuVoiceSelection.key` ("nano:<tên>" / "turbo:<id>").
    @ViewBuilder
    var vieNeuMergedVoicePicker: some View {
        let lab = VieNeuTurboLab.shared
        let turboCustom = VieNeuTurboCustomVoiceRepository.shared.voices
        if availableVoices.isEmpty && !vieNeuTurboReady {
            Text("Chưa tải giọng VieNeu nào")
                .foregroundColor(.secondary)
        } else {
            Picker("Giọng đọc VieNeu", selection: vieNeuVoiceSelectionBinding) {
                if !availableVoices.isEmpty {
                    Section("Nano") {
                        ForEach(availableVoices, id: \.name) { voice in
                            Text(voice.name).tag(VieNeuVoiceSelection(model: .nano, voiceId: voice.name).key)
                        }
                    }
                }
                if vieNeuTurboReady {
                    Section("Turbo") {
                        ForEach(turboCustom) { record in
                            Text(record.name).tag(VieNeuVoiceSelection(model: .turbo, voiceId: record.id).key)
                        }
                        ForEach(lab.voices) { voice in
                            turboVoiceOption(voice, defaultVoiceId: lab.defaultVoiceId)
                        }
                    }
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Đọc: model hiệu lực + giọng đang đọc; ghi: `TTSManager.selectVieNeuVoice` (đổi model thì nạp lại engine).
    private var vieNeuVoiceSelectionBinding: Binding<String> {
        Binding(
            get: { VieNeuVoiceSelection(model: VieNeuModelChoice.current, voiceId: ttsManager.selectedVoice).key },
            set: { raw in
                guard let selection = VieNeuVoiceSelection(storageValue: raw) else { return }
                ttsManager.selectVieNeuVoice(selection)
            }
        )
    }

    /// Một mục giọng Turbo: tên (bỏ ⭐) + dòng phụ "Nam · Bắc · tự nhiên" (thêm "· mặc định" cho giọng mặc định của manifest).
    private func turboVoiceOption(_ voice: VieNeuTurboVoiceManifest.Voice, defaultVoiceId: String?) -> some View {
        let notes = [voice.traitsSummary, voice.id == defaultVoiceId ? "mặc định" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        return VStack(alignment: .leading) {
            Text(voice.name)
            if !notes.isEmpty {
                Text(notes)
            }
        }
        .tag(VieNeuVoiceSelection(model: .turbo, voiceId: voice.id).key)
    }

    // MARK: - Cấu hình giọng nói

    /// Dưới thanh Tốc độ khi giọng đang chọn là Turbo: **chỉ** cảnh báo cam khi vượt mức Turbo tổng hợp kịp. Giải thích
    /// (Turbo không có tốc độ tổng hợp) nằm sau nút "?" của section (`voiceSectionHelp`).
    @ViewBuilder
    var vieNeuTurboSpeedNotes: some View {
        let limit = VieNeuTurboTTSService.realtimeSpeedLimit
        // `+ 0.001`: bước 0,1 cộng dồn số thực ra kiểu 2.0000000000000004 — không được tính là vượt mức.
        if ttsManager.speed > limit + 0.001 {
            Label {
                Text("Turbo theo kịp tới khoảng \(Self.speedText(limit))×. Ở \(Self.speedText(ttsManager.speed))× có thể hụt tiếng, nhất là khi máy nóng.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            // `.orange` literal có chủ ý (như cảnh báo tốc độ nghe của Nano): màu nhấn do người dùng chọn có thể là cam.
            .foregroundColor(.orange)
        }
    }

    /// Nút "?" của section "Cấu hình giọng nói" khi trình đọc là VieNeu.
    var voiceSectionHelp: some View {
        SectionHelpButton(accessibilityLabel: "Giải thích Cấu hình giọng nói", paragraphs: [
            "Turbo luôn tổng hợp ở tốc độ gốc, tốc độ nghe chỉnh bằng thanh Tốc độ. Turbo theo kịp tới khoảng 2,0×. Giọng Nano có thêm Tốc độ tổng hợp.",
            "Tốc độ tổng hợp (Nano): model nói nhanh hơn, máy mát hơn. 1,15× ít lặp chữ nhất, quá 1,25× mất chữ. Tốc độ nghe thực tế = tốc độ tổng hợp × Tốc độ."
        ])
    }

    /// "1,6" — dấu phẩy thập phân như chữ trong mockup.
    static func speedText(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
