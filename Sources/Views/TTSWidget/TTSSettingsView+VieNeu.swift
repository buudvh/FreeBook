import Combine
import SwiftUI

/// Phần **VieNeu-TTS** của màn Cài đặt TTS.
///
/// Tách khỏi `TTSSettingsView.swift` vì file đó có baseline **519** dòng và lượt nối 2b đẩy nó lên
/// **540** — tức một vi phạm kiến trúc mới. Cùng khuôn tách `X+Feature.swift` của repo.
extension TTSSettingsView {
    /// Mục VieNeu của Picker "Trình đọc" — **một** mục cho cả Nano lẫn Turbo (1.3.898): model đi theo giọng chọn ở
    /// section "Giọng đọc". Luôn hiện: chưa có model nào thì tải ở sheet chọn giọng (nút ⬇ của từng giọng).
    var vieNeuPickerRows: some View {
        Text("VieNeu-TTS v3 (Offline)").tag("vieneu")
    }

    /// Section "Giọng đọc" của VieNeu (1.3.900): **một hàng** tóm tắt giọng đang đọc, bấm ⇒ sheet chọn giọng
    /// (`VieNeuVoicePickerSheet`, gắn ở gốc `Form` qua `showingVieNeuVoicePicker`). Không còn hàng tải model riêng: mỗi
    /// giọng trong sheet có nút tải của nó.
    var vieNeuVoicePicker: some View {
        VieNeuVoiceSummaryRow { showingVieNeuVoicePicker = true }
    }

    /// Đọc lại thiết lập VieNeu **thẳng từ `UserDefaults`** mỗi lần mở màn Cài đặt (lỗi 1.3.456: `@State` chỉ khởi
    /// tạo **một lần** lúc View dựng, nên mở lại màn từ tab Cài đặt thấy giá trị mặc định thay vì giá trị đã lưu).
    ///
    /// Từ 1.3.899 không còn "Tiết kiệm pin" / "Chế độ tạo audio" / "Số luồng tổng hợp" (Nano luôn Cân bằng + 2 luồng).
    func refreshVieNeuSettings() {
        // Tốc độ tổng hợp (1.3.465) — đọc thẳng `UserDefaults`, không qua service.
        vieNeuSynthesisSpeed = VieNeuSynthesisPolicy.synthesisSpeed(from: .standard)
        // Cờ từ điển tiếng Nhật + trạng thái "đã tải từ điển" đọc thẳng kho, cùng lý do.
        vieNeuJapaneseFlags.refresh()
        // Danh sách giọng + trạng thái tải của hàng "Giọng đọc" / sheet chọn giọng (đọc đĩa ngoài main).
        if ttsManager.tool == "vieneu" { VieNeuVoiceDirectory.shared.reload() }
    }

    // MARK: - Tốc độ tổng hợp (1.3.465)

    /// Hàng **"Tốc độ tổng hợp (VieNeu)"** — đặt cạnh thanh Tốc độ trong Section 4 (`VieNeuSynthesisSpeedRow`, dùng chung
    /// với màn Giọng dự phòng từ 1.3.961).
    var vieneuSynthesisSpeedRow: some View {
        VieNeuSynthesisSpeedRow(synthesisSpeed: $vieNeuSynthesisSpeed, playbackSpeed: ttsManager.speed) {
            // Phần đệm đã tổng hợp ở tốc độ cũ phải bị bỏ: đoạn đang phát được giữ nguyên, các đoạn sau
            // nạp lại. Không gọi là nghe sai tốc độ mà không có lỗi gì.
            ttsManager.invalidateVieNeuSynthesisSpeed()
        }
    }

    /// Đưa tốc độ tổng hợp về 1,0× — dùng cho nút "Đặt lại" của Section 4. Hàng tự lưu + bỏ phần đệm khi giá trị đổi.
    func resetVieNeuSynthesisSpeed() {
        // Turbo không có tốc độ tổng hợp (hàng bị ẩn) ⇒ đừng âm thầm đặt lại giá trị của Nano.
        guard ttsManager.tool == "vieneu", !isVieNeuTurboSelected else { return }
        vieNeuSynthesisSpeed = 1.0
    }

    /// Khối **quản lý riêng của trình đọc** cho VieNeu — hiện thẳng trong Section 3 của màn Cài đặt.
    ///
    /// Hàng đầu là lối vào trang **Cài đặt VieNeu TTS** (`VieNeuTTSSettingsView`). Từ 1.3.899 phần còn lại chỉ là công tắc
    /// từ điển phiên âm + lối vào / nút tải từ điển tiếng Nhật, chung cho Nano lẫn Turbo. Đã
    /// bỏ (giá trị cũ giữ nguyên, không đọc nữa): "Tiết kiệm pin" / "Chế độ tạo audio" / "Số luồng tổng hợp" (Nano luôn
    /// Cân bằng 8 bước + 2 luồng — `VieNeuSynthesisPolicy.isPowerSaving`), "Luồng tổng hợp chờ bận (spin)" (luôn tắt),
    /// "Tự động phiên âm tiếng Nhật" (luôn tắt), hàng "Tổng hợp Turbo" và chú thích. Giải thích nằm sau nút "?" của
    /// tiêu đề (`readerManagementHeader`).
    ///
    /// Tham số *hiệu năng* (số đoạn tải trước, độ dài phân đoạn, ngưỡng nạp bộ đệm) nằm ở Section 5 "Tải trước dữ liệu"
    /// — xem `vieNeuPrefetchSection` (một nguồn sự thật, bài học 1.3.435).
    ///
    /// Các hàng dựng ở `VieNeuReaderManagementRows`, dùng chung với màn Giọng dự phòng (1.3.961). Giọng nhân bản ("Giọng
    /// của tôi") nằm trong sheet chọn giọng từ 1.3.900.
    var vieNeuReaderSection: some View {
        VieNeuReaderManagementRows(flags: vieNeuJapaneseFlags)
    }

    /// Tiêu đề Section 3 "Quản lý riêng của trình đọc": nút "?" giải thích công tắc "Phiên âm tiếng Nhật" của trình đọc
    /// đang chọn (1.3.973); VieNeu thêm cấu hình cố định của hai model.
    var readerManagementHeader: some View {
        SectionHelpHeader(
            "Quản lý riêng của trình đọc",
            paragraphs: ttsManager.tool == "vieneu"
                ? VieNeuReaderManagementRows.helpParagraphs
                : [TTSJapaneseTransliterationRow.helpParagraph(forTool: ttsManager.tool)]
        )
    }

    /// Hàng "Phiên âm tiếng Nhật" của Section 3 cho Siri / NghiTTS / Google / tiện ích — VieNeu đã có trong
    /// `VieNeuReaderManagementRows` (dùng chung với màn Giọng dự phòng).
    @ViewBuilder
    var japaneseTransliterationRow: some View {
        if ttsManager.tool != "vieneu" {
            TTSJapaneseTransliterationRow(tool: ttsManager.tool)
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
            Text("Nạp thêm khi đệm còn dưới \(Int(ttsManager.vieneuSafeCachedTimeThreshold)) giây.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

}

/// Trạng thái của phần **tiếng Nhật** cho VieNeu (công tắc "Tự động phiên âm tiếng Nhật" bỏ ở 1.3.899). Công tắc "Đọc tên
/// Nhật theo âm tiết" (1.3.950) từ 1.3.973 là hàng chung "Phiên âm tiếng Nhật" (`TTSJapaneseTransliterationRow`, tự giữ
/// trạng thái, lưu riêng từng trình đọc) nên không còn ở đây.
///
/// **Vì sao không dùng `@AppStorage`**: `TTSSettingsView.swift` chỉ còn **3 dòng** tới trần 519 của
/// `check_architecture.py`, mà hai `@AppStorage` cộng một `@State` là vừa đúng 3 dòng. Gom vào một
/// `ObservableObject` tốn **một** dòng ở file chính và vẫn còn chỗ cho lần sau.
///
/// **Vì sao `refresh()` đọc thẳng `UserDefaults`**: đây là bài học lỗi **1.3.456** — *"vào Cài đặt TTS từ
/// tab Cài đặt thì luôn hiển thị giá trị mặc định dù đã thay đổi cài đặt rồi"*: `@State` chỉ khởi tạo
/// **một lần** lúc View dựng, nên phải làm mới trong `.onAppear` (đi qua `refreshVieNeuSettings()`).
final class VieNeuJapaneseFlags: ObservableObject, @unchecked Sendable {
    /// "Áp dụng từ điển phiên âm VieNeu" — mặc định **TẮT**.
    @Published var dictionaryEnabled: Bool = false {
        didSet { UserDefaults.standard.set(dictionaryEnabled, forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey) }
    }

    /// "Đọc chậm đoạn có tên (Nano)" (1.3.952) — mặc định **Ít nhất 10%** (`VieNeuNameFrameBoost.defaultMode`).
    @Published var nameFrameBoost: VieNeuNameFrameBoost.Mode = VieNeuNameFrameBoost.defaultMode {
        didSet { VieNeuNameFrameBoost.mode = nameFrameBoost }
    }

    /// Đoạn giải thích sau nút "?" của mục Quản lý riêng — dùng chung Cài đặt TTS và màn Giọng dự phòng.
    static let nameFrameBoostHelp: LocalizedStringKey =
        "**Đọc chậm đoạn có tên (Nano)**: đoạn có tên phiên âm theo âm tiết (Gô Cu, Naruto…) được kéo dài tới 30% để không nuốt chữ. **Miễn phí** chỉ dùng phần máy vốn đã tính sẵn, không tốn thêm pin. **Ít nhất 10%** kéo dài thêm cả những đoạn không còn phần miễn phí, tốn thêm chút ít."

    /// Từ điển đã có dưới máy chưa — quyết định hiện lối vào hay hiện cảnh báo + nút tải.
    @Published var dictionaryDownloaded: Bool = false

    func refresh() {
        let defaults = UserDefaults.standard
        dictionaryEnabled = defaults.bool(forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey)
        nameFrameBoost = VieNeuNameFrameBoost.mode
        dictionaryDownloaded = VieNeuJapaneseDictionary.existsOnDisk()
    }
}
