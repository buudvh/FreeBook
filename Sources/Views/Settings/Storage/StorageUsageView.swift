import SwiftUI

/// Màn **Dung lượng** (Cài đặt › Thư Viện, 1.3.728): app đang chiếm bao nhiêu, máy còn trống bao nhiêu, và từng loại
/// dữ liệu xếp lớn → nhỏ (`StorageUsageScanner`). Ba loại xoá được (cache ảnh truyện tranh, file xuất, nhật ký) có
/// nút "Xoá" kèm hộp xác nhận (`StorageUsageCleaner`); xoá xong đo lại.
///
/// Số liệu nằm ở `StorageUsageRepository` (1.3.730): mở màn hiện ngay lần đo gần nhất kèm giờ đo, rồi đo lại ngầm; thoát
/// màn giữa chừng vẫn đo tiếp. Cả cây thư mục có thể hàng chục nghìn file (đoạn HLS, ảnh comic), nên hàng "Dung lượng"
/// ở Cài đặt không hiện số.
struct StorageUsageView: View {
    @State private var clearingCategory: StorageUsageCategory? = nil
    @State private var pendingClear: StorageUsageSnapshot.Entry? = nil

    /// Màu riêng cho 3 loại lớn nhất (thanh + ô màu của hàng); còn lại xám. Màu cố định, không dùng màu nhấn
    /// (luật `WHITE_TINT_FILL` cấm tô nền đặc bằng `Color.accentColor`).
    private static let highlightColors: [Color] = [.teal, .purple, .orange]
    private static let restColor = Color(UIColor.systemGray3)

    private var repository: StorageUsageRepository { .shared }
    private var snapshot: StorageUsageSnapshot? { repository.snapshot }
    private var isScanning: Bool { repository.isScanning }

    var body: some View {
        List {
            summaryCard
                .bookListPanelRow()
            if let snapshot {
                ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                    row(entry, color: color(at: index))
                        .bookListPanelRow()
                }
            }
        }
        .listStyle(.plain)
        .backPageTitle("Dung lượng")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isScanning {
                    // Đang đo (kể cả lượt chạy từ lần vào trước): vòng xoay thay cho ↻.
                    ProgressView()
                        .frame(width: 36, height: 38)
                        .accessibilityLabel("Đang đo")
                } else {
                    Button {
                        repository.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 38)
                    }
                    .disabled(clearingCategory != nil)
                    .accessibilityLabel("Đo lại")
                }
            }
        }
        // Hiện ngay số cũ, đo lại ngầm; lượt đo là của repository nên thoát màn vẫn chạy tiếp.
        .onAppear { repository.refresh() }
        .confirmationDialog(
            pendingClear.map { "Xoá \($0.category.title.lowercased()) (\(StorageUsageSnapshot.format($0.bytes)))?" } ?? "",
            isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
            titleVisibility: .visible,
            presenting: pendingClear
        ) { entry in
            Button("Xoá", role: .destructive) {
                Task { await clear(entry) }
            }
        } message: { entry in
            Text(entry.category.clearNote)
        }
    }

    // MARK: - Thẻ tổng

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App đang dùng")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let snapshot {
                Text(StorageUsageSnapshot.format(snapshot.appBytes))
                    .font(.system(size: 28, weight: .bold))
                Text(measuredText(snapshot.measuredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                usageBar(snapshot)
                if let total = snapshot.deviceTotalBytes, let available = snapshot.deviceAvailableBytes {
                    HStack {
                        Text("Máy đã dùng \(StorageUsageSnapshot.format(total - available)) / \(StorageUsageSnapshot.format(total))")
                        Spacer(minLength: 8)
                        Text("Còn trống \(StorageUsageSnapshot.format(available))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 4)
    }

    /// Thanh ngang chia theo tỉ lệ từng loại trên tổng app: 3 loại lớn nhất màu riêng, phần còn lại xám.
    private func usageBar(_ snapshot: StorageUsageSnapshot) -> some View {
        GeometryReader { proxy in
            let total = max(Double(snapshot.appBytes), 1)
            HStack(spacing: 0) {
                ForEach(Array(snapshot.entries.prefix(Self.highlightColors.count).enumerated()), id: \.element.id) { index, entry in
                    Rectangle()
                        .fill(Self.highlightColors[index])
                        .frame(width: proxy.size.width * Double(entry.bytes) / total)
                }
                Rectangle().fill(Self.restColor)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    // MARK: - Hàng

    private func row(_ entry: StorageUsageSnapshot.Entry, color: Color) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(entry.category.title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(StorageUsageSnapshot.format(entry.bytes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if entry.category.isClearable {
                if clearingCategory == entry.category {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Xoá") { pendingClear = entry }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .buttonStyle(.borderless)
                        .disabled(isScanning || clearingCategory != nil)
                }
            }
        }
    }

    private func color(at index: Int) -> Color {
        index < Self.highlightColors.count ? Self.highlightColors[index] : Self.restColor
    }

    /// "Đo lúc 14:32" (hôm nay) hoặc "Đo lúc 14:32 03/11"; đang đo thì thêm "· đang đo lại".
    private func measuredText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "HH:mm dd/MM"
        let base = "Đo lúc \(formatter.string(from: date))"
        return isScanning ? base + " · đang đo lại" : base
    }

    // MARK: - Xoá

    private func clear(_ entry: StorageUsageSnapshot.Entry) async {
        let category = entry.category
        let before = snapshot?.bytes(of: category) ?? entry.bytes
        clearingCategory = category
        await StorageUsageCleaner.clear(category)
        await repository.refreshAfterChange()
        clearingCategory = nil
        let freed = max(0, before - (snapshot?.bytes(of: category) ?? 0))
        ToastManager.shared.show(
            message: "Đã xoá \(category.title.lowercased()) (\(StorageUsageSnapshot.format(freed)))",
            type: .success,
            recordsInInbox: false
        )
    }
}
