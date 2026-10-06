import SwiftUI

/// Khối "Hiệu năng" của `ZeroTTSTestView` — quét **số luồng ORT**.
///
/// Tách khỏi file chính vì trần **400 dòng vật lý** của repo (file chính đã **357**). Đây là **extension
/// cùng file type** nên `@State` của view vẫn dùng được; thành viên dùng chéo file buộc phải để mức
/// `internal` (Swift giới hạn `private` theo file) — cùng khuôn `VieNeuTTSTestView+Sections`.
///
/// ## Vì sao phải có nút "Áp dụng" chứ không tự quét
/// Số luồng nằm trong `OrtSessionOptions` **lúc tạo session**; không có API nào đổi số luồng của một
/// `OrtSession` đã tạo. Nên mỗi mức tốn lại ~17 s nạp 903 MB + ~1 s làm nóng — không thể quét ngầm trong
/// một lượt bấm ▶.
///
/// ## Vì sao nhiều luồng hơn **không chắc** nhanh hơn
/// `local_frame_decode` chạy ở **độ dài chuỗi 1** (đúng một frame mỗi lượt), nên mỗi phép nhân ma trận rất
/// nhỏ và phần lớn thời gian là chi phí điều phối op chứ không phải tính toán. iPhone lại có 2 nhân hiệu
/// năng + 4 nhân tiết kiệm: đẩy việc sang nhân tiết kiệm có thể làm **chậm đi**. Đây đúng là câu hỏi mà
/// phép quét tồn tại để trả lời bằng số, không bằng suy đoán.
extension ZeroTTSTestView {
    @ViewBuilder
    var performanceSection: some View {
        Section {
            Stepper(value: $threadCount, in: ZeroTTSEngine.threadCountRange) {
                HStack {
                    Text("Luồng ORT")
                    Spacer()
                    Text("\(threadCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .disabled(isReloadingEngine || isSynthesizing)

            LabeledContent("Đang chạy", value: "\(engine?.threadCount ?? 0) luồng")

            Button {
                reloadEngine()
            } label: {
                Label(isReloadingEngine ? "Đang dựng lại engine…" : "Áp dụng & dựng lại engine",
                      systemImage: "arrow.clockwise")
            }
            .disabled(isReloadingEngine || isSynthesizing || !isModelReady)
        } header: {
            Text("Hiệu năng")
        } footer: {
            Text("Số luồng nằm trong `OrtSessionOptions` lúc tạo session nên **không sửa được tại chỗ** — đổi là phải dựng lại cả bốn session: tốn lại ~17 s nạp 903 MB + ~1 s làm nóng. Sau khi dựng lại, bấm ▶ rồi so `local_decode … ms/frame` giữa các mức. **Nhiều luồng hơn không chắc nhanh hơn**: `local_frame_decode` chạy ở độ dài chuỗi 1 nên mỗi phép nhân ma trận rất nhỏ, mà iPhone có 2 nhân hiệu năng + 4 nhân tiết kiệm.")
        }
    }

    /// Dựng lại engine với số luồng đang chọn.
    func reloadEngine() {
        guard let engine else { return }
        stopPlayback()
        let target = threadCount
        isReloadingEngine = true
        isError = false
        statusMessage = "Đang dựng lại engine với \(target) luồng…"
        Task {
            do {
                try await engine.setThreadCountAsync(target)
                await MainActor.run {
                    isReloadingEngine = false
                    statusMessage = "Đã dựng lại engine với \(target) luồng. Bấm ▶ rồi so ms/frame."
                }
            } catch {
                await MainActor.run {
                    isReloadingEngine = false
                    isError = true
                    statusMessage = "Dựng lại engine thất bại: \(error.localizedDescription)"
                }
            }
        }
    }
}
