import SwiftUI

/// Màn **Dung lượng** (Cài đặt › Thư Viện, 1.3.728): app đang chiếm bao nhiêu, máy còn trống bao nhiêu, và từng loại
/// dữ liệu xếp lớn → nhỏ (`StorageUsageScanner`). Ba loại xoá được (cache ảnh truyện tranh, file xuất, nhật ký) có
/// nút "Xoá" kèm hộp xác nhận (`StorageUsageCleaner`); xoá xong đo lại.
///
/// Đo trên luồng nền mỗi lần mở màn và khi bấm ↻ — cả cây thư mục có thể hàng chục nghìn file (đoạn HLS, ảnh comic),
/// nên hàng "Dung lượng" ở Cài đặt không hiện số.
struct StorageUsageView: View {
    @State private var snapshot: StorageUsageSnapshot? = nil
    @State private var isScanning = false
    @State private var clearingCategory: StorageUsageCategory? = nil
    @State private var pendingClear: StorageUsageSnapshot.Entry? = nil

    /// Màu riêng cho 3 loại lớn nhất (thanh + ô màu của hàng); còn lại xám. Màu cố định, không dùng màu nhấn
    /// (luật `WHITE_TINT_FILL` cấm tô nền đặc bằng `Color.accentColor`).
    private static let highlightColors: [Color] = [.teal, .purple, .orange]
    private static let restColor = Color(UIColor.systemGray3)

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
                Button {
                    Task { await scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 38)
                }
                .disabled(isScanning || clearingCategory != nil)
                .accessibilityLabel("Đo lại")
            }
        }
        .task { await scan() }
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

    // MARK: - Đo / xoá

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        let result = await Task.detached(priority: .utility) { StorageUsageScanner.scan() }.value
        snapshot = result
        isScanning = false
    }

    private func clear(_ entry: StorageUsageSnapshot.Entry) async {
        let category = entry.category
        let before = snapshot?.bytes(of: category) ?? entry.bytes
        clearingCategory = category
        await StorageUsageCleaner.clear(category)
        await scan()
        clearingCategory = nil
        let freed = max(0, before - (snapshot?.bytes(of: category) ?? 0))
        ToastManager.shared.show(
            message: "Đã xoá \(category.title.lowercased()) (\(StorageUsageSnapshot.format(freed)))",
            type: .success,
            recordsInInbox: false
        )
    }
}
