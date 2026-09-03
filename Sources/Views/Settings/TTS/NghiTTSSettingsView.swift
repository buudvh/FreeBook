import SwiftUI

struct NghiTTSSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var ttsManager = TTSManager.shared
    
    // Preprocessor Settings
    @AppStorage(PreprocessorSettingKey.numericNormalizationEnabled) private var preprocessorNumericNormalizationEnabled = true
    @AppStorage(PreprocessorSettingKey.dictionaryReplacementEnabled) private var preprocessorDictionaryReplacementEnabled = true
    @AppStorage(PreprocessorSettingKey.transliterationEnabled) private var preprocessorTransliterationEnabled = true
    /// Công tắc này trước đây nằm ở màn "Thử phiên âm" (đã xoá ở 1.3.328). Giữ lại ở đây vì nó là
    /// đường thoát duy nhất khi IPA của espeak đọc sai một loạt từ tiếng Anh.
    @AppStorage(EnglishPhonemeTransliterator.useEspeakKey) private var useEspeakIPAForEnglish = true
    
    // Pause Durations (seconds)
    @AppStorage("newlinePauseDuration") private var newlinePause = 0.4
    @AppStorage("sentencePauseDuration") private var sentencePause = 0.3
    @AppStorage("phrasePauseDuration") private var phrasePause = 0.15
    @AppStorage("bracketPauseDuration") private var bracketPause = 0.1
    @AppStorage("paragraphPauseDuration") private var paragraphPause = 0.5
    
    var body: some View {
        Form {
            Section("Tiền xử lý text") {
                Toggle("Chuẩn hóa cách đọc số", isOn: $preprocessorNumericNormalizationEnabled)
                Toggle("Áp dụng thay thế từ điển", isOn: $preprocessorDictionaryReplacementEnabled)
                Toggle("Phiên âm tiếng Anh/Nhật", isOn: $preprocessorTransliterationEnabled)
                Toggle("Dùng IPA của espeak cho tiếng Anh", isOn: $useEspeakIPAForEnglish)

                NavigationLink(destination: NghiTTSTextToolView()) {
                    Label("Thử giọng đọc", systemImage: "text.bubble")
                }
            }
            
            Section("Cấu hình khoảng ngắt (giây)") {
                PrecisionSliderView(title: "Xuống dòng:", value: $newlinePause, defaultValue: 0.4)
                PrecisionSliderView(title: "Cuối câu (. ! ?):", value: $sentencePause, defaultValue: 0.3)
                PrecisionSliderView(title: "Giữa câu (, ; :):", value: $phrasePause, defaultValue: 0.15)
                PrecisionSliderView(title: "Dấu ngoặc (( ) [ ] { } 「 」 etc.):", value: $bracketPause, defaultValue: 0.1)
                PrecisionSliderView(title: "Cuối đoạn văn:", value: $paragraphPause, defaultValue: 0.5)
                
                Button("Đặt lại mặc định") {
                    newlinePause = 0.4
                    sentencePause = 0.3
                    phrasePause = 0.15
                    bracketPause = 0.1
                    paragraphPause = 0.5
                }
                .foregroundStyle(.red)
            }
            Section("Tải trước & Bộ đệm âm thanh (NghiTTS)") {
                Stepper(
                    value: Binding(
                        get: { ttsManager.nghittsSafeCachedTimeThreshold },
                        set: { ttsManager.setNghiTTSSafeCachedTimeThreshold($0) }
                    ),
                    in: 4...20,
                    step: 1
                ) {
                    HStack {
                        Text("Ngưỡng nạp bộ đệm:")
                        Spacer()
                        Text("\(Int(ttsManager.nghittsSafeCachedTimeThreshold))s")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                }
                Text("Tự động tổng hợp thêm âm thanh khi thời lượng đệm âm thanh liên tục còn lại giảm xuống dưới \(Int(ttsManager.nghittsSafeCachedTimeThreshold)) giây.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Cấu hình NghiTTS")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrecisionSliderView: View {
    let title: String
    @Binding var value: Double
    let defaultValue: Double
    var range: ClosedRange<Double> = 0.0...2.0
    var step: Double = 0.01
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.body)
                Spacer()
                
                // Minus button
                Button(action: {
                    let target = value - step
                    let rounded = (target * 100).rounded() / 100
                    value = max(range.lowerBound, min(range.upperBound, rounded))
                }) {
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .frame(width: 32, height: 32)
                
                // Value text
                Text(String(format: "%.2f s", value))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50, alignment: .center)
                
                // Plus button
                Button(action: {
                    let target = value + step
                    let rounded = (target * 100).rounded() / 100
                    value = max(range.lowerBound, min(range.upperBound, rounded))
                }) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .frame(width: 32, height: 32)
                
                // Reset button
                Button(action: {
                    value = defaultValue
                }) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .frame(width: 32, height: 32)
            }
            
            // Slider row with min/max labels
            HStack(spacing: 8) {
                Text(String(format: "%.1f", range.lowerBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Slider(value: $value, in: range, step: step)
                
                Text(String(format: "%.1f", range.upperBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
