import SwiftUI

/// Đang tìm mà không còn giọng nào khớp — cùng câu với sheet chọn giọng VieNeu.
struct TTSVoiceNoMatchSection: View {
    /// Chữ người dùng gõ (chưa chuẩn hoá).
    let query: String

    var body: some View {
        Section {
            Text("Không có giọng nào tên “\(query.trimmingCharacters(in: .whitespaces))”.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
