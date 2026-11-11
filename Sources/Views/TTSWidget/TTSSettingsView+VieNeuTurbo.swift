import SwiftUI

/// Phần **VieNeu Turbo** của màn Cài đặt TTS (đợt B, theo mockup đã duyệt): mục Turbo trong Picker "Trình đọc", hàng tải
/// model 188 MB tại chỗ, Picker 25 giọng Turbo chia hai nhóm, hàng "Tổng hợp Turbo" + chú thích, và cảnh báo tốc độ.
///
/// Tách file riêng vì `TTSSettingsView.swift` là file legacy chỉ được giảm dòng — ở đó chỉ đổi đúng một dòng (selection
/// của Picker "Trình đọc"); `+VieNeu` / `+Voice` chỉ thêm lời gọi tới các khối ở đây.
///
/// Bên trong vẫn là `tool == "vieneu"`: model nằm ở `VieNeuModelChoice` (khoá `vieneuModel`), xem doc của type đó.
extension TTSSettingsView {
    /// Turbo đang là trình đọc (model **hiệu lực**, đã xét máy có đủ file).
    var isVieNeuTurboSelected: Bool {
        ttsManager.tool == "vieneu" && VieNeuModelChoice.current == .turbo
    }

    /// Mục Turbo có được hiện trong Picker "Trình đọc" không — như Nano: **chặn ở Picker**, chưa tải model thì không chọn.
    /// Đọc trạng thái quan sát được của `VieNeuTurboLab` để tải xong là mục hiện ra ngay.
    var vieNeuTurboReady: Bool {
        VieNeuTurboRuntime.isAvailable && VieNeuTurboLab.shared.isTurboReady
    }

    // MARK: - Picker "Trình đọc"

    /// Selection của Picker "Trình đọc": hai mục VieNeu (Nano / Turbo) cùng ánh xạ về `tool = "vieneu"` + model đã lưu.
    var readerPickerSelection: Binding<String> {
        Binding(
            get: { VieNeuModelChoice.pickerTag(forTool: ttsManager.tool) },
            set: { selectReader(tag: $0) }
        )
    }

    /// Mục Turbo của Picker "Trình đọc" — ngay dưới Nano.
    var vieNeuTurboPickerRow: some View {
        VStack(alignment: .leading) {
            Text("VieNeu-TTS v3 Turbo (Offline)")
            Text("Hay hơn Nano, tốn CPU khoảng 1,5 lần")
        }
        .tag(VieNeuModelChoice.turboPickerTag)
    }

    /// Đổi trình đọc. Với hai mục VieNeu: ghi model **trước**, rồi mới gán `tool` — `tool.didSet` nạp tham số (giọng theo
    /// khoá của model), bỏ phần đệm và nạp sẵn engine; `persistVoice` cũng đọc model lúc đó. Gán ngược thứ tự là nạp sẵn
    /// nhầm engine và giọng Turbo bị ghi vào khoá giọng của Nano.
    ///
    /// Đang là `vieneu` mà đổi model thì vẫn gán lại `tool = "vieneu"`: Swift chạy `didSet` cả khi giá trị không đổi ⇒ đi
    /// đúng luồng đổi engine. Nhưng `onChange(of: ttsManager.tool)` của màn **không** chạy ⇒ tự làm mới phần của màn.
    private func selectReader(tag: String) {
        guard let model = VieNeuModelChoice(pickerTag: tag) else {
            ttsManager.tool = tag
            return
        }
        let wasVieNeu = ttsManager.tool == "vieneu"
        let unchanged = wasVieNeu && VieNeuModelChoice.current == model
        VieNeuModelChoice.store(model)
        guard !unchanged else { return }
        AppLogger.shared.log("[TTSRoute] chon model VieNeu=\(model.rawValue)")
        ttsManager.tool = "vieneu"
        if wasVieNeu {
            refreshVieNeuSettings()
            Task { await loadVoicesForCurrentTool() }
        }
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

    /// 25 giọng Turbo từ manifest: "Tuyển chọn" (10 giọng ⭐) rồi "Giọng khác". Giọng nhớ riêng với Nano
    /// (`vieneuTurboVoice`). Chọn giọng chưa có file ⇒ tải cặp file vài KB ngay (đoạn đầu tiên cũng tự tải nếu lượt này lỗi).
    @ViewBuilder
    var vieNeuTurboVoicePicker: some View {
        let lab = VieNeuTurboLab.shared
        if lab.voices.isEmpty {
            Text("Chưa đọc được danh sách giọng VieNeu Turbo")
                .foregroundColor(.secondary)
        } else {
            Picker("Giọng đọc VieNeu", selection: $ttsManager.selectedVoice) {
                Section("Tuyển chọn") {
                    ForEach(lab.voices.filter(\.isFeatured)) { voice in
                        turboVoiceOption(voice, defaultVoiceId: lab.defaultVoiceId)
                    }
                }
                Section("Giọng khác") {
                    ForEach(lab.voices.filter { !$0.isFeatured }) { voice in
                        turboVoiceOption(voice, defaultVoiceId: lab.defaultVoiceId)
                    }
                }
            }
            .pickerStyle(.menu)
            .onChange(of: ttsManager.selectedVoice) { _, voiceId in
                VieNeuTurboTTSService.shared?.prefetchVoice(voiceId)
            }
        }
    }

    /// Một mục giọng: tên (bỏ ⭐) + dòng phụ "Nam · Bắc · tự nhiên" (thêm "· mặc định" cho giọng mặc định của manifest).
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
        .tag(voice.id)
    }

    // MARK: - Quản lý riêng của trình đọc

    /// Thay bốn hàng của Nano (Tiết kiệm pin, Chế độ tạo audio, Số luồng, spin ORT): Turbo luôn chạy CPU 2 luồng.
    var vieNeuTurboEngineRow: some View {
        LabeledContent("Tổng hợp Turbo", value: "\(VieNeuTurboTTSService.threadCount) luồng, cố định")
    }

    /// Chú thích cuối nhóm "Quản lý riêng của trình đọc" khi đang chọn Turbo.
    var vieNeuTurboReaderNote: some View {
        Text("iPhone chỉ có 2 lõi hiệu năng, thêm luồng làm Turbo chậm hơn. Máy ấm sau vài phút đọc là bình thường. Giọng nhân bản (Giọng của tôi) chỉ dùng với Nano.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Cấu hình giọng nói

    /// Dưới thanh Tốc độ khi đang chọn Turbo: cảnh báo khi vượt mức Turbo tổng hợp kịp + chú thích thay hàng "Tốc độ tổng
    /// hợp (VieNeu)" (Turbo không có tốc độ tổng hợp).
    @ViewBuilder
    var vieNeuTurboSpeedNotes: some View {
        let limit = VieNeuTurboTTSService.realtimeSpeedLimit
        // `+ 0.001`: bước 0,1 cộng dồn số thực ra 1.4000000000000001 — không được tính là vượt 1,4.
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
        Text("Turbo luôn tổng hợp ở tốc độ gốc, tốc độ nghe chỉnh bằng thanh trên.")
            .font(.caption2)
            .foregroundColor(.secondary)
    }

    /// "1,6" — dấu phẩy thập phân như chữ trong mockup.
    static func speedText(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
