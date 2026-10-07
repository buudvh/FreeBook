import SwiftUI

/// Khung xương của màn **Khôi phục**, hiện **ngay** khi người dùng chạm "Khôi phục từ bản này" — trong lúc
/// `BackupCoordinator.prepareRestore` giải nén archive và đọc `manifest.json` ở nền.
///
/// ## Vì sao cần
/// Trước 1.3.475, `BackupHubView.startRestore` chỉ bật sheet **sau khi** `prepareRestore` xong. Suốt thời gian
/// giải nén, người dùng không thấy gì ngoài cú chạm ⇒ nút như không phản hồi, và với archive vài trăm MB thì
/// khoảng đó đủ dài để tưởng app treo. Nay sheet hiện tức thì và **tự thay** bằng nội dung thật khi
/// `coordinator.preparedRestore` khác `nil`.
///
/// ## Bố cục phải khớp `RestoreOptionsSheet`
/// Số hàng và thứ tự ở đây cố ý sao đúng màn thật — section "File sao lưu" (một hàng tên file thật + 8 hàng
/// xương), danh sách nhóm khôi phục, rồi 2 hàng toggle — để lúc nội dung thật tới thì chỉ có **chữ hiện ra**,
/// không có khung nhảy. Sửa bố cục `RestoreOptionsSheet` thì sửa cả file này.
///
/// ## Nút "Huỷ" vẫn bấm được
/// Cố ý giữ `Huỷ` hoạt động trong lúc đọc file: giải nén có thể lâu, và khoá người dùng trong một màn chỉ có
/// khung xương là đúng thứ trải nghiệm mà lượt này đang sửa. Đóng giữa chừng thì `startRestore` dọn thư mục
/// tạm ngay khi `prepareRestore` trả về.
///
/// Tái dùng `SkeletonView` dùng chung thay vì tự vẽ khối nhấp nháy — một định nghĩa "khung xương" cho cả app.
struct RestoreSkeletonView: View {
    /// Tên file đang đọc — **dữ liệu thật**, đã biết từ trước nên hiện luôn thay vì để xương.
    let sourceName: String
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Đang đọc file sao lưu…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("File sao lưu")) {
                    HStack {
                        Text("Tên file")
                            .font(.subheadline)
                        Spacer()
                        Text(sourceName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    ForEach(0..<8, id: \.self) { index in
                        skeletonRow(labelWidth: Self.summaryLabelWidths[index % Self.summaryLabelWidths.count])
                    }
                }

                Section(header: Text("Nhóm sẽ khôi phục")) {
                    ForEach(0..<6, id: \.self) { index in
                        skeletonToggleRow(labelWidth: Self.scopeLabelWidths[index % Self.scopeLabelWidths.count])
                    }
                }

                Section {
                    skeletonToggleRow(labelWidth: 150)
                    skeletonToggleRow(labelWidth: 178)
                }
            }
            .navigationTitle("Khôi phục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", action: onCancel)
                }
            }
        }
    }

    /// Độ rộng nhãn đổi qua lại giữa các hàng: hàng xương cùng một cỡ trông như bảng biểu, không như đang tải.
    private static let summaryLabelWidths: [CGFloat] = [74, 60, 88, 52, 96, 68, 82, 64]
    private static let scopeLabelWidths: [CGFloat] = [126, 158, 112, 170, 140, 96]

    private func skeletonRow(labelWidth: CGFloat) -> some View {
        HStack {
            SkeletonView(width: labelWidth, height: 12)
            Spacer(minLength: 12)
            SkeletonView(width: 46, height: 12)
        }
        .padding(.vertical, 2)
    }

    /// Hàng toggle: nhãn xương + một khối bo tròn cỡ `Toggle` để tổng thể nặng–nhẹ giống màn thật.
    private func skeletonToggleRow(labelWidth: CGFloat) -> some View {
        HStack {
            SkeletonView(width: labelWidth, height: 12)
            Spacer(minLength: 12)
            SkeletonView(width: 44, height: 26)
        }
        .padding(.vertical, 2)
    }
}
