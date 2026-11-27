import SwiftUI

/// Sắp xếp của thẻ duyệt name (`ReaderAINameReviewCardView`): kiểu sắp, menu ⇅ và phép sắp. Tách khỏi thẻ để thẻ giữ dưới
/// 400 dòng. Danh sách **chỉ** sắp lại lúc mở thẻ (`onAppear`) hoặc khi chọn ở menu — tích / bỏ tích, sửa nghĩa, cờ NE / VP
/// tra lại không làm hàng nhảy chỗ.
extension ReaderAINameReviewCardView {
    public enum SortMode {
        case selectedFirst
        case alphabetical
        /// "Nhiều lần nhất": số lần giảm dần, rồi chữ Hán tăng dần (đúng thứ tự bộ lọc name local trả).
        case mostFrequent
        /// "Chưa có trước" (mặc định luồng lọc local, kể cả khi mở lại gói tạm — anh Bửu 2026-11-27, thay kiểu "Chưa chọn
        /// trước" của 1.3.1092 mà anh nói đã yêu cầu nhầm): name **chưa có** trong từ điển — không badge NE (Name riêng /
        /// chung) hay VP — lên đầu; mỗi nhóm số lần giảm dần, hoà thì chữ Hán tăng dần.
        /// Vd 炽翎 735 → 赤玄子 43 → 李印生 (NE) 4284 → 穆小鱼 (NE) 1287.
        case notInDictionaryFirst
    }

    /// Hai kiểu theo số lần chỉ có trong menu khi thẻ mở với một trong hai kiểu đó (luồng lọc local) — luồng AI giữ menu cũ.
    var offersFrequencySorts: Bool {
        initialSortMode == .notInDictionaryFirst || initialSortMode == .mostFrequent
    }

    var sortChipLabel: String {
        switch sortMode {
        case .selectedFirst: return "Đã chọn"
        case .alphabetical: return "A-Z"
        case .mostFrequent: return "Nhiều lần"
        case .notInDictionaryFirst: return "Chưa có"
        }
    }

    /// Nút ⇅ trên đầu thẻ: menu các kiểu sắp + "Sắp xếp lại ngay".
    var sortMenu: some View {
        Menu {
            if offersFrequencySorts {
                sortMenuButton(.notInDictionaryFirst, title: "Chưa có trước")
                sortMenuButton(.mostFrequent, title: "Nhiều lần nhất")
            }
            sortMenuButton(.selectedFirst, title: "Đã chọn trước")
            sortMenuButton(.alphabetical, title: "Từ A → Z (Hán Việt)")

            Divider()

            Button {
                applySorting()
            } label: {
                Label("Sắp xếp lại ngay", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortChipLabel)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(red: 90/255.0, green: 170/255.0, blue: 255/255.0))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.08))
            .cornerRadius(6)
        }
    }

    /// Một mục của menu sắp xếp: chọn ⇒ sắp lại ngay; kiểu đang dùng có dấu ✓.
    private func sortMenuButton(_ mode: SortMode, title: String) -> some View {
        Button {
            sortMode = mode
            applySorting()
        } label: {
            HStack {
                Text(title)
                if sortMode == mode {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    /// Sắp cả `names` (kể cả mục đang bị ô tìm / chip ẩn) theo `sortMode`.
    func applySorting() {
        switch sortMode {
        case .mostFrequent:
            names.sort { (a, b) -> Bool in
                if a.occurrenceCount != b.occurrenceCount {
                    return a.occurrenceCount > b.occurrenceCount
                }
                return a.original < b.original
            }
        case .notInDictionaryFirst:
            names.sort { (a, b) -> Bool in
                let aKnown = a.hasInBookNames || a.hasInBookVP
                let bKnown = b.hasInBookNames || b.hasInBookVP
                if aKnown != bKnown {
                    return !aKnown
                }
                if a.occurrenceCount != b.occurrenceCount {
                    return a.occurrenceCount > b.occurrenceCount
                }
                return a.original < b.original
            }
        case .selectedFirst:
            names.sort { (a, b) -> Bool in
                if a.isSelected != b.isSelected {
                    return a.isSelected && !b.isSelected
                }
                let aStr = a.suggestedMeaning.isEmpty ? a.original : a.suggestedMeaning
                let bStr = b.suggestedMeaning.isEmpty ? b.original : b.suggestedMeaning
                return aStr.localizedStandardCompare(bStr) == .orderedAscending
            }
        case .alphabetical:
            names.sort { (a, b) -> Bool in
                let aStr = a.suggestedMeaning.isEmpty ? a.original : a.suggestedMeaning
                let bStr = b.suggestedMeaning.isEmpty ? b.original : b.suggestedMeaning
                return aStr.localizedStandardCompare(bStr) == .orderedAscending
            }
        }
    }
}
