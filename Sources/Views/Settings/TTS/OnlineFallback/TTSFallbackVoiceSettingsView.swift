import SwiftUI

/// Màn **"Giọng dự phòng"** (1.3.945, anh Bửu duyệt mockup: "nav tới màn tương tự chọn engine vieneu hoặc piper tts") — mở từ
/// hàng "Giọng dự phòng" của Cài đặt TTS khi trình đọc là Google / tiện ích (`TTSFallbackVoiceSection`). Dựng y các mục
/// Cài đặt TTS hiện khi chọn engine đó làm trình đọc: Picker "Trình đọc" (Không dùng / NghiTTS / VieNeu) · "Giọng đọc" (cùng
/// hàng + sheet chọn giọng) · "Quản lý riêng của trình đọc" · "Cấu hình giọng nói" (Tốc độ; VieNeu Nano thêm Tốc độ tổng hợp).
///
/// Không có: "Tải trước dữ liệu" (đoạn dự phòng nạp theo cửa sổ của trình đọc online), Cao độ (engine offline không chỉnh
/// được), "Quản lý thay thế ký tự" + "Tiền xử lý số" (chung mọi trình đọc, đã ở Cài đặt TTS), "Đọc lai Nano · Turbo".
///
/// Giọng + cài đặt ở đây là **của chính engine** (chung với lúc engine đó là trình đọc chính). Chọn giọng VieNeu ở đây chỉ lưu
/// lựa chọn, **không** chuyển trình đọc chính sang VieNeu (`vieNeuVoicePickerSheet(selectsForFallback: true)`; trang
/// Cài đặt VieNeu TTS mở từ đây cũng vậy). NghiTTS vốn chỉ ghi `nghittsVoice` khi trình đọc không phải NghiTTS.
struct TTSFallbackVoiceSettingsView: View {
    typealias Engine = TTSOnlineFallbackSettings.Engine

    static let helpParagraphs: [LocalizedStringKey] = [
        "Trình đọc online (Google Cloud TTS, TTS tiện ích) lỗi hoặc máy mất mạng thì app đọc tiếp bằng trình đọc offline chọn ở đây thay vì dừng. **Không dùng** ⇒ lỗi thì tạm dừng đọc như trước.",
        "Đang đọc dự phòng, app thử lại giọng online ở nền (sau 15 giây, giãn dần tới 2 phút; mạng có lại thì thử ngay). Online chạy lại thì tự đọc tiếp bằng giọng online.",
        "Giọng và cài đặt ở đây là **của chính trình đọc đó** — dùng chung khi chọn nó làm trình đọc chính. Đoạn dự phòng chia theo độ dài đoạn của trình đọc online."
    ]

    @State private var engine: Engine? = TTSOnlineFallbackSettings.engine
    @State private var speed: Double = 1.0
    @State private var synthesisSpeed: Double = 1.0
    @StateObject private var japaneseFlags = VieNeuJapaneseFlags()
    @State private var showingVieNeuPicker = false
    @State private var nghiPicker: TTSVoiceEngine?
    /// Tăng khi sheet chọn giọng VieNeu đóng ⇒ đọc lại model (Nano / Turbo quyết hàng Tốc độ tổng hợp).
    @State private var selectionToken = 0

    var body: some View {
        Form { Group {
            Section {
                Picker("Trình đọc", selection: engineBinding) {
                    Text("Không dùng").tag(Engine?.none)
                    ForEach(Engine.allCases) { option in
                        Text(option.pickerTitle).tag(Engine?.some(option))
                    }
                }
                .pickerStyle(.menu)
            } header: {
                SectionHelpHeader("Trình đọc dự phòng", paragraphs: Self.helpParagraphs)
            }
            if let engine {
                Section("Giọng đọc") { voiceRow(engine) }
                managementSection(engine)
                voiceConfigSection(engine)
            }
        }.glassSheetRows() }
        .backPageTitle("Giọng dự phòng")
        .onAppear(perform: reload)
        .vieNeuVoicePickerSheet(isPresented: $showingVieNeuPicker, selectsForFallback: true)
        .ttsVoicePickerSheet(engine: $nghiPicker)
        .onChange(of: showingVieNeuPicker) { _, presented in
            if !presented { selectionToken += 1 }
        }
    }

    // MARK: - Trạng thái

    private var engineBinding: Binding<Engine?> {
        Binding(
            get: { engine },
            set: { newValue in
                TTSOnlineFallbackSettings.engine = newValue
                AppLogger.shared.log("[TTSFallback] Chọn trình đọc dự phòng: \(newValue?.title ?? "không dùng")")
                reload()
            }
        )
    }

    private func speedBinding(_ engine: Engine) -> Binding<Double> {
        Binding(
            get: { speed },
            set: { newValue in
                speed = newValue
                TTSOnlineFallbackSettings.setPlaybackSpeed(newValue, for: engine)
            }
        )
    }

    /// `@State` chỉ khởi tạo một lần ⇒ đọc lại mỗi lần màn hiện (bài học 1.3.456).
    private func reload() {
        engine = TTSOnlineFallbackSettings.engine
        if let engine { speed = TTSOnlineFallbackSettings.playbackSpeed(for: engine) }
        synthesisSpeed = VieNeuSynthesisPolicy.synthesisSpeed(from: .standard)
        japaneseFlags.refresh()
        if engine == .vieneu { VieNeuVoiceDirectory.shared.reload() }
    }

    private var isNanoSelected: Bool {
        _ = selectionToken
        return VieNeuModelChoice.current == .nano
    }

    // MARK: - Mục

    @ViewBuilder
    private func voiceRow(_ engine: Engine) -> some View {
        switch engine {
        case .vieneu:
            VieNeuVoiceSummaryRow { showingVieNeuPicker = true }
        case .nghitts:
            TTSReaderVoiceSummaryRow(engine: .nghi) { nghiPicker = .nghi }
        }
    }

    @ViewBuilder
    private func managementSection(_ engine: Engine) -> some View {
        switch engine {
        case .vieneu:
            Section {
                NavigationLink(destination: VieNeuTTSSettingsView(selectsForFallback: true)) {
                    Label("Cài đặt VieNeu TTS", systemImage: "waveform.badge.plus")
                }
                Toggle("Áp dụng từ điển phiên âm VieNeu", isOn: $japaneseFlags.dictionaryEnabled)
                if japaneseFlags.dictionaryDownloaded {
                    NavigationLink(destination: VieNeuJapaneseDictionaryView()) {
                        Label("Từ điển phiên âm tiếng Nhật", systemImage: "character.book.closed")
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Chưa tải từ điển tiếng Nhật").font(.subheadline).foregroundColor(.secondary)
                    }
                    Button(action: downloadJapaneseDictionary) {
                        Label("Tải từ điển tiếng Nhật", systemImage: "arrow.down.circle")
                    }
                }
            } header: {
                SectionHelpHeader("Quản lý riêng của trình đọc", paragraphs: [
                    "Nano luôn chạy Cân bằng (8 bước) + 2 luồng, không chờ bận. Turbo luôn 2 luồng trên lõi hiệu năng."
                ])
            }
        case .nghitts:
            Section("Quản lý riêng của trình đọc") {
                NavigationLink(destination: NghiTTSSettingsHubView()) {
                    Label("Cài đặt NghiTTS", systemImage: "waveform.and.mic")
                }
                NavigationLink(destination: NghiTTSSettingsView()) {
                    Label("Cấu hình tiền xử lý & ngắt nghỉ", systemImage: "slider.horizontal.3")
                }
                NavigationLink(destination: TTSDictionaryEditView()) {
                    Label("Từ điển phiên âm cá nhân", systemImage: "character.book.closed")
                }
            }
        }
    }

    private func voiceConfigSection(_ engine: Engine) -> some View {
        Section(header: HStack(spacing: 6) {
            Text("Cấu hình giọng nói")
            if engine == .vieneu {
                SectionHelpButton(accessibilityLabel: "Giải thích Cấu hình giọng nói", paragraphs: [
                    "Turbo luôn tổng hợp ở tốc độ gốc, tốc độ nghe chỉnh bằng thanh Tốc độ. Turbo theo kịp tới khoảng 2,0×. Giọng Nano có thêm Tốc độ tổng hợp.",
                    "Tốc độ tổng hợp (Nano): model nói nhanh hơn, máy mát hơn. 1,15× ít lặp chữ nhất, quá 1,25× mất chữ. Tốc độ nghe thực tế = tốc độ tổng hợp × Tốc độ."
                ])
            }
            Spacer()
            Button(action: { reset(engine) }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Đặt lại")
                }
                .font(.caption)
                .foregroundColor(.white)
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Stepper(value: speedBinding(engine), in: TTSSpeedPolicy.playbackRange, step: 0.1) {
                    HStack {
                        Text("Tốc độ:")
                        Spacer()
                        Text(String(format: "%.1fx", speed))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                Slider(value: speedBinding(engine), in: TTSSpeedPolicy.playbackRange, step: 0.1)
            }
            if engine == .vieneu && isNanoSelected {
                synthesisSpeedRow
            }
        }
    }

    /// Như hàng "Tốc độ tổng hợp (VieNeu)" của Cài đặt TTS — cùng khoá `VieNeuSynthesisPolicy.synthesisSpeedKey`.
    private var synthesisSpeedRow: some View {
        let effective = synthesisSpeed * speed
        return VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $synthesisSpeed, in: VieNeuSynthesisPolicy.synthesisSpeedRange, step: 0.05) {
                HStack {
                    Text("Tốc độ tổng hợp (VieNeu):")
                    Spacer()
                    Text(String(format: "%.2fx", synthesisSpeed))
                        .font(.system(.body, design: .monospaced))
                }
            }
            Slider(value: $synthesisSpeed, in: VieNeuSynthesisPolicy.synthesisSpeedRange, step: 0.05)
            HStack(spacing: 4) {
                Text("Tốc độ nghe thực tế:")
                Text(String(format: "%.2fx", effective))
                    .font(.system(.body, design: .monospaced))
                    // `.orange` literal: cảnh báo, không theo màu nhấn (như Cài đặt TTS).
                    .foregroundColor(effective > 2.0 ? .orange : .primary)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .onChange(of: synthesisSpeed) { _, newValue in
            UserDefaults.standard.set((newValue * 100).rounded() / 100, forKey: VieNeuSynthesisPolicy.synthesisSpeedKey)
        }
    }

    private func reset(_ engine: Engine) {
        speed = 1.0
        TTSOnlineFallbackSettings.setPlaybackSpeed(1.0, for: engine)
        if engine == .vieneu && isNanoSelected { synthesisSpeed = 1.0 }
    }

    private func downloadJapaneseDictionary() {
        Task {
            do {
                try await VieNeuJapaneseDictionary.shared.downloadInitialDictionary()
                japaneseFlags.refresh()
                ToastManager.shared.show(message: "Tải từ điển tiếng Nhật thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Không thể tải từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }
}
