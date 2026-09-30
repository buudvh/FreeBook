import SwiftUI

/// Phần **VieNeu-TTS** của màn Cài đặt TTS.
///
/// Tách khỏi `TTSSettingsView.swift` vì file đó có baseline **519** dòng và lượt nối 2b đẩy nó lên
/// **540** — tức một vi phạm kiến trúc mới. Đây là cùng khuôn đã dùng cho `VieNeuTTSTestView+Sections`.
///
/// Vì tách file, `availableVoices` của view chính phải hạ từ `private` xuống `internal` (Swift giới hạn
/// `private` theo file).
extension TTSSettingsView {
    /// Model VieNeu đã tải đủ chưa — quyết định có cho chọn `vieneu` trong Picker hay không.
    ///
    /// Quyết định grill #2: **chặn ở Picker**. Chọn rồi mới biết không dùng được là trải nghiệm tệ, mà
    /// model thì 343 MB nên không thể tải ngầm.
    var vieNeuModelReady: Bool {
        VieNeuTTSService.shared?.modelStore.isReady ?? false
    }

    /// Dòng Picker cho VieNeu + lối tải model khi còn thiếu.
    @ViewBuilder
    var vieNeuPickerRows: some View {
        if vieNeuModelReady {
            Text("VieNeu-TTS v3 Nano (Offline)").tag("vieneu")
        }
    }

    /// Lối tải model, hiện ngay dưới Picker khi chưa có model.
    @ViewBuilder
    var vieNeuDownloadRow: some View {
        if !vieNeuModelReady {
            NavigationLink(destination: VieNeuTTSTestView()) {
                Label("Tải model VieNeu-TTS (343 MB)", systemImage: "arrow.down.circle")
            }
        }
    }

    /// Danh sách giọng của VieNeu.
    ///
    /// **Không** lọc theo `isModelDownloaded` như NghiTTS: 11 giọng của VieNeu nằm chung trong
    /// `voices_v3_nano.json` của bộ model, không phải file rời cho từng giọng — nên `isReady` đã bảo đảm
    /// có đủ giọng rồi.
    @ViewBuilder
    var vieNeuVoicePicker: some View {
        if availableVoices.isEmpty {
            Text("Chưa đọc được danh sách giọng VieNeu")
                .foregroundColor(.secondary)
        } else {
            Picker("Giọng đọc VieNeu", selection: $ttsManager.selectedVoice) {
                ForEach(availableVoices, id: \.name) { voice in
                    Text(voice.name).tag(voice.name)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Nạp giọng theo engine đang chọn. VieNeu lấy từ catalog riêng (`voices_v3_nano.json`), NghiTTS lấy
    /// qua `nghiTTSClient`.
    ///
    /// **Phải gọi lại mỗi khi `tool` đổi** — và đây là chỗ dễ sót nhất: `availableVoices` là **một** mảng
    /// dùng chung cho hai engine có sẵn, nên nếu không nạp lại thì đổi từ VieNeu sang NghiTTS sẽ giữ
    /// nguyên tên giọng của VieNeu, rồi nhánh NghiTTS lọc `isModelDownloaded` trên những tên đó ⇒ hiện
    /// "Chưa tải giọng đọc NghiTTS nào" dù model đã có. Lỗi có sẵn từ trước nhưng chỉ lộ ra khi có engine
    /// thứ hai cùng dùng mảng này.
    func loadVoicesForCurrentTool() async {
        if ttsManager.tool == "vieneu" {
            availableVoices = (try? VieNeuTTSService.shared?.availableVoices()) ?? []
        } else {
            availableVoices = (try? await ttsManager.nghiTTSClient?.getAllVoices(forceRefresh: false))
                ?? NghiTTSClient.fallbackVietnameseVoices
        }
    }

    /// Khối **quản lý riêng của trình đọc** cho VieNeu — hiện thẳng trong Section 3 của màn Cài đặt.
    ///
    /// **Chỉ chứa thứ thật sự thuộc về engine**: chế độ chất lượng (`fast`/`high`/tự động). Các tham số
    /// *hiệu năng* (số đoạn tải trước, độ dài phân đoạn, ngưỡng nạp bộ đệm) nằm ở Section 5
    /// "Tải trước dữ liệu" — xem `vieNeuPrefetchSection`. Tách như vậy để **không có hai nguồn sự thật**:
    /// trước lượt 1.3.435 số đoạn tải trước xuất hiện ở **cả** Section 3 **và** Section 5.
    ///
    /// **Tốc độ và cao độ không lặp lại ở đây**: chúng đã có slider ở Section 4, chỉ khác khoá lưu
    /// (`vieneuRate`/`vieneuPitch` nhờ `persistSpeed`/`persistPitch`). Lặp lại sẽ tạo hai nguồn sự thật.
    @ViewBuilder
    var vieNeuReaderSection: some View {
        Picker("Tốc độ tạo audio", selection: $vieNeuSelectedMode) {
            Text("Tự động (theo tốc độ máy)").tag(VieNeuSynthesisPolicy.Mode?.none)
            ForEach(VieNeuSynthesisPolicy.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(VieNeuSynthesisPolicy.Mode?.some(mode))
            }
        }
        .pickerStyle(.menu)
        // Đẩy lựa chọn xuống service. Setter của `preferredMode` gọi `engine.setRequestedMode(...)` nên có
        // hiệu lực **ngay**, không phải chờ `prepare()`. Nhưng UI vẫn phải giữ giá trị trong `@State` vì
        // `VieNeuTTSService` là class thường (không `@Observable`) — SwiftUI không thấy nó đổi.
        .onChange(of: vieNeuSelectedMode) { _, newValue in
            VieNeuTTSService.shared?.preferredMode = newValue
        }
        // "Tiết kiệm pin": ép `fast` (giảm ~2× tính toán) + 2 luồng ⇒ mát máy/pin hơn, chất lượng thấp hơn.
        Toggle("Tiết kiệm pin (giọng nhanh hơn, mát máy hơn)", isOn: Binding(
            get: { vieNeuPowerSaving },
            set: { vieNeuPowerSaving = $0; VieNeuTTSService.shared?.powerSaving = $0 }
        ))
        Picker("Số luồng tổng hợp", selection: Binding(
            get: { vieNeuThreadCount },
            set: { vieNeuThreadCount = $0; VieNeuTTSService.shared?.threadCount = $0 }
        )) {
            Text("2 luồng (mát máy hơn)").tag(2)
            Text("4 luồng (nhanh hơn)").tag(4)
        }
        .pickerStyle(.menu)
        Text("Số luồng áp dụng sau khi nạp lại engine (mở lại app hoặc đổi engine). Nhiều luồng = tổng hợp nhanh hơn nhưng nóng máy/tốn pin hơn; ít luồng thì mát hơn, chậm hơn.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    /// Khối "Tải trước dữ liệu" của VieNeu (Section 5).
    ///
    /// **Vì sao phải có nhánh riêng**: Section 5 phân nhánh theo engine và **thiếu nhánh `vieneu`**, nên
    /// VieNeu rơi vào nhánh `else` — nhánh **extension** — và hiện *"Số đoạn tải trước (Extension TTS)"*
    /// trỏ vào `extPrefetchCount` cùng *"Độ dài đoạn văn (Extension TTS)"* trỏ vào `chunkLength`. Đó chính
    /// là "2 chỗ config số đoạn tải trước" và nhãn sai. Khoá đúng là `vieneuPrefetchCount` / `vieneuChunk`.
    ///
    /// **Độ dài phân đoạn CÓ tác dụng với VieNeu** (không phải thừa): `TTSManager.playbackParagraphs`
    /// (`:801-803`) cho `vieneu` đi qua `NghiUtteranceSegmenter.expand(baseParagraphs, maximumLength:
    /// chunkLength)` giống Piper, nên nó quyết định cách chia đoạn để đọc.
    @ViewBuilder
    var vieNeuPrefetchSection: some View {
        Stepper(value: $ttsManager.vieneuPrefetchCount, in: 2...10) {
            HStack {
                Text("Số đoạn tải trước (VieNeu):")
                Spacer()
                Text("\(ttsManager.vieneuPrefetchCount) đoạn")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        Stepper(value: $ttsManager.chunkLength, in: 50...500, step: 10) {
            HStack {
                Text("Độ dài phân đoạn (VieNeu):")
                Spacer()
                Text("\(ttsManager.chunkLength) ký tự")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Stepper(
                value: Binding(
                    get: { ttsManager.vieneuSafeCachedTimeThreshold },
                    set: { ttsManager.setVieNeuSafeCachedTimeThreshold($0) }
                ),
                in: 4...20,
                step: 1
            ) {
                HStack {
                    Text("Ngưỡng nạp bộ đệm (VieNeu):")
                    Spacer()
                    Text("\(Int(ttsManager.vieneuSafeCachedTimeThreshold))s")
                        .font(.system(.body, design: .monospaced))
                }
            }
            Text("Tự động tổng hợp thêm âm thanh khi thời lượng đệm âm thanh liên tục còn lại giảm xuống dưới \(Int(ttsManager.vieneuSafeCachedTimeThreshold)) giây.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
