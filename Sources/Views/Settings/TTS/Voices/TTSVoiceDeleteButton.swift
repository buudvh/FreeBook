import SwiftUI

/// Nút 🗑 cuối hàng giọng offline đã tải ở sheet chọn giọng (`TTSVoiceListRow` của NghiTTS, `VieNeuVoiceListRow` của
/// giọng Turbo tải về). Nút riêng `.borderless` để `List` tách chạm khỏi thân hàng; chỉ báo ý định — hỏi lại và xoá là
/// việc của danh sách.
struct TTSVoiceDeleteButton: View {
    let voiceName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .semibold))
                // `.red` literal có chủ ý: hành động xoá, không theo màu nhấn.
                .foregroundColor(.red)
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Xoá giọng \(voiceName)")
    }
}
