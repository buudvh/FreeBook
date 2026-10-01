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
    /// Đọc lại ba thiết lập VieNeu **thẳng từ `UserDefaults`** mỗi lần mở màn Cài đặt.
    ///
    /// **Vì sao cần** (lỗi 1.3.456 — *"vào cài đặt TTS từ tab setting thì luôn hiển thị giá trị mặc định
    /// (bật tiết kiệm pin) dù đã thay đổi cài đặt rồi"*): ba giá trị này là `@State` của
    /// `TTSSettingsView`, nên chỉ được khởi tạo **một lần** lúc View dựng — mà lúc đó
    /// `VieNeuTTSService.shared` có thể chưa tồn tại ⇒ `?? true` rơi về mặc định "Tiết kiệm pin: BẬT".
    /// Trước đây chỉ `vieNeuSelectedMode` được làm mới (trong `.onChange(of: ttsManager.tool)`), còn
    /// `vieNeuPowerSaving` / `vieNeuThreadCount` **không bao giờ** được làm mới ⇒ mở lại màn là thấy sai.
    ///
    /// Đọc thẳng `UserDefaults` (không qua service) nên kết quả đúng bất kể service đã dựng chưa.
    func refreshVieNeuSettings() {
        vieNeuPowerSaving = VieNeuSynthesisPolicy.isPowerSaving(.standard)
        vieNeuThreadCount = Int(VieNeuSynthesisPolicy.threadCount(from: .standard))
        vieNeuSelectedMode = VieNeuSynthesisPolicy.preferredMode(from: .standard)
    }

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
        // 1. Tiết kiệm pin (LÊN TRÊN): bật ⇒ ghim "Cân bằng" + 2 luồng, khoá 2 picker bên dưới.
        Toggle("Tiết kiệm pin", isOn: Binding(
            get: { vieNeuPowerSaving },
            set: { newValue in
                vieNeuPowerSaving = newValue
                VieNeuTTSService.shared?.powerSaving = newValue
                if !newValue { vieNeuSelectedMode = nil }   // tắt ⇒ về "Tự động"
            }
        ))
        // 2. Chế độ tạo audio
        Picker("Chế độ tạo audio", selection: Binding(
            get: { vieNeuPowerSaving ? VieNeuSynthesisPolicy.Mode?.some(.fast) : vieNeuSelectedMode },
            set: { vieNeuSelectedMode = $0 }
        )) {
            Text("Tự động").tag(VieNeuSynthesisPolicy.Mode?.none)
            ForEach(VieNeuSynthesisPolicy.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(VieNeuSynthesisPolicy.Mode?.some(mode))
            }
        }
        .pickerStyle(.menu)
        .disabled(vieNeuPowerSaving)
        // Đẩy lựa chọn xuống service. Setter của `preferredMode` gọi `engine.setRequestedMode(...)` nên có
        // hiệu lực **ngay**. UI giữ giá trị trong `@State` vì `VieNeuTTSService` không `@Observable`.
        .onChange(of: vieNeuSelectedMode) { _, newValue in
            VieNeuTTSService.shared?.preferredMode = newValue
        }
        // 3. Số luồng tổng hợp (2/3/4, KHÔNG kèm ngoặc bổ nghĩa).
        Picker("Số luồng tổng hợp", selection: Binding(
            get: { vieNeuPowerSaving ? 2 : vieNeuThreadCount },
            set: { vieNeuThreadCount = $0; VieNeuTTSService.shared?.threadCount = $0 }
        )) {
            ForEach([2, 3, 4], id: \.self) { count in
                Text("\(count) luồng").tag(count)
            }
        }
        .pickerStyle(.menu)
        .disabled(vieNeuPowerSaving)
        // 4. Giải thích — LUÔN hiển thị (nối thuyết minh khi bật Tiết kiệm pin).
        Text("Số luồng càng nhiều càng khó gây ra trường hợp phải chờ đợi giữa hai đoạn nghe nhưng dễ nóng máy và hết pin nhanh. Số luồng áp dụng sau khi nạp lại engine (mở lại app hoặc đổi engine)." + (vieNeuPowerSaving ? " Đang bật Tiết kiệm pin: cố định chế độ Cân bằng + 2 luồng để máy mát và ít tốn pin; chất lượng giọng thấp hơn." : ""))
            .font(.caption)
            .foregroundColor(.secondary)
        // 5. Lối vào **giọng nhân bản**.
        //
        // Chỉ hiện khi đã có `voices_v3_nano.json`: màn đó đọc catalog để dựng danh sách, mà thiếu file
        // ấy thì nó chỉ hiện được một câu báo lỗi — vào được cũng không làm gì. Điều kiện **không** gồm
        // gói graph clone: màn đó tự có nút tải gói ấy, nên chặn ở đây là chặn đúng đường tải.
        if vieNeuModelReady {
            NavigationLink(destination: VieNeuVoiceLibraryView()) {
                Label("Giọng của tôi (nhân bản từ audio mẫu)", systemImage: "person.wave.2")
            }
        }
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
