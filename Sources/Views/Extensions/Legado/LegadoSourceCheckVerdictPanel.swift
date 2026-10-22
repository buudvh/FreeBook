import SwiftUI

/// Phần "Lỗi do ai" của màn Kiểm tra nguồn: hàng ô đếm theo kết luận (Web chặn / sập · Nguồn lỗi thời · Cần xác minh /
/// đăng nhập · Nghi do app · Chưa rõ — chỉ ô có số > 0; chạm ô để lọc) và hàng chip lọc (Tất cả / Lỗi / Đạt + chip
/// của từng kết luận đang có nguồn).
///
/// Chip cơ bản đang chọn theo kiểu `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn mờ 18%, viền 60%); chip/ô kết luận
/// dùng màu của kết luận, cũng chỉ ở dạng mờ.
struct LegadoSourceCheckVerdictPanel: View {
    let results: [LegadoCorpusReport.SourceResult]
    @Binding var filter: LegadoSourceCheckFilter

    struct VerdictCount: Identifiable {
        let verdict: LegadoFailureVerdict
        let count: Int
        var id: String { verdict.rawValue }
    }

    private var counts: [VerdictCount] {
        var table: [LegadoFailureVerdict: Int] = [:]
        for result in results where result.outcome == .failed {
            if let verdict = result.verdict { table[verdict, default: 0] += 1 }
        }
        return LegadoFailureVerdict.allCases.compactMap { verdict in
            guard let count = table[verdict], count > 0 else { return nil }
            return VerdictCount(verdict: verdict, count: count)
        }
    }

    var body: some View {
        let items = counts
        VStack(alignment: .leading, spacing: 8) {
            if !items.isEmpty {
                Text("Lỗi do ai")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            verdictTile(item)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LegadoSourceCheckFilter.basic) { item in
                        basicChip(item)
                    }
                    ForEach(items) { item in
                        verdictChip(item)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Ô đếm

    private func verdictTile(_ item: VerdictCount) -> some View {
        let isSelected = filter == .verdict(item.verdict)
        return Button(action: { toggle(.verdict(item.verdict)) }) {
            VStack(spacing: 2) {
                Text("\(item.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundColor(item.verdict.tint)
                Text(item.verdict.label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(minWidth: 96)
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(item.verdict.tint.opacity(isSelected ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? item.verdict.tint.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.verdict.label): \(item.count) nguồn")
    }

    // MARK: - Chip

    private func basicChip(_ item: LegadoSourceCheckFilter) -> some View {
        let isSelected = item == filter
        return Button(action: { filter = item }) {
            Text(item.label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .clipShape(Capsule())
                // App đặt `.tint(.white)` toàn cục ⇒ màu nhấn là trắng: chip chọn theo kiểu `ExtensionKindFilterBar`.
                .overlay(Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func verdictChip(_ item: VerdictCount) -> some View {
        let isSelected = filter == .verdict(item.verdict)
        let tint = item.verdict.tint
        return Button(action: { toggle(.verdict(item.verdict)) }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text("\(item.verdict.label) \(item.count)")
                    .font(.caption.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isSelected ? tint.opacity(0.18) : Color(.secondarySystemBackground))
            .foregroundColor(isSelected ? tint : .primary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? tint.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Chạm lại bộ lọc đang chọn ⇒ về "Lỗi".
    private func toggle(_ item: LegadoSourceCheckFilter) {
        filter = filter == item ? .failed : item
    }
}
