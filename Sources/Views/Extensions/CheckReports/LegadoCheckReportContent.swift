import SwiftUI

/// Thân màn chi tiết của một báo cáo kiểm tra nguồn Legado **đã lưu** (chỉ xem): ô Đạt / Lỗi / Bỏ qua, phần "Lỗi do ai"
/// (`LegadoSourceCheckVerdictPanel`) và dòng từng nguồn (`LegadoSourceCheckRow`). Nút 🐞 chỉ hiện khi nguồn còn cài.
/// Không có Tắt / Gắn nhóm / Xoá nguồn lỗi hay chạy lại — những việc đó ở màn Kiểm tra nguồn.
struct LegadoCheckReportContent: View {
    let report: LegadoCorpusReport

    @State private var filter: LegadoSourceCheckFilter = .all
    @State private var debugPackageId: String?

    private var results: [LegadoCorpusReport.SourceResult] { report.sources ?? [] }

    var body: some View {
        let installed = installedNames
        let rows = results.filter { filter.matches($0) }
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                SourceCheckTile(title: "Đạt", value: report.passed, color: .green)
                SourceCheckTile(title: "Lỗi", value: max(0, report.attempted - report.passed), color: .red)
                SourceCheckTile(title: "Bỏ qua", value: report.skipped, color: .secondary)
            }
            .padding(.horizontal)
            LegadoSourceCheckVerdictPanel(results: results, filter: $filter)
            if rows.isEmpty {
                VStack {
                    Spacer()
                    Text("Không có nguồn nào ở mục này.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(rows.enumerated()), id: \.offset) { _, result in
                    LegadoSourceCheckRow(
                        result: result,
                        displayName: installed[result.packageId] ?? result.name,
                        onDebug: debugAction(for: result.packageId, installed: installed)
                    )
                }
                .listStyle(.plain)
            }
        }
        .navigationDestination(item: $debugPackageId) { id in
            LegadoSourceDebugView(packageId: id, sourceName: installedNames[id] ?? id)
        }
    }

    /// Nguồn đã gỡ ⇒ không có nút 🐞 (màn Gỡ lỗi cần `source.json` của nguồn).
    private func debugAction(for packageId: String, installed: [String: String]) -> (() -> Void)? {
        guard installed[packageId] != nil else { return nil }
        return { debugPackageId = packageId }
    }

    /// Tên hiển thị theo `packageId` của các nguồn **còn cài** trong báo cáo.
    private var installedNames: [String: String] {
        let wanted = Set(results.map(\.packageId))
        var table: [String: String] = [:]
        for summary in LegadoSourceRepository.shared.summaries where wanted.contains(summary.packageId) {
            table[summary.packageId] = summary.displayName
        }
        return table
    }
}
