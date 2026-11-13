import SwiftData
import SwiftUI

/// Trang **Dọn rác** (Cài đặt › Thư Viện › Dung lượng › Dọn rác): tổng dọn được, các nhóm "không còn dùng" và nút dọn
/// đỏ kèm hộp xác nhận. Luật nằm ở `JunkScanner`; quét / dọn qua `JunkCleanupCoordinator` (dọn = quét lại rồi chỉ xoá mục
/// có trong cả hai lượt). Giải thích chỉ sau nút "?" — trên màn không có chú thích.
///
/// Toast do View hiện (Services không gọi `ToastManager`); dọn xong quét lại trang này và đo lại màn Dung lượng.
struct JunkCleanupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var scan: JunkScanResult? = nil
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var showingConfirm = false

    private static let helpText = "Mỗi loại dữ liệu tự biết chính xác file nào nó đang dùng (model, giọng, gói Core ML đã tự kiểm, truyện còn trong thư viện…). Rác là file nằm trong thư mục của nó mà không có trong danh sách đó. File tạm chỉ dọn khi không có sao lưu, tải hay nhập nào đang chạy. Thư mục không rõ chủ chỉ hiện ở mục Khác, không tự xoá. Không đụng giọng nhân bản, dữ liệu AI, đăng nhập, bản sao lưu."

    var body: some View {
        List { Group {
            summaryCard
                .bookListPanelRow()
            if let scan, !scan.isEmpty {
                Text("Không còn dùng")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .bookListPanelRowChrome()
                ForEach(scan.groups) { group in
                    groupRow(group)
                        .bookListPanelRow()
                }
                cleanButton(totalBytes: scan.totalBytes)
                    .padding(.top, 8)
                    .bookListPanelRowChrome()
            }
        }.glassSheetRows() }
        .listStyle(.plain)
        .backPageTitle("Dọn rác")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SectionHelpButton(accessibilityLabel: "Giải thích Dọn rác", texts: [Text(Self.helpText)])
            }
        }
        .onAppear {
            if scan == nil {
                Task { await rescan() }
            }
        }
        .confirmationDialog(
            "Dọn \(StorageUsageSnapshot.format(scan?.totalBytes ?? 0)) rác?",
            isPresented: $showingConfirm,
            titleVisibility: .visible
        ) {
            Button("Dọn", role: .destructive) {
                Task { await clean() }
            }
        } message: {
            Text("Chỉ xoá các mục trong danh sách. Giọng nhân bản, dữ liệu AI, đăng nhập, bản sao lưu không bị đụng.")
        }
    }

    // MARK: - Thẻ tổng

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dọn được")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let scan {
                Text(scan.isEmpty ? "Không có rác" : StorageUsageSnapshot.format(scan.totalBytes))
                    .font(.system(size: 28, weight: .bold))
                if isScanning {
                    Text("Đang quét lại…")
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

    // MARK: - Nhóm

    private func groupRow(_ group: JunkScanResult.Group) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.icon(for: group.kind))
                .font(.subheadline)
                .foregroundStyle(.orange)
                .frame(width: 22)
            Text(group.kind.title)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(StorageUsageSnapshot.format(group.bytes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private static func icon(for kind: JunkGroupKind) -> String {
        switch kind {
        case .coreMLStale: return "cpu"
        case .labData: return "flask"
        case .partialDownloads: return "arrow.down.circle"
        case .staleTemporary: return "clock.arrow.circlepath"
        case .deletedBooks: return "book.closed"
        case .legacyExtensionCopy: return "puzzlepiece.extension"
        }
    }

    private func cleanButton(totalBytes: Int64) -> some View {
        Button {
            showingConfirm = true
        } label: {
            HStack(spacing: 8) {
                if isCleaning {
                    ProgressView()
                        .tint(.white)
                }
                Text(isCleaning ? "Đang dọn…" : "Dọn \(StorageUsageSnapshot.format(totalBytes))")
            }
        }
        .buttonStyle(.appFilled(.red))
        .disabled(isCleaning || isScanning)
    }

    // MARK: - Quét / dọn

    @MainActor
    private func rescan() async {
        guard !isScanning else { return }
        isScanning = true
        scan = await JunkCleanupCoordinator.preview(container: modelContext.container)
        isScanning = false
    }

    @MainActor
    private func clean() async {
        guard let shown = scan, !isCleaning else { return }
        isCleaning = true
        let result = await JunkCleanupCoordinator.run(shown, container: modelContext.container)
        isCleaning = false
        guard let result else {
            ToastManager.shared.show(message: "Đang dọn ở lượt khác, thử lại sau", type: .info, recordsInInbox: false)
            return
        }
        var message = result.removedBytes > 0
            ? "Đã dọn rác (\(StorageUsageSnapshot.format(result.removedBytes)))"
            : "Không còn gì để dọn"
        if result.failedCount > 0 {
            message += " · \(result.failedCount) mục chưa xoá được"
        }
        let type: ToastType = result.failedCount > 0 ? .error : (result.removedBytes > 0 ? .success : .info)
        ToastManager.shared.show(message: message, type: type, recordsInInbox: false)
        await rescan()
        // Màn Dung lượng đo lại (tổng, dòng "Dọn rác", dòng con TTS / Khác) — lượt của repository, thoát trang vẫn chạy.
        Task { await StorageUsageRepository.shared.refreshAfterChange() }
    }
}
