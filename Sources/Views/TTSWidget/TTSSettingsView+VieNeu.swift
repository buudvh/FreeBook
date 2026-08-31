import SwiftUI

/// Phần giao diện của hai engine on-device trong màn Cài đặt TTS.
///
/// Tách khỏi `TTSSettingsView.swift` vì file đó đã ở baseline 519 dòng của `check_architecture.py`
/// và chỉ được phép **giảm**, không được tăng.
extension TTSSettingsView {

    /// Chọn engine cho nhánh `nghitts`. Chỉ hiện khi nhánh đó đang được chọn.
    ///
    /// Dùng `Binding(get:set:)` chứ không phải `$ttsManager.nghiEngineKind`: `nghiEngineKind` là
    /// computed property đọc/ghi UserDefaults (xem `TTSManager+LocalEngine`), không phải `@Published`,
    /// vì `TTSManager.swift` đã vượt baseline dòng nên không nhận thêm stored property.
    @ViewBuilder
    var localEnginePicker: some View {
        if ttsManager.tool == "nghitts" {
            Picker("Engine offline", selection: Binding(
                get: { ttsManager.nghiEngineKind },
                set: { ttsManager.nghiEngineKind = $0 }
            )) {
                ForEach(TTSManager.LocalEngineKind.allCases, id: \.rawValue) { kind in
                    Text(kind.displayName).tag(kind.rawValue)
                }
            }
            .pickerStyle(.menu)

            if ttsManager.localEngineKind == .vieneu, !ttsManager.isVieNeuModelInstalled {
                Text("Chưa tải bộ model VieNeu (~274 MB). Vào Cài đặt → Quản lý model để tải.")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder
    var piperVoicePicker: some View {
        let downloadedVoices = availableVoices.filter { isModelDownloaded($0) }
        if downloadedVoices.isEmpty {
            Text("Chưa tải giọng đọc NghiTTS nào")
                .foregroundColor(.secondary)
        } else {
            Picker("Giọng đọc NghiTTS", selection: $ttsManager.selectedVoice) {
                ForEach(downloadedVoices, id: \.name) { voice in
                    Text(voice.name).tag(voice.name)
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// 20 giọng preset của VieNeu.
    ///
    /// Lưu vào khoá riêng `vieneuVoice`, **không** dùng chung `selectedVoice` với Piper: hai bộ tên
    /// không giao nhau nên dùng chung một khoá là đổi engine xong không còn giọng hợp lệ.
    @ViewBuilder
    var vieNeuVoicePicker: some View {
        let voices = ttsManager.vieNeuVoices
        if voices.isEmpty {
            Text(
                ttsManager.isVieNeuModelInstalled
                    ? "Không đọc được danh sách giọng VieNeu"
                    : "Chưa tải bộ model VieNeu"
            )
            .foregroundColor(.secondary)
        } else {
            Picker("Giọng đọc VieNeu", selection: Binding(
                get: {
                    let stored = ttsManager.vieNeuVoiceName
                    return voices.contains(where: { $0.name == stored })
                        ? stored
                        : (voices.first?.name ?? "")
                },
                set: { ttsManager.vieNeuVoiceName = $0 }
            )) {
                ForEach(voices) { voice in
                    Text(voice.displayLabel).tag(voice.name)
                }
            }
            .pickerStyle(.menu)

            if let current = voices.first(where: { $0.name == ttsManager.vieNeuVoiceName }),
               !current.description.isEmpty {
                Text(current.description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}
