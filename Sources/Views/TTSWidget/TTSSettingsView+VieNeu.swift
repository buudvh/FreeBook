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

    /// Hàng **"Tốc độ tổng hợp (VieNeu)"** — đặt cạnh thanh Tốc độ trong Section 4.
    ///
    /// Khác thanh Tốc độ ở chỗ: giá trị này **đưa vào model** (`secs = exp(log_s)/speed`), không phải
    /// tăng tốc lúc phát. Tốc độ nghe = **tích** hai thanh, nên bắt buộc phải hiện tích đó — nếu không,
    /// kéo thanh này lên 1,8× trong khi thanh Tốc độ đang 1,8× sẽ thành **3,24×** mà người dùng không
    /// hề hay biết (đây là lý do dòng tóm tắt đổi màu khi vượt 2,0×).
    @ViewBuilder
    var vieneuSynthesisSpeedRow: some View {
        let effective = vieNeuSynthesisSpeed * ttsManager.speed
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $vieNeuSynthesisSpeed, in: VieNeuSynthesisPolicy.synthesisSpeedRange, step: 0.05) {
                HStack {
                    Text("Tốc độ tổng hợp (VieNeu):")
                    Spacer()
                    Text(String(format: "%.2fx", vieNeuSynthesisSpeed))
                        .font(.system(.body, design: .monospaced))
                }
            }
            Slider(value: $vieNeuSynthesisSpeed, in: VieNeuSynthesisPolicy.synthesisSpeedRange, step: 0.05)
            HStack(spacing: 4) {
                Text("Tốc độ nghe thực tế:")
                Text(String(format: "%.2fx", effective))
                    .font(.system(.body, design: .monospaced))
                    // `.orange` là màu cảnh báo literal có chủ ý: không dùng `Color.accentColor` vì màu nhấn do người
                    // dùng chọn (có thể chính là Cam hổ phách) ⇒ cảnh báo lẫn với màu nhấn.
                    .foregroundColor(effective > 2.0 ? .orange : .primary)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .onChange(of: vieNeuSynthesisSpeed) { _, newValue in
            // Bước 0,05 cộng dồn số thực ra kiểu 1.1500000000000001 ⇒ làm tròn 2 chữ số khi lưu (1.3.502).
            UserDefaults.standard.set((newValue * 100).rounded() / 100, forKey: VieNeuSynthesisPolicy.synthesisSpeedKey)
            // Phần đệm đã tổng hợp ở tốc độ cũ phải bị bỏ: đoạn đang phát được giữ nguyên, các đoạn sau
            // nạp lại. Không gọi là nghe sai tốc độ mà không có lỗi gì.
            ttsManager.invalidateVieNeuSynthesisSpeed()
        }
    }

    /// Đưa tốc độ tổng hợp về 1,0× — dùng cho nút "Đặt lại" của Section 4.
    func resetVieNeuSynthesisSpeed() {
        // Turbo không có tốc độ tổng hợp (hàng bị ẩn) ⇒ đừng âm thầm đặt lại giá trị của Nano.
        guard ttsManager.tool == "vieneu", !isVieNeuTurboSelected else { return }
        vieNeuSynthesisSpeed = 1.0
        UserDefaults.standard.set(1.0, forKey: VieNeuSynthesisPolicy.synthesisSpeedKey)
        ttsManager.invalidateVieNeuSynthesisSpeed()
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
    @ViewBuilder
    var vieNeuReaderSection: some View {
        NavigationLink(destination: VieNeuTTSSettingsView()) {
            Label("Cài đặt VieNeu TTS", systemImage: "waveform.badge.plus")
        }

        // Công tắc **riêng của VieNeu** cho từ điển phiên âm tiếng Nhật (chung cho Nano và Turbo). Mặc định **TẮT**: VieNeu
        // chỉ gấp macron về ASCII (`danzō` → `danzo`), xem `VieNeuJapanesePreprocessor`.
        Toggle("Áp dụng từ điển phiên âm VieNeu", isOn: $vieNeuJapaneseFlags.dictionaryEnabled)

        // Tên kiểu Nhật viết hoa ("Sasuke") đọc theo âm tiết thay vì theo luật chính tả tiếng Anh — mặc định **BẬT**,
        // chung cho Nano và Turbo. Xem `VieNeuJapaneseNameReader`.
        Toggle("Đọc tên Nhật theo âm tiết", isOn: $vieNeuJapaneseFlags.nameSyllablesEnabled)

        // Nano: đoạn có tên phiên âm theo âm tiết được thêm khung để không nuốt âm tiết ngắn (`VieNeuNameFrameBoost`).
        Picker("Đọc chậm đoạn có tên (Nano)", selection: $vieNeuJapaneseFlags.nameFrameBoost) {
            ForEach(VieNeuNameFrameBoost.Mode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.menu)

        // Từ điển tiếng Nhật: **đã tải ⇒ lối vào; chưa tải ⇒ cảnh báo + nút tải** — mở một màn trống thì người dùng không
        // biết phải làm gì.
        if vieNeuJapaneseFlags.dictionaryDownloaded {
            NavigationLink(destination: VieNeuJapaneseDictionaryView()) {
                Label("Từ điển phiên âm tiếng Nhật", systemImage: "character.book.closed")
            }
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("Chưa tải từ điển tiếng Nhật").font(.subheadline).foregroundColor(.secondary)
            }
            Button {
                downloadJapaneseDictionary()
            } label: {
                Label("Tải từ điển tiếng Nhật", systemImage: "arrow.down.circle")
            }
        }

        // Giọng nhân bản ("Giọng của tôi") nằm trong sheet chọn giọng từ 1.3.900.
    }

    /// Tiêu đề Section 3 "Quản lý riêng của trình đọc": VieNeu có nút "?" giải thích cấu hình cố định của hai model.
    @ViewBuilder
    var readerManagementHeader: some View {
        if ttsManager.tool == "vieneu" {
            SectionHelpHeader("Quản lý riêng của trình đọc", paragraphs: [
                "Nano luôn chạy Cân bằng (8 bước) + 2 luồng, không chờ bận. Turbo luôn 2 luồng trên lõi hiệu năng.",
                VieNeuJapaneseFlags.nameFrameBoostHelp
            ])
        } else {
            Text("Quản lý riêng của trình đọc")
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

    /// Tải từ điển tiếng Nhật rồi làm mới cờ "đã tải" ⇒ hàng **cảnh báo + nút tải** đổi thành **lối vào**
    /// ngay, không phải thoát màn rồi mở lại.
    func downloadJapaneseDictionary() {
        Task {
            do {
                try await VieNeuJapaneseDictionary.shared.downloadInitialDictionary()
                vieNeuJapaneseFlags.refresh()
                ToastManager.shared.show(message: "Tải từ điển tiếng Nhật thành công!", type: .success)
            } catch {
                ToastManager.shared.show(message: "Không thể tải từ điển: \(error.localizedDescription)", type: .error)
            }
        }
    }
}

/// Trạng thái của phần **tiếng Nhật** cho VieNeu (công tắc "Tự động phiên âm tiếng Nhật" bỏ ở 1.3.899).
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

    /// "Đọc tên Nhật theo âm tiết" (1.3.950) — mặc định **BẬT** (`VieNeuJapaneseNameReader.isEnabled`).
    @Published var nameSyllablesEnabled: Bool = true {
        didSet { UserDefaults.standard.set(nameSyllablesEnabled, forKey: VieNeuJapaneseNameReader.enabledKey) }
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
        nameSyllablesEnabled = VieNeuJapaneseNameReader.isEnabled
        nameFrameBoost = VieNeuNameFrameBoost.mode
        dictionaryDownloaded = VieNeuJapaneseDictionary.existsOnDisk()
    }
}
