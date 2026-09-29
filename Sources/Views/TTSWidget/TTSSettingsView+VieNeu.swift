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
}
