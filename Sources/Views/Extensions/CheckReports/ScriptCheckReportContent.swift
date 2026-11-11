import SwiftUI

/// Thân màn chi tiết của một báo cáo kiểm tra tiện ích JS **đã lưu** (chỉ xem).
///
/// - Một tiện ích ⇒ kết quả từng script ngay tại màn (`ExtensionCheckDetailContent`).
/// - Nhiều tiện ích ⇒ ô Đạt đủ / Có lỗi / Chưa xong, chip lọc, mỗi tiện ích một dòng (`ExtensionCheckBatchRow`); chạm ⇒
///   đẩy kết quả từng script của tiện ích đó.
///
/// Báo cáo đọc từ file không có link lỗi (`errorLink` không ghi vào JSON) nên không có nút "Mở link lỗi"; không chạy lại,
/// không gỡ tiện ích — những việc đó ở màn Kiểm tra tiện ích.
struct ScriptCheckReportContent: View {
    let report: ExtensionCheckReport

    @State private var filter: ExtensionCheckFilter = .all
    @State private var openedPackageId: String?

    var body: some View {
        Group {
            if report.totalExtensions == 1, let only = report.results.first {
                ExtensionCheckDetailContent(result: only, openingLink: .constant(nil))
            } else {
                batchContent
            }
        }
        .navigationDestination(item: $openedPackageId) { id in
            ExtensionCheckDetailContent(result: report.result(packageId: id), openingLink: .constant(nil))
                .backPageTitle(report.result(packageId: id)?.name ?? id)
        }
    }

    private var batchContent: some View {
        let rows = report.results.filter { filter.matches($0) }
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                SourceCheckTile(title: "Đạt đủ", value: report.fullyPassed, color: .green)
                SourceCheckTile(title: "Có lỗi", value: report.withProblems, color: .red)
                SourceCheckTile(title: "Chưa xong", value: max(0, report.totalExtensions - report.completed), color: .secondary)
            }
            .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExtensionCheckFilter.allCases) { item in
                        ExtensionCheckFilterChip(item: item, isSelected: item == filter) { filter = item }
                    }
                }
                .padding(.horizontal)
            }
            if rows.isEmpty {
                VStack {
                    Spacer()
                    Text("Không có tiện ích nào ở mục này.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rows) { result in Group {
                    Button(action: { openedPackageId = result.packageId }) {
                        ExtensionCheckBatchRow(result: result)
                    }
                    .buttonStyle(.plain)
                }.glassSheetRows() }
                .listStyle(.plain)
            }
        }
    }
}
